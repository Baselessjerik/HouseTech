from datetime import datetime, timezone as dt_timezone

from django.utils import timezone
from drf_spectacular.utils import extend_schema
from rest_framework import generics, mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import ValidationError
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.exceptions import TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView

from apps.core.db import set_audit_user
from apps.core.permissions import requiere_permiso

from .filters import UsuarioFilter
from .models import Permiso, Rol, TokenRevocado, Usuario
from .serializers import (
    AsignarPermisosSerializer,
    AsignarRolesSerializer,
    CambiarPasswordSerializer,
    LoginSerializer,
    LogoutSerializer,
    PerfilUpdateSerializer,
    PermisoSerializer,
    RefreshSerializer,
    RegistroSerializer,
    RestablecerPasswordSerializer,
    RolSerializer,
    SolicitarRecuperacionSerializer,
    ValidarCodigoRecuperacionSerializer,
    UsuarioAdminCreateSerializer,
    UsuarioListaSerializer,
    UsuarioPerfilSerializer,
)
from .services import asignar_permisos, asignar_roles, emitir_codigo_recuperacion
from .throttles import RestablecerPasswordThrottle, SolicitarRecuperacionThrottle

PuedeGestionarUsuarios = requiere_permiso("usuarios.gestionar")
PuedeGestionarRoles = requiere_permiso("roles.gestionar")


class LoginView(TokenObtainPairView):
    serializer_class = LoginSerializer


class RefreshView(TokenRefreshView):
    serializer_class = RefreshSerializer


class RegistroView(generics.CreateAPIView):
    """Autorregistro público. Siempre crea un usuario con rol RESIDENTE."""

    serializer_class = RegistroSerializer
    permission_classes = [AllowAny]
    authentication_classes: list = []

    @extend_schema(responses={201: UsuarioPerfilSerializer})
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        usuario = serializer.save()
        return Response(UsuarioPerfilSerializer(usuario).data, status=status.HTTP_201_CREATED)


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


class MeView(generics.RetrieveUpdateAPIView):
    """GET: perfil con roles y permisos. PATCH: edita nombres, apellidos, teléfono y correo."""

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


# --- recuperación de contraseña (RF4) -------------------------------------------
class SolicitarRecuperacionView(APIView):
    """Envía un código de 6 dígitos al correo. Responde igual exista o no la cuenta."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes = [SolicitarRecuperacionThrottle]

    @extend_schema(request=SolicitarRecuperacionSerializer, responses={200: None})
    def post(self, request):
        serializer = SolicitarRecuperacionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        try:
            usuario = Usuario.objects.get_by_natural_key(serializer.validated_data["identificador"])
        except Usuario.DoesNotExist:
            usuario = None
        if usuario is not None and usuario.activo:
            emitir_codigo_recuperacion(usuario)
        return Response({"detail": "Si la cuenta existe, enviamos un código al correo registrado."})


class ValidarCodigoRecuperacionView(APIView):
    """Valida el código sin consumirlo para mostrar el formulario de contraseña."""

    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes = [RestablecerPasswordThrottle]

    @extend_schema(request=ValidarCodigoRecuperacionSerializer, responses={204: None})
    def post(self, request):
        serializer = ValidarCodigoRecuperacionSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        return Response(status=status.HTTP_204_NO_CONTENT)


class RestablecerPasswordView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]
    throttle_classes = [RestablecerPasswordThrottle]

    @extend_schema(request=RestablecerPasswordSerializer, responses={204: None})
    def post(self, request):
        serializer = RestablecerPasswordSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        usuario = serializer.validated_data["usuario"]
        registro = serializer.validated_data["registro"]

        set_audit_user(usuario.pk)  # quien demostró ser el dueño de la cuenta
        usuario.set_password(serializer.validated_data["password_nueva"])
        usuario.save(update_fields=["password"])
        registro.usado_en = timezone.now()
        registro.save(update_fields=["usado_en"])
        return Response(status=status.HTTP_204_NO_CONTENT)


# --- administración de usuarios (RF1, RF7, RF8, RF9) -------------------------------
class UsuarioViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Gestión de usuarios. No hay DELETE ni PUT: los usuarios se desactivan, no se borran (RF8)."""

    queryset = Usuario.objects.order_by("apellidos", "nombres", "id")
    filterset_class = UsuarioFilter
    search_fields = ["nombres", "apellidos", "username", "email", "numero_documento"]
    ordering_fields = ["apellidos", "nombres", "username", "created_at", "last_login"]

    def get_permissions(self):
        clase = PuedeGestionarRoles if self.action == "roles" else PuedeGestionarUsuarios
        return [IsAuthenticated(), clase()]

    def get_serializer_class(self):
        return {
            "list": UsuarioListaSerializer,
            "create": UsuarioAdminCreateSerializer,
            "partial_update": PerfilUpdateSerializer,
            "roles": AsignarRolesSerializer,
        }.get(self.action, UsuarioPerfilSerializer)

    @extend_schema(responses={201: UsuarioPerfilSerializer})
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        usuario = serializer.save()
        return Response(UsuarioPerfilSerializer(usuario).data, status=status.HTTP_201_CREATED)

    @extend_schema(responses=UsuarioPerfilSerializer)
    def partial_update(self, request, *args, **kwargs):
        usuario = self.get_object()
        serializer = self.get_serializer(usuario, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        serializer.save()
        return Response(UsuarioPerfilSerializer(usuario).data)

    def _cambiar_estado(self, request, activo):
        usuario = self.get_object()
        if not activo and usuario.pk == request.user.pk:
            raise ValidationError({"detail": "No puedes desactivar tu propia cuenta."})
        usuario.activo = activo
        usuario.save(update_fields=["activo"])
        return Response(UsuarioPerfilSerializer(usuario).data)

    @extend_schema(request=None, responses=UsuarioPerfilSerializer)
    @action(detail=True, methods=["post"])
    def activar(self, request, pk=None):
        return self._cambiar_estado(request, True)

    @extend_schema(request=None, responses=UsuarioPerfilSerializer)
    @action(detail=True, methods=["post"])
    def desactivar(self, request, pk=None):
        return self._cambiar_estado(request, False)

    @extend_schema(request=AsignarRolesSerializer, responses=UsuarioPerfilSerializer)
    @action(detail=True, methods=["put"])
    def roles(self, request, pk=None):
        """Reemplaza los roles del usuario por la lista enviada."""
        usuario = self.get_object()
        serializer = AsignarRolesSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        asignar_roles(usuario, serializer.validated_data["roles"], por=request.user)
        return Response(UsuarioPerfilSerializer(usuario).data)


class RolViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Rol.objects.order_by("codigo")
    serializer_class = RolSerializer
    permission_classes = [IsAuthenticated, PuedeGestionarRoles]
    pagination_class = None

    @extend_schema(request=AsignarPermisosSerializer, responses=RolSerializer)
    @action(detail=True, methods=["put"])
    def permisos(self, request, pk=None):
        """Reemplaza los permisos del rol. El rol ADMIN no se puede modificar."""
        rol = self.get_object()
        if rol.codigo == "ADMIN":
            raise ValidationError({"permisos": "El rol ADMIN siempre conserva todos los permisos."})
        serializer = AsignarPermisosSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        asignar_permisos(rol, serializer.validated_data["permisos"])
        return Response(RolSerializer(rol).data)


class PermisoViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Permiso.objects.order_by("modulo", "codigo")
    serializer_class = PermisoSerializer
    permission_classes = [IsAuthenticated, PuedeGestionarRoles]
    pagination_class = None
