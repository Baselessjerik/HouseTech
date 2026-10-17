from datetime import datetime, timezone as dt_timezone

from drf_spectacular.utils import extend_schema
from rest_framework import generics, status
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from .models import TokenRevocado
from .serializers import (
    CambiarPasswordSerializer,
    LoginSerializer,
    LogoutSerializer,
    PerfilUpdateSerializer,
    RefreshSerializer,
    RegistroSerializer,
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


class RegistroView(generics.CreateAPIView):
    serializer_class = RegistroSerializer
    permission_classes = [AllowAny]
    authentication_classes = []

    @extend_schema(responses={201: UsuarioPerfilSerializer})
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        usuario = serializer.save()
        return Response(UsuarioPerfilSerializer(usuario).data, status=status.HTTP_201_CREATED)


class MeView(generics.RetrieveUpdateAPIView):
    http_method_names = ["get", "patch", "head", "options"]

    def get_serializer_class(self):
        return PerfilUpdateSerializer if self.request.method == "PATCH" else UsuarioPerfilSerializer

    def get_object(self):
        return self.request.user

    @extend_schema(responses=UsuarioPerfilSerializer)
    def patch(self, request, *args, **kwargs):
        serializer = self.get_serializer(self.get_object(), data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        usuario = serializer.save()
        return Response(UsuarioPerfilSerializer(usuario).data)


class CambiarPasswordView(APIView):
    @extend_schema(request=CambiarPasswordSerializer, responses={204: None})
    def post(self, request):
        serializer = CambiarPasswordSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        request.user.set_password(serializer.validated_data["password_nueva"])
        request.user.save(update_fields=["password"])
        return Response(status=status.HTTP_204_NO_CONTENT)
