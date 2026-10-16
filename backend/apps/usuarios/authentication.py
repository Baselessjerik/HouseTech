from rest_framework.exceptions import AuthenticationFailed
from rest_framework_simplejwt.authentication import JWTAuthentication

from apps.core.db import set_audit_user

from .models import TokenRevocado


class HouseTechJWTAuthentication(JWTAuthentication):
    """JWT + lista de tokens revocados + usuario de auditoría para los triggers."""

    def authenticate(self, request):
        resultado = super().authenticate(request)
        if resultado is None:
            return None
        usuario, token = resultado
        if TokenRevocado.objects.filter(jti=token["jti"]).exists():
            raise AuthenticationFailed("El token fue revocado.", code="token_revoked")
        set_audit_user(usuario.pk)  # corre dentro de la transacción de la petición
        return usuario, token
