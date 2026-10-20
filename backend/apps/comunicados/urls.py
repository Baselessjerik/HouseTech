from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import (
    AvisoViewSet,
    BloqueoViewSet,
    CategoriaViewSet,
    ComunicadoViewSet,
    DisponibilidadDetalleView,
    DisponibilidadView,
    MantenimientoViewSet,
    NotificacionViewSet,
    OpcionesRolesView,
    OpcionesUsuariosView,
)

app_name = "comunicados"

router = SimpleRouter()
router.register("mantenimientos", MantenimientoViewSet, basename="mantenimiento")
router.register("bloqueos", BloqueoViewSet, basename="bloqueo")
router.register("categorias-comunicado", CategoriaViewSet, basename="categoria-comunicado")
router.register("comunicados", ComunicadoViewSet, basename="comunicado")
router.register("avisos", AvisoViewSet, basename="aviso")
router.register("notificaciones", NotificacionViewSet, basename="notificacion")

# IMPORTANTE al unir los módulos: incluir estas rutas ANTES de las de amenidades para que
# "amenidades/disponibilidad/" no la capture un detalle "amenidades/<pk>/".
urlpatterns = [
    path("amenidades/disponibilidad/", DisponibilidadView.as_view(), name="disponibilidad"),
    path("amenidades/<int:pk>/disponibilidad/", DisponibilidadDetalleView.as_view(), name="disponibilidad-detalle"),
    path("comunicados-opciones/roles/", OpcionesRolesView.as_view(), name="opciones-roles"),
    path("comunicados-opciones/usuarios/", OpcionesUsuariosView.as_view(), name="opciones-usuarios"),
] + router.urls
