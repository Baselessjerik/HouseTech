from datetime import datetime, timezone as dt_timezone

from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.exceptions import ValidationError
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .models import TokenRevocado
from .serializers import (
    LoginSerializer,
    LogoutSerializer,
    RefreshSerializer,
    UsuarioPerfilSerializer,
)


class LoginView(TokenObtainPairView):
    serializer_class = LoginSerializer


class RefreshView(TokenRefreshView):
    serializer_class = RefreshSerializer


class LogoutView(APIView):
    """Revoca el access token en uso y el refresh token recibido."""

    @extend_schema(request=LogoutSerializer, responses={204: None})
    def post(self, request):
        serializer = LogoutSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            refresh = RefreshToken(serializer.validated_data["refresh"])
        except TokenError:
            raise ValidationError({"refresh": "Token inválido o expirado."})
        if str(refresh["user_id"]) != str(request.user.pk):
            raise ValidationError({"refresh": "El token no pertenece al usuario autenticado."})

        for token in (request.auth, refresh):
            TokenRevocado.objects.get_or_create(
                jti=token["jti"],
                defaults={
                    "usuario": request.user,
                    "expira_en": datetime.fromtimestamp(token["exp"], tz=dt_timezone.utc),
                },
            )
        return Response(status=status.HTTP_204_NO_CONTENT)


class MeView(generics.RetrieveAPIView):
    """Perfil del usuario autenticado, con sus roles y permisos (para la UI de Flutter)."""

    serializer_class = UsuarioPerfilSerializer

    def get_object(self):
        return self.request.user
