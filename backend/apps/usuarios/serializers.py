from django.utils import timezone
from drf_spectacular.utils import extend_schema_field
from rest_framework import serializers
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer, TokenRefreshSerializer
from rest_framework_simplejwt.tokens import RefreshToken

from apps.core.db import set_audit_user

from .models import TokenRevocado, Usuario


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
