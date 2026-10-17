from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import (
    CambiarPasswordView,
    LoginView,
    LogoutView,
    MeView,
    PermisoViewSet,
    RefreshView,
    RegistroView,
    RestablecerPasswordView,
    RolViewSet,
    SolicitarRecuperacionView,
    ValidarCodigoRecuperacionView,
    UsuarioViewSet,
)

app_name = "usuarios"

router = SimpleRouter()
router.register("usuarios", UsuarioViewSet, basename="usuario")
router.register("roles", RolViewSet, basename="rol")
router.register("permisos", PermisoViewSet, basename="permiso")

urlpatterns = [
    path("auth/login/", LoginView.as_view(), name="login"),
    path("auth/refresh/", RefreshView.as_view(), name="refresh"),
    path("auth/logout/", LogoutView.as_view(), name="logout"),
    path("auth/registro/", RegistroView.as_view(), name="registro"),
    path("auth/me/", MeView.as_view(), name="me"),
    path("auth/cambiar-password/", CambiarPasswordView.as_view(), name="cambiar-password"),
    path("auth/recuperar/", SolicitarRecuperacionView.as_view(), name="recuperar"),
    path("auth/validar-codigo/", ValidarCodigoRecuperacionView.as_view(), name="validar-codigo"),
    path("auth/restablecer/", RestablecerPasswordView.as_view(), name="restablecer"),
] + router.urls
