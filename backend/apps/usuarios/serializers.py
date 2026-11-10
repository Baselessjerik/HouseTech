from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.db import set_audit_user
from apps.core.models import Auditoria, Copropiedad, Estado
from apps.inmuebles.models import Inmueble, InmuebleUsuario

from .models import Permiso, Rol, RolPermiso, TokenRevocado, Usuario, UsuarioRol
from .services import guardar_foto_perfil, obtener_codigo_vigente, obtener_foto_perfil


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
    foto_perfil = serializers.SerializerMethodField()

    class Meta:
        model = Usuario
        fields = [
            "id", "tipo_documento", "numero_documento", "nombres", "apellidos",
            "username", "email", "telefono", "activo", "ultimo_login", "roles", "permisos",
            "foto_perfil",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_roles(self, obj):
        return obj.codigos_roles()

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_permisos(self, obj):
        return sorted(obj.codigos_permisos())

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_foto_perfil(self, obj):
        return obtener_foto_perfil(obj.pk)


class LoginSerializer(TokenObtainPairSerializer):
    """Acepta usuario o correo en el campo `username`. Devuelve tokens + perfil."""

    def validate(self, attrs):
        try:
            data = super().validate(attrs)
        except AuthenticationFailed:
            raise AuthenticationFailed(
                "El usuario, correo o contraseña no son correctos."
            )
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
    """Lo único que el usuario puede editar de sí mismo (incluye foto_perfil)."""

    email = serializers.EmailField(max_length=150)
    foto_perfil = serializers.CharField(required=False, allow_null=True, allow_blank=True)

    class Meta:
        model = Usuario
        fields = ["nombres", "apellidos", "telefono", "email", "foto_perfil"]

    def validate_email(self, valor):
        return _verificar_unico(
            "email", valor, "Este correo ya está registrado.", excluir_pk=self.instance.pk
        )

    def update(self, instance, validated_data):
        tiene_foto = "foto_perfil" in validated_data
        foto = validated_data.pop("foto_perfil", None)
        for campo, valor in validated_data.items():
            setattr(instance, campo, valor)
        if validated_data:
            instance.save(update_fields=list(validated_data))  # no toca password_hash ni otras columnas
        if tiene_foto:
            guardar_foto_perfil(instance.pk, foto)
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


class ValidarCodigoRecuperacionSerializer(serializers.Serializer):
    identificador = serializers.CharField(max_length=150)
    codigo = serializers.RegexField(r"^\d{6}$", error_messages={"invalid": "El código tiene 6 dígitos."})

    def validate(self, attrs):
        try:
            usuario = Usuario.objects.get_by_natural_key(attrs["identificador"])
        except Usuario.DoesNotExist:
            usuario = None
        registro = obtener_codigo_vigente(usuario, attrs["codigo"]) if usuario and usuario.activo else None
        if registro is None:
            raise serializers.ValidationError({"codigo": "Código inválido o vencido."})
        return attrs


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
    foto_perfil = serializers.SerializerMethodField()

    class Meta:
        model = Usuario
        fields = [
            "id", "tipo_documento", "numero_documento", "nombres", "apellidos",
            "username", "email", "telefono", "activo", "ultimo_login", "roles",
            "foto_perfil",
        ]
        read_only_fields = fields

    @extend_schema_field(serializers.ListField(child=serializers.CharField()))
    def get_roles(self, obj):
        # 1 consulta por fila (máx. 20 por página); optimizable con prefetch si hiciera falta
        return obj.codigos_roles()

    @extend_schema_field(serializers.CharField(allow_null=True))
    def get_foto_perfil(self, obj):
        return obtener_foto_perfil(obj.pk)


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


# --- Inmuebles, Copropiedad (Parametrización), Estados y Auditoría ---------------
class InmuebleVinculoSerializer(serializers.ModelSerializer):
    usuario_id = serializers.IntegerField(source="usuario.id", read_only=True)
    usuario_nombre = serializers.CharField(source="usuario.nombre_completo", read_only=True)
    usuario_username = serializers.CharField(source="usuario.username", read_only=True)
    usuario_documento = serializers.CharField(source="usuario.numero_documento", read_only=True)

    class Meta:
        model = InmuebleUsuario
        fields = [
            "id", "usuario_id", "usuario_nombre", "usuario_username",
            "usuario_documento", "tipo_relacion", "fecha_inicio", "fecha_fin",
        ]
        read_only_fields = fields


class InmuebleSerializer(serializers.ModelSerializer):
    copropiedad_nombre = serializers.CharField(source="copropiedad.nombre", read_only=True)
    vinculos = serializers.SerializerMethodField()

    class Meta:
        model = Inmueble
        fields = [
            "id", "copropiedad", "copropiedad_nombre", "tipo", "torre_bloque",
            "piso", "numero", "codigo_interno", "area_m2", "activo", "vinculos",
        ]
        read_only_fields = ["id", "copropiedad_nombre", "vinculos"]
        extra_kwargs = {
            "copropiedad": {"required": False},
            "codigo_interno": {"required": False, "allow_blank": True},
        }

    @extend_schema_field(InmuebleVinculoSerializer(many=True))
    def get_vinculos(self, obj):
        vigentes = obj.vinculos.filter(fecha_fin__isnull=True).select_related("usuario").order_by("id")
        return InmuebleVinculoSerializer(vigentes, many=True).data

    def _generar_codigo_unico(self, tipo, torre, numero):
        prefijo = (tipo or "INM")[:3].upper()
        bloque = f"-{torre.strip().upper()}" if torre and str(torre).strip() else ""
        base = f"{prefijo}{bloque}-{str(numero).strip().upper()}"
        candidato = base
        sufijo = 2
        qs_base = Inmueble.objects.all()
        if self.instance is not None:
            qs_base = qs_base.exclude(pk=self.instance.pk)
        while qs_base.filter(codigo_interno__iexact=candidato).exists():
            candidato = f"{base}-{sufijo}"
            sufijo += 1
        return candidato

    def validate_codigo_interno(self, valor):
        if not valor or not valor.strip():
            return ""
        qs = Inmueble.objects.filter(codigo_interno__iexact=valor.strip())
        if self.instance is not None:
            qs = qs.exclude(pk=self.instance.pk)
        if qs.exists():
            raise serializers.ValidationError("Ya existe un inmueble con este código interno.")
        return valor.strip()

    def create(self, validated_data):
        if "copropiedad" not in validated_data or validated_data["copropiedad"] is None:
            copropiedad = Copropiedad.objects.order_by("id").first()
            if copropiedad is None:
                copropiedad = Copropiedad.objects.create(
                    nombre="Conjunto Residencial HouseTech",
                    nit="900000001-1",
                    ciudad="San José de Cúcuta",
                )
            validated_data["copropiedad"] = copropiedad
        if not validated_data.get("codigo_interno"):
            validated_data["codigo_interno"] = self._generar_codigo_unico(
                validated_data.get("tipo"),
                validated_data.get("torre_bloque"),
                validated_data.get("numero", ""),
            )
        return super().create(validated_data)

    def update(self, instance, validated_data):
        if "codigo_interno" in validated_data and not validated_data["codigo_interno"]:
            validated_data.pop("codigo_interno")
        return super().update(instance, validated_data)


class VincularUsuarioInmuebleSerializer(serializers.Serializer):
    usuario_id = serializers.IntegerField()
    tipo_relacion = serializers.ChoiceField(
        choices=InmuebleUsuario.Relacion.choices,
        default=InmuebleUsuario.Relacion.RESIDENTE,
    )

    def validate_usuario_id(self, valor):
        try:
            return Usuario.objects.get(pk=valor, activo=True)
        except Usuario.DoesNotExist:
            raise serializers.ValidationError("El usuario indicado no existe o está inactivo.")


class CopropiedadSerializer(serializers.ModelSerializer):
    total_inmuebles = serializers.SerializerMethodField()

    class Meta:
        model = Copropiedad
        fields = [
            "id", "nombre", "nit", "direccion", "ciudad",
            "telefono", "email", "descripcion", "total_inmuebles",
        ]
        read_only_fields = ["id", "total_inmuebles"]

    @extend_schema_field(serializers.IntegerField())
    def get_total_inmuebles(self, obj):
        return obj.inmuebles.count()


class EstadoConfigSerializer(serializers.ModelSerializer):
    class Meta:
        model = Estado
        fields = ["id", "proceso", "codigo", "nombre", "orden", "es_inicial", "es_final", "activo"]
        read_only_fields = fields


class AuditoriaSerializer(serializers.ModelSerializer):
    usuario_username = serializers.CharField(source="usuario.username", read_only=True, default=None)
    usuario_nombre = serializers.CharField(source="usuario.nombre_completo", read_only=True, default=None)

    class Meta:
        model = Auditoria
        fields = [
            "id", "fecha", "usuario_id", "usuario_username", "usuario_nombre",
            "tabla", "registro_id", "operacion", "datos_anteriores", "datos_nuevos",
        ]
        read_only_fields = fields
