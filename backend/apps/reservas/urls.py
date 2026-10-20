from django.urls import path
from rest_framework.routers import SimpleRouter

from .views import AgendaView, AmenidadViewSet, HistoricoReservasView, OcupacionReporteView, ReservaViewSet

app_name = "reservas"

router = SimpleRouter()
router.register("amenidades", AmenidadViewSet, basename="amenidad")
router.register("reservas", ReservaViewSet, basename="reserva")

urlpatterns = [
    path("agenda/", AgendaView.as_view(), name="agenda"),
    path("reportes/ocupacion/", OcupacionReporteView.as_view(), name="reporte-ocupacion"),
    path("reportes/reservas/", HistoricoReservasView.as_view(), name="reporte-historico"),
] + router.urls
