from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError as DjangoValidationError
from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.db import set_audit_user

from .models import Rol, TokenRevocado, Usuario, UsuarioRol


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
    username = serializers.RegexField(
        r"^[A-Za-z0-9._-]{3,60}$",
        error_messages={"invalid": "Usa de 3 a 60 caracteres: letras, números, punto, guion o guion bajo."},
    )
    email = serializers.EmailField(max_length=150)
    password = serializers.CharField(
        write_only=True, trim_whitespace=False, max_length=128, style={"input_type": "password"}
    )

    class Meta:
        model = Usuario
        fields = [
            "tipo_documento", "numero_documento", "nombres", "apellidos",
            "username", "email", "telefono", "password",
        ]

    def validate_username(self, value):
        if Usuario.objects.filter(username__iexact=value).exists():
            raise serializers.ValidationError("Este nombre de usuario ya está en uso.")
        return value

    def validate_email(self, value):
        if Usuario.objects.filter(email__iexact=value).exists():
            raise serializers.ValidationError("Este correo ya está registrado.")
        return value

    def validate(self, attrs):
        if Usuario.objects.filter(
            tipo_documento=attrs.get("tipo_documento", Usuario.TipoDocumento.CC),
            numero_documento=attrs["numero_documento"],
        ).exists():
            raise serializers.ValidationError(
                {"numero_documento": "Ya existe un usuario con este documento."}
            )
        try:
            validate_password(
                attrs["password"],
                Usuario(username=attrs["username"], email=attrs["email"]),
            )
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"password": list(exc.messages)})
        return attrs

    def create(self, validated_data):
        password = validated_data.pop("password")
        usuario = Usuario.objects.create_user(password=password, **validated_data)
        set_audit_user(usuario.pk)
        UsuarioRol.objects.create(usuario=usuario, rol=Rol.objects.get(codigo="RESIDENTE"))
        return usuario


class PerfilUpdateSerializer(serializers.ModelSerializer):
    email = serializers.EmailField(max_length=150)

    class Meta:
        model = Usuario
        fields = ["nombres", "apellidos", "telefono", "email"]

    def validate_email(self, value):
        if Usuario.objects.filter(email__iexact=value).exclude(pk=self.instance.pk).exists():
            raise serializers.ValidationError("Este correo ya está registrado.")
        return value

    def update(self, instance, validated_data):
        for field, value in validated_data.items():
            setattr(instance, field, value)
        instance.save(update_fields=list(validated_data))
        return instance


class CambiarPasswordSerializer(serializers.Serializer):
    password_actual = serializers.CharField(
        write_only=True, trim_whitespace=False, max_length=128, style={"input_type": "password"}
    )
    password_nueva = serializers.CharField(
        write_only=True, trim_whitespace=False, max_length=128, style={"input_type": "password"}
    )

    def validate(self, attrs):
        usuario = self.context["request"].user
        if not usuario.check_password(attrs["password_actual"]):
            raise serializers.ValidationError(
                {"password_actual": "La contraseña actual es incorrecta."}
            )
        if attrs["password_actual"] == attrs["password_nueva"]:
            raise serializers.ValidationError(
                {"password_nueva": "La nueva contraseña debe ser distinta de la actual."}
            )
        try:
            validate_password(attrs["password_nueva"], usuario)
        except DjangoValidationError as exc:
            raise serializers.ValidationError({"password_nueva": list(exc.messages)})
        return attrs
