from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.db import set_audit_user

from .models import Permiso, Rol, RolPermiso, TokenRevocado, Usuario, UsuarioRol
from .services import obtener_codigo_vigente


def _verificar_unico(campo, valor, mensaje, excluir_pk=None):
    """Unicidad sin distinguir mayúsculas (igual que los índices lower() de la BD)."""
    qs = Usuario.objects.filter(**{f"{campo}__iexact": valor})
    if excluir_pk is not None:
        qs = qs.exclude(pk=excluir_pk)
    if qs.exists():
        raise serializers.ValidationError(mensaje)
    return valor


def _validar_clave(clave, usuario, campo):
    try:
        validate_password(clave, usuario)
    except DjangoValidationError as exc:
        raise serializers.ValidationError({campo: list(exc.messages)})


def _campo_clave(**kwargs):
    # trim_whitespace=False: no se debe alterar una contraseña; max_length evita hashear textos enormes
    return serializers.CharField(
        write_only=True, trim_whitespace=False, max_length=128, style={"input_type": "password"}, **kwargs
    )


def _resolver_roles(codigos):
    codigos = {c.strip().upper() for c in codigos}
    roles = list(Rol.objects.filter(codigo__in=codigos, activo=True))
    faltantes = codigos - {r.codigo for r in roles}
    if faltantes:
        raise serializers.ValidationError(f"Roles inexistentes o inactivos: {', '.join(sorted(faltantes))}.")
    return roles


class UsuarioPerfilSerializer(serializers.ModelSerializer):
    ultimo_login = serializers.DateTimeField(source="last_login", read_only=True)
    roles = serializers.SerializerMethodField()
    permisos = serializers.SerializerMethodField()

    class Meta:
        model = Usuario
        fields = [
            "id", "tipo_documento", "numero_documento", "nombres", "apellidos",
            "username", "email", "telefono", "activo", "ultimo_login", "roles", "permisos",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_roles(self, obj):
        return obj.codigos_roles()

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_permisos(self, obj):
        return sorted(obj.codigos_permisos())


class LoginSerializer(TokenObtainPairSerializer):
    """Acepta usuario o correo en el campo `username`. Devuelve tokens + perfil."""

    def validate(self, attrs):
        data = super().validate(attrs)  # lanza 401 si credenciales inválidas o usuario inactivo
        set_audit_user(self.user.pk)
        self.user.last_login = timezone.now()
        self.user.save(update_fields=["last_login"])
        data["usuario"] = UsuarioPerfilSerializer(self.user).data
        return data


class RefreshSerializer(TokenRefreshSerializer):
    """Igual que el original, pero rechaza refresh tokens revocados en el logout."""

    def validate(self, attrs):
        try:
            refresh = RefreshToken(attrs["refresh"])
        except TokenError as exc:
            raise InvalidToken(exc.args[0])
        if TokenRevocado.objects.filter(jti=refresh["jti"]).exists():
            raise InvalidToken("El token fue revocado.")
        return super().validate(attrs)


class LogoutSerializer(serializers.Serializer):
    refresh = serializers.CharField()


class RegistroSerializer(serializers.ModelSerializer):
    """Autorregistro: SIEMPRE crea un RESIDENTE. Rol y estado nunca vienen del cliente."""

    # Sin '@' en el username: el login acepta usuario o correo en el mismo campo.
    username = serializers.RegexField(
        r"^[A-Za-z0-9._-]{3,60}$",
        error_messages={"invalid": "Usa de 3 a 60 caracteres: letras, números, punto, guion o guion bajo."},
    )
    email = serializers.EmailField(max_length=150)
    password = _campo_clave()

    class Meta:
        model = Usuario
        fields = [
            "tipo_documento", "numero_documento", "nombres", "apellidos",
            "username", "email", "telefono", "password",
        ]

    def validate_username(self, valor):
        return _verificar_unico("username", valor, "Este nombre de usuario ya está en uso.")

    def validate_email(self, valor):
        return _verificar_unico("email", valor, "Este correo ya está registrado.")

    def validate(self, attrs):
        tipo = attrs.get("tipo_documento", Usuario.TipoDocumento.CC)
        if Usuario.objects.filter(tipo_documento=tipo, numero_documento=attrs["numero_documento"]).exists():
            raise serializers.ValidationError({"numero_documento": "Ya existe un usuario con este documento."})
        _validar_clave(attrs["password"], Usuario(username=attrs["username"], email=attrs["email"]), "password")
        return attrs

    def create(self, validated_data):
        password = validated_data.pop("password")
        usuario = Usuario.objects.create_user(password=password, **validated_data)
        # El INSERT del usuario queda en auditoría sin autor (aún no existía su id);
        # desde aquí los cambios sí se atribuyen a la persona recién registrada.
        set_audit_user(usuario.pk)
        UsuarioRol.objects.create(usuario=usuario, rol=Rol.objects.get(codigo="RESIDENTE"))
        return usuario


class PerfilUpdateSerializer(serializers.ModelSerializer):
    """Lo único que el usuario puede editar de sí mismo."""

    email = serializers.EmailField(max_length=150)

    class Meta:
        model = Usuario
        fields = ["nombres", "apellidos", "telefono", "email"]

    def validate_email(self, valor):
        return _verificar_unico(
            "email", valor, "Este correo ya está registrado.", excluir_pk=self.instance.pk
        )

    def update(self, instance, validated_data):
        for campo, valor in validated_data.items():
            setattr(instance, campo, valor)
        instance.save(update_fields=list(validated_data))  # no toca password_hash ni otras columnas
        return instance


class CambiarPasswordSerializer(serializers.Serializer):
    password_actual = _campo_clave()
    password_nueva = _campo_clave()

    def validate(self, attrs):
        usuario = self.context["request"].user
        if not usuario.check_password(attrs["password_actual"]):
            raise serializers.ValidationError({"password_actual": "La contraseña actual es incorrecta."})
        if attrs["password_actual"] == attrs["password_nueva"]:
            raise serializers.ValidationError(
                {"password_nueva": "La nueva contraseña debe ser distinta de la actual."}
            )
        _validar_clave(attrs["password_nueva"], usuario, "password_nueva")
        return attrs


# --- recuperación de contraseña (RF4) -----------------------------------------
class SolicitarRecuperacionSerializer(serializers.Serializer):
    identificador = serializers.CharField(max_length=150, help_text="Correo o nombre de usuario")


class RestablecerPasswordSerializer(serializers.Serializer):
    identificador = serializers.CharField(max_length=150)
    codigo = serializers.RegexField(r"^\d{6}$", error_messages={"invalid": "El código tiene 6 dígitos."})
    password_nueva = _campo_clave()

    def validate(self, attrs):
        try:
            usuario = Usuario.objects.get_by_natural_key(attrs["identificador"])
        except Usuario.DoesNotExist:
            usuario = None
        registro = obtener_codigo_vigente(usuario, attrs["codigo"]) if usuario and usuario.activo else None
        if registro is None:  # mismo mensaje para cuenta inexistente, código errado o vencido
            raise serializers.ValidationError({"codigo": "Código inválido o vencido."})
        # La clave se valida antes de consumir el código: una clave débil no lo gasta.
        _validar_clave(attrs["password_nueva"], usuario, "password_nueva")
        attrs["usuario"], attrs["registro"] = usuario, registro
        return attrs


# --- administración de usuarios (RF1, RF7, RF8, RF9) -----------------------------
class UsuarioListaSerializer(serializers.ModelSerializer):
    ultimo_login = serializers.DateTimeField(source="last_login", read_only=True)
    roles = serializers.SerializerMethodField()

    class Meta:
        model = Usuario
        fields = [
            "id", "tipo_documento", "numero_documento", "nombres", "apellidos",
            "username", "email", "telefono", "activo", "ultimo_login", "roles",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_roles(self, obj):
        # 1 consulta por fila (máx. 20 por página); optimizable con prefetch si hiciera falta
        return obj.codigos_roles()


class UsuarioAdminCreateSerializer(RegistroSerializer):
    """Alta por el administrador: igual que el registro, pero eligiendo los roles."""

    roles = serializers.ListField(
        child=serializers.CharField(), required=False, help_text="Códigos de rol. Por defecto: RESIDENTE"
    )

    class Meta(RegistroSerializer.Meta):
        fields = RegistroSerializer.Meta.fields + ["roles"]

    def validate_roles(self, codigos):
        return _resolver_roles(codigos)

    def create(self, validated_data):
        roles = validated_data.pop("roles", None)
        if roles is None:
            roles = [Rol.objects.get(codigo="RESIDENTE")]
        password = validated_data.pop("password")
        usuario = Usuario.objects.create_user(password=password, **validated_data)
        por = self.context["request"].user
        for rol in roles:
            UsuarioRol.objects.create(usuario=usuario, rol=rol, asignado_por=por)
        return usuario


class AsignarRolesSerializer(serializers.Serializer):
    roles = serializers.ListField(child=serializers.CharField(), allow_empty=False)

    def validate_roles(self, codigos):
        return _resolver_roles(codigos)


class PermisoSerializer(serializers.ModelSerializer):
    class Meta:
        model = Permiso
        fields = ["id", "codigo", "modulo", "descripcion"]
        read_only_fields = fields


class RolSerializer(serializers.ModelSerializer):
    permisos = serializers.SerializerMethodField()

    class Meta:
        model = Rol
        fields = ["id", "codigo", "nombre", "descripcion", "activo", "permisos"]
        read_only_fields = fields

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_permisos(self, obj):
        return list(
            RolPermiso.objects.filter(rol_id=obj.pk)
            .order_by("permiso__codigo")
            .values_list("permiso__codigo", flat=True)
        )


class AsignarPermisosSerializer(serializers.Serializer):
    permisos = serializers.ListField(child=serializers.CharField(), allow_empty=True)

    def validate_permisos(self, codigos):
        codigos = {c.strip() for c in codigos}
        permisos = list(Permiso.objects.filter(codigo__in=codigos))
        faltantes = codigos - {p.codigo for p in permisos}
        if faltantes:
            raise serializers.ValidationError(f"Permisos inexistentes: {', '.join(sorted(faltantes))}.")
        return permisos
