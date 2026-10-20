import datetime as dt

from django.utils import timezone
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.generics import ListAPIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.permissions import requiere_algun_permiso, requiere_permiso
from apps.inmuebles.models import Inmueble

from . import reportes, services
from .automatizacion import procesar_reservas
from .filters import BloqueoFilter, ReservaFilter
from .models import Amenidad, BloqueoAmenidad, Reserva, ReservaHistorial
from .serializers import (
    AgendaQuerySerializer,
    AmenidadSerializer,
    BloqueoSerializer,
    DisponibilidadQuerySerializer,
    MotivoSerializer,
    ReporteFiltrosSerializer,
    ReservaCrearSerializer,
    ReservaHistorialSerializer,
    ReservaSerializer,
    VerificarQuerySerializer,
)

PuedeGestionarAmenidades = requiere_algun_permiso("amenidades.gestionar", "configuracion.gestionar")
PuedeConsultarAmenidades = requiere_algun_permiso("reservas.solicitar", "amenidades.gestionar", "configuracion.gestionar")
PuedeVerReservas = requiere_algun_permiso("reservas.solicitar", "amenidades.gestionar")
PuedeAdministrarReservas = requiere_permiso("amenidades.gestionar")
PuedeGestionarBloqueos = requiere_permiso("bloqueos.gestionar")
PuedeVerReportes = requiere_permiso("reportes.ver")

PARAMETROS_AGENDA = [
    OpenApiParameter("desde", str, description="YYYY-MM-DD"), OpenApiParameter("hasta", str, description="YYYY-MM-DD"),
    OpenApiParameter("amenidad", str, description="Ids separados por coma"),
    OpenApiParameter("estado", str, description="Códigos separados por coma"),
]


# --- zonas comunes: registro y configuración (aforo, horarios, políticas) ----------------------------------
class AmenidadViewSet(viewsets.ModelViewSet):
    """Registro de zonas comunes con aforo (`capacidad`), horarios y políticas de reserva/cancelación (`reglas`).

    No hay DELETE: una amenidad con historial se desactiva (`/desactivar/`).
    """

    queryset = Amenidad.objects.select_related("reglas").prefetch_related("horarios").order_by("nombre")
    serializer_class = AmenidadSerializer
    http_method_names = ["get", "post", "put", "patch", "head", "options"]
    pagination_class = None
    filterset_fields = ["activa", "copropiedad"]
    search_fields = ["nombre", "descripcion"]

    def get_permissions(self):
        lectura = self.action in {"list", "retrieve", "disponibilidad", "verificar", "calendario"}
        return [IsAuthenticated(), (PuedeConsultarAmenidades if lectura else PuedeGestionarAmenidades)()]

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, "swagger_fake_view", False):
            return qs
        # Quien solo reserva no ve las amenidades desactivadas
        if not self.request.user.tiene_permiso("amenidades.gestionar") and not self.request.user.tiene_permiso("configuracion.gestionar"):
            qs = qs.filter(activa=True)
        return qs

    def get_serializer_context(self):
        contexto = super().get_serializer_context()
        contexto["incluir_estado"] = self.action == "retrieve"
        return contexto

    @extend_schema(request=None, responses=AmenidadSerializer)
    @action(detail=True, methods=["post"])
    def activar(self, request, pk=None):
        return self._cambiar_activa(True)

    @extend_schema(request=None, responses=AmenidadSerializer)
    @action(detail=True, methods=["post"])
    def desactivar(self, request, pk=None):
        return self._cambiar_activa(False)

    def _cambiar_activa(self, activa):
        amenidad = self.get_object()
        amenidad.activa = activa
        amenidad.save(update_fields=["activa", "updated_at"])
        return Response(self.get_serializer(amenidad).data)

    @extend_schema(parameters=[DisponibilidadQuerySerializer], responses={200: dict})
    @action(detail=True, methods=["get"])
    def disponibilidad(self, request, pk=None):
        """Franjas abiertas, ocupadas (reservas y bloqueos) y libres de la amenidad en un día."""
        params = DisponibilidadQuerySerializer(data=request.query_params)
        params.is_valid(raise_exception=True)
        fecha = params.validated_data.get("fecha") or timezone.localdate()
        return Response(services.disponibilidad_dia(self.get_object(), fecha))

    @extend_schema(parameters=[VerificarQuerySerializer], responses={200: dict})
    @action(detail=True, methods=["get"])
    def verificar(self, request, pk=None):
        """¿Se puede reservar este horario? Responde `disponible` y, si no, la lista de `motivos`."""
        params = VerificarQuerySerializer(data=request.query_params)
        params.is_valid(raise_exception=True)
        datos = params.validated_data
        inmueble = None
        if datos.get("inmueble"):
            inmueble = Inmueble.objects.filter(pk=datos["inmueble"]).first()
        else:
            inmueble = services.resolver_inmueble(request.user, None, gestor=services.es_gestor(request.user))
        motivos = services.verificar_disponibilidad(
            self.get_object(), datos["inicio"], datos["fin"],
            num_personas=datos.get("num_personas"), inmueble=inmueble,
        )
        return Response({"disponible": not motivos, "motivos": motivos})

    @extend_schema(parameters=PARAMETROS_AGENDA, responses={200: dict})
    @action(detail=True, methods=["get"])
    def calendario(self, request, pk=None):
        """Calendario de una sola amenidad (mismas reglas de privacidad que /agenda/)."""
        amenidad = self.get_object()
        params = AgendaQuerySerializer(data=request.query_params)
        params.is_valid(raise_exception=True)
        d = params.validated_data
        eventos = services.eventos_agenda(
            services.inicio_dia(d["desde"]), services.inicio_dia(d["hasta"] + dt.timedelta(days=1)),
            request.user, amenidad_ids=[amenidad.pk], estados=d["estados"],
        )
        return Response({"amenidad_id": amenidad.pk, "desde": d["desde"], "hasta": d["hasta"], "eventos": eventos})


# --- reservas e historial (RF11) ---------------------------------------------------------------------------------
class ReservaViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    """Solicitud, consulta e historial de reservas. El residente solo ve las suyas."""

    queryset = Reserva.objects.select_related("amenidad", "usuario", "inmueble", "estado").order_by("-fecha_inicio", "-id")
    serializer_class = ReservaSerializer
    filterset_class = ReservaFilter
    search_fields = ["amenidad__nombre", "usuario__nombres", "usuario__apellidos", "inmueble__codigo_interno"]
    ordering_fields = ["fecha_inicio", "fecha_fin", "created_at"]

    def get_permissions(self):
        if self.action in {"confirmar", "rechazar", "finalizar", "procesar"}:
            clase = PuedeAdministrarReservas
        elif self.action == "create":
            clase = requiere_permiso("reservas.solicitar")
        else:
            clase = PuedeVerReservas
        return [IsAuthenticated(), clase()]

    def get_queryset(self):
        qs = super().get_queryset()
        if getattr(self, "swagger_fake_view", False) or services.es_gestor(self.request.user):
            return qs
        return qs.filter(usuario=self.request.user)

    @extend_schema(request=ReservaCrearSerializer, responses={201: ReservaSerializer})
    def create(self, request, *args, **kwargs):
        """Valida disponibilidad, horario, aforo, políticas y bloqueos. 409 si hay conflicto de agenda."""
        serializer = ReservaCrearSerializer(data=request.data, context={"request": request})
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        gestor = services.es_gestor(request.user)
        titular = d.get("usuario") or request.user
        inmueble = services.resolver_inmueble(titular, d.get("inmueble"), gestor=gestor)
        reserva = services.crear_reserva(
            amenidad=d["amenidad"], usuario=titular, inicio=d["fecha_inicio"], fin=d["fecha_fin"],
            num_personas=d["num_personas"], inmueble=inmueble, observaciones=d.get("observaciones"),
        )
        reserva = self.get_queryset().get(pk=reserva.pk)
        return Response(ReservaSerializer(reserva, context=self.get_serializer_context()).data, status=status.HTTP_201_CREATED)

    def _responder(self, reserva):
        reserva = self.get_queryset().get(pk=reserva.pk)
        return Response(ReservaSerializer(reserva, context=self.get_serializer_context()).data)

    @extend_schema(request=MotivoSerializer, responses=ReservaSerializer)
    @action(detail=True, methods=["post"])
    def cancelar(self, request, pk=None):
        """Aplica la política de cancelación (`horas_limite_cancelacion`) de la amenidad."""
        datos = MotivoSerializer(data=request.data)
        datos.is_valid(raise_exception=True)
        reserva = services.cancelar_reserva(self.get_object(), request.user, datos.validated_data.get("motivo"))
        return self._responder(reserva)

    @extend_schema(request=None, responses=ReservaSerializer)
    @action(detail=True, methods=["post"])
    def confirmar(self, request, pk=None):
        return self._responder(services.confirmar_reserva(self.get_object(), request.user))

    @extend_schema(request=MotivoSerializer, responses=ReservaSerializer)
    @action(detail=True, methods=["post"])
    def rechazar(self, request, pk=None):
        datos = MotivoSerializer(data=request.data)
        datos.is_valid(raise_exception=True)
        return self._responder(services.rechazar_reserva(self.get_object(), request.user, datos.validated_data.get("motivo")))

    @extend_schema(request=None, responses=ReservaSerializer)
    @action(detail=True, methods=["post"])
    def finalizar(self, request, pk=None):
        return self._responder(services.finalizar_reserva(self.get_object()))

    @extend_schema(request=None, responses={200: dict})
    @action(detail=False, methods=["post"])
    def procesar(self, request):
        """Ejecuta ahora el proceso automático: libera solicitudes vencidas, envía recordatorios, finaliza reservas."""
        return Response(procesar_reservas())

    @extend_schema(responses=ReservaHistorialSerializer(many=True))
    @action(detail=True, methods=["get"])
    def historial(self, request, pk=None):
        """RF11: línea de tiempo de estados de la reserva (quién, cuándo y por qué)."""
        reserva = self.get_object()  # respeta la visibilidad: el residente solo ve la suya
        eventos = ReservaHistorial.objects.filter(reserva=reserva).select_related("estado_anterior", "estado_nuevo", "usuario")
        return Response(ReservaHistorialSerializer(eventos, many=True).data)


# --- bloqueos ---------------------------------------------------------------------------------------------------------------
class BloqueoViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, mixins.CreateModelMixin, viewsets.GenericViewSet):
    """Bloqueos temporales de amenidades. Impiden nuevas reservas en el rango."""

    queryset = BloqueoAmenidad.objects.select_related("amenidad").order_by("-fecha_inicio", "-id")
    serializer_class = BloqueoSerializer
    permission_classes = [IsAuthenticated, PuedeGestionarBloqueos]
    filterset_class = BloqueoFilter

    @extend_schema(request=BloqueoSerializer, responses={201: BloqueoSerializer})
    def create(self, request, *args, **kwargs):
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        d = serializer.validated_data
        bloqueo, canceladas = services.crear_bloqueo(
            amenidad=d["amenidad"], inicio=d["fecha_inicio"], fin=d["fecha_fin"], motivo=d["motivo"],
            usuario=request.user, cancelar_reservas=d.get("cancelar_reservas", False),
        )
        datos = BloqueoSerializer(bloqueo, context=self.get_serializer_context()).data
        datos["reservas_canceladas"] = [r.pk for r in canceladas]
        return Response(datos, status=status.HTTP_201_CREATED)

    @extend_schema(request=None, responses=BloqueoSerializer)
    @action(detail=True, methods=["post"])
    def cancelar(self, request, pk=None):
        bloqueo = services.cancelar_bloqueo(self.get_object())
        return Response(self.get_serializer(bloqueo).data)


# --- RF12: agenda y calendario de disponibilidad ------------------------------------------------------------------------------
class AgendaView(APIView):
    """Agenda de todas las amenidades: reservas y bloqueos en un rango de fechas."""

    permission_classes = [IsAuthenticated, requiere_algun_permiso("reservas.solicitar", "amenidades.gestionar", "bloqueos.gestionar")]

    @extend_schema(parameters=PARAMETROS_AGENDA, responses={200: dict})
    def get(self, request):
        params = AgendaQuerySerializer(data=request.query_params)
        params.is_valid(raise_exception=True)
        d = params.validated_data
        eventos = services.eventos_agenda(
            services.inicio_dia(d["desde"]), services.inicio_dia(d["hasta"] + dt.timedelta(days=1)),
            request.user, amenidad_ids=d["amenidades"], estados=d["estados"],
        )
        return Response({"desde": d["desde"], "hasta": d["hasta"], "eventos": eventos})


# --- reportes --------------------------------------------------------------------------------------------------------------------
_PARAMETROS_REPORTE = [ReporteFiltrosSerializer]


class OcupacionReporteView(APIView):
    """Ocupación por amenidad (horas reservadas / horas de funcionamiento), serie temporal y hora pico."""

    permission_classes = [IsAuthenticated, PuedeVerReportes]

    @extend_schema(parameters=_PARAMETROS_REPORTE, responses={200: dict})
    def get(self, request):
        filtros = ReporteFiltrosSerializer(data=request.query_params)
        filtros.is_valid(raise_exception=True)
        datos = reportes.reporte_ocupacion(filtros.validated_data)
        if filtros.validated_data["formato"] == "csv":
            return reportes.ocupacion_a_csv(datos)
        return Response(datos)


class HistoricoReservasView(ListAPIView):
    """Histórico de reservas de toda la copropiedad con filtros (amenidad, usuario, inmueble, estado, fechas).
    Agrega `?formato=csv` para exportar todo el resultado."""

    queryset = Reserva.objects.select_related("amenidad", "usuario", "inmueble", "estado").order_by("-fecha_inicio", "-id")
    serializer_class = ReservaSerializer
    permission_classes = [IsAuthenticated, PuedeVerReportes]
    filterset_class = ReservaFilter
    search_fields = ["amenidad__nombre", "usuario__nombres", "usuario__apellidos", "inmueble__codigo_interno"]
    ordering_fields = ["fecha_inicio", "fecha_fin", "created_at"]

    @extend_schema(parameters=[OpenApiParameter("formato", str, enum=["json", "csv"])])
    def list(self, request, *args, **kwargs):
        if request.query_params.get("formato") == "csv":
            return reportes.historico_a_csv(self.filter_queryset(self.get_queryset())[:50000])
        return super().list(request, *args, **kwargs)
