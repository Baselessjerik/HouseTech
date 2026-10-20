from django.db.models import Q
from django.utils import timezone
from django.utils.dateparse import parse_datetime
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import OpenApiParameter, extend_schema
from rest_framework import mixins, status, viewsets
from rest_framework.decorators import action
from rest_framework.exceptions import NotFound, ValidationError
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.permissions import requiere_permiso
from apps.usuarios.models import Rol, Usuario

from . import services
from .filters import AvisoFilter, BloqueoFilter, ComunicadoFilter, MantenimientoFilter, NotificacionFilter
from .models import Bloqueo, CategoriaComunicado, Comunicado, ComunicadoHistorial, Mantenimiento, Notificacion
from .serializers import (
    AvisoSerializer,
    BloqueoEscrituraSerializer,
    BloqueoSerializer,
    CancelarBloqueoSerializer,
    CategoriaSerializer,
    ComunicadoEscrituraSerializer,
    ComunicadoHistorialSerializer,
    ComunicadoSerializer,
    DisponibilidadSerializer,
    MantenimientoEscrituraSerializer,
    MantenimientoSerializer,
    NotificacionSerializer,
    OpcionRolSerializer,
    OpcionUsuarioSerializer,
    ProgramarSerializer,
)

PuedeGestionarBloqueos = requiere_permiso("bloqueos.gestionar")
PuedeGestionarComunicados = requiere_permiso("comunicados.gestionar")
PuedeVerComunicados = requiere_permiso("comunicados.ver")

PARAM_CONFIRMAR = OpenApiParameter(
    "confirmar", OpenApiTypes.BOOL, description="Continuar aunque haya reservas en conflicto (se avisa a sus dueños)."
)


def _confirmar(request):
    valor = request.query_params.get("confirmar", request.data.get("confirmar", False) if hasattr(request.data, "get") else False)
    return str(valor).strip().lower() in ("1", "true", "si", "sí", "yes")


# ------------------------------------------------------------- mantenimientos (RF1, RF8)
class MantenimientoViewSet(
    mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet
):
    """Mantenimientos programados de zonas comunes. No hay DELETE: se cancelan (estado CANCELADO)."""

    queryset = Mantenimiento.objects.select_related("amenidad", "estado", "creado_por").order_by(
        "-fecha_inicio", "-id"
    )
    serializer_class = MantenimientoSerializer
    permission_classes = [IsAuthenticated, PuedeGestionarBloqueos]
    filterset_class = MantenimientoFilter
    search_fields = ["titulo", "descripcion", "responsable", "amenidad__nombre"]
    ordering_fields = ["fecha_inicio", "fecha_fin", "created_at", "titulo"]
    http_method_names = ["get", "post", "patch", "head", "options"]

    @extend_schema(
        request=MantenimientoEscrituraSerializer, responses={201: MantenimientoSerializer},
        parameters=[PARAM_CONFIRMAR],
    )
    def create(self, request, *args, **kwargs):
        serializer = MantenimientoEscrituraSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        datos = dict(serializer.validated_data)
        crear_bloqueo = datos.pop("crear_bloqueo", False)
        m = services.crear_mantenimiento(
            datos, request.user, crear_bloqueo_asociado=crear_bloqueo, confirmar=_confirmar(request)
        )
        return Response(MantenimientoSerializer(m).data, status=status.HTTP_201_CREATED)

    @extend_schema(
        request=MantenimientoEscrituraSerializer, responses={200: MantenimientoSerializer},
        parameters=[PARAM_CONFIRMAR],
    )
    def partial_update(self, request, *args, **kwargs):
        m = self.get_object()
        serializer = MantenimientoEscrituraSerializer(m, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        datos = dict(serializer.validated_data)
        datos.pop("crear_bloqueo", None)
        m = services.modificar_mantenimiento(m, datos, request.user, confirmar=_confirmar(request))
        return Response(MantenimientoSerializer(m).data)

    def _transicion(self, request, codigo):
        m = services.cambiar_estado_mantenimiento(self.get_object(), codigo, request.user)
        return Response(MantenimientoSerializer(m).data)

    @extend_schema(request=None, responses={200: MantenimientoSerializer})
    @action(detail=True, methods=["post"])
    def iniciar(self, request, pk=None):
        return self._transicion(request, "EN_CURSO")

    @extend_schema(request=None, responses={200: MantenimientoSerializer})
    @action(detail=True, methods=["post"])
    def finalizar(self, request, pk=None):
        return self._transicion(request, "FINALIZADO")

    @extend_schema(request=None, responses={200: MantenimientoSerializer})
    @action(detail=True, methods=["post"])
    def cancelar(self, request, pk=None):
        return self._transicion(request, "CANCELADO")


# ---------------------------------------------------------------- bloqueos (RF2-RF5, RF7)
class BloqueoViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Bloqueos temporales de amenidades. No hay DELETE: se cancelan (cancelado = true)."""

    queryset = Bloqueo.objects.select_related("amenidad", "mantenimiento", "creado_por").order_by(
        "-fecha_inicio", "-id"
    )
    serializer_class = BloqueoSerializer
    permission_classes = [IsAuthenticated, PuedeGestionarBloqueos]
    filterset_class = BloqueoFilter
    search_fields = ["motivo", "amenidad__nombre"]
    ordering_fields = ["fecha_inicio", "fecha_fin", "created_at"]
    http_method_names = ["get", "post", "patch", "head", "options"]

    @extend_schema(
        request=BloqueoEscrituraSerializer, responses={201: BloqueoSerializer}, parameters=[PARAM_CONFIRMAR]
    )
    def create(self, request, *args, **kwargs):
        serializer = BloqueoEscrituraSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        b = services.crear_bloqueo(serializer.validated_data, request.user, confirmar=_confirmar(request))
        return Response(BloqueoSerializer(b).data, status=status.HTTP_201_CREATED)

    @extend_schema(
        request=BloqueoEscrituraSerializer, responses={200: BloqueoSerializer}, parameters=[PARAM_CONFIRMAR]
    )
    def partial_update(self, request, *args, **kwargs):
        b = self.get_object()
        serializer = BloqueoEscrituraSerializer(b, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        datos = {k: v for k, v in serializer.validated_data.items() if k in ("fecha_inicio", "fecha_fin", "motivo")}
        b = services.modificar_bloqueo(b, datos, request.user, confirmar=_confirmar(request))
        return Response(BloqueoSerializer(b).data)

    @extend_schema(request=CancelarBloqueoSerializer, responses={200: BloqueoSerializer})
    @action(detail=True, methods=["post"])
    def cancelar(self, request, pk=None):
        CancelarBloqueoSerializer(data=request.data).is_valid(raise_exception=True)
        b = services.cancelar_bloqueo(self.get_object(), request.user)
        return Response(BloqueoSerializer(b).data)


# ------------------------------------------------------------------ disponibilidad (RF6)
def _momento(request):
    texto = request.query_params.get("momento")
    if not texto:
        return timezone.now()
    momento = parse_datetime(texto)
    if momento is None:
        raise ValidationError({"momento": "Usa el formato ISO-8601, por ejemplo 2026-10-20T15:00:00-05:00."})
    return timezone.make_aware(momento) if timezone.is_naive(momento) else momento


class DisponibilidadView(APIView):
    """Estado de todas las amenidades activas (DISPONIBLE, RESERVADA, BLOQUEADA, EN_MANTENIMIENTO)."""

    @extend_schema(
        parameters=[OpenApiParameter("momento", OpenApiTypes.DATETIME, description="Por defecto, ahora.")],
        responses=DisponibilidadSerializer(many=True),
    )
    def get(self, request):
        datos = services.disponibilidad(_momento(request))
        return Response(DisponibilidadSerializer(datos, many=True).data)


class DisponibilidadDetalleView(APIView):
    @extend_schema(
        parameters=[OpenApiParameter("momento", OpenApiTypes.DATETIME, description="Por defecto, ahora.")],
        responses=DisponibilidadSerializer,
    )
    def get(self, request, pk):
        datos = services.disponibilidad(_momento(request), amenidad_id=pk)
        if not datos:
            raise NotFound("La amenidad no existe o no está activa.")
        return Response(DisponibilidadSerializer(datos[0]).data)


# ------------------------------------------------------------------ categorías (RF12)
class CategoriaViewSet(viewsets.ModelViewSet):
    """Lectura: `comunicados.ver` (solo activas). Escritura: `comunicados.gestionar`."""

    serializer_class = CategoriaSerializer
    pagination_class = None
    search_fields = ["nombre", "descripcion"]
    ordering_fields = ["nombre"]
    http_method_names = ["get", "post", "patch", "delete", "head", "options"]

    def get_permissions(self):
        clase = PuedeVerComunicados if self.action in ("list", "retrieve") else PuedeGestionarComunicados
        return [IsAuthenticated(), clase()]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return CategoriaComunicado.objects.none()
        qs = CategoriaComunicado.objects.order_by("nombre")
        if not self.request.user.tiene_permiso("comunicados.gestionar"):
            qs = qs.filter(activa=True)
        return qs


# ------------------------------------------------------------- comunicados (RF9-RF15)
class ComunicadoViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Gestión de comunicados en cualquier estado. No hay DELETE: se archivan."""

    queryset = Comunicado.objects.select_related("categoria", "autor", "rol_destino").order_by("-created_at", "-id")
    serializer_class = ComunicadoSerializer
    permission_classes = [IsAuthenticated, PuedeGestionarComunicados]
    filterset_class = ComunicadoFilter
    search_fields = ["titulo", "contenido"]
    ordering_fields = ["created_at", "fecha_publicacion", "fecha_programada", "titulo"]
    http_method_names = ["get", "post", "patch", "head", "options"]

    @extend_schema(request=ComunicadoEscrituraSerializer, responses={201: ComunicadoSerializer})
    def create(self, request, *args, **kwargs):
        serializer = ComunicadoEscrituraSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        c = services.crear_comunicado(serializer.validated_data, request.user)
        return Response(ComunicadoSerializer(c).data, status=status.HTTP_201_CREATED)

    @extend_schema(request=ComunicadoEscrituraSerializer, responses={200: ComunicadoSerializer})
    def partial_update(self, request, *args, **kwargs):
        c = self.get_object()
        serializer = ComunicadoEscrituraSerializer(c, data=request.data, partial=True)
        serializer.is_valid(raise_exception=True)
        c = services.modificar_comunicado(c, serializer.validated_data, request.user)
        return Response(ComunicadoSerializer(c).data)

    @extend_schema(request=None, responses={200: ComunicadoSerializer})
    @action(detail=True, methods=["post"])
    def publicar(self, request, pk=None):
        c = services.publicar_comunicado(self.get_object(), request.user)
        return Response(ComunicadoSerializer(c).data)

    @extend_schema(request=ProgramarSerializer, responses={200: ComunicadoSerializer})
    @action(detail=True, methods=["post"])
    def programar(self, request, pk=None):
        serializer = ProgramarSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        c = services.programar_comunicado(self.get_object(), serializer.validated_data["fecha_programada"])
        return Response(ComunicadoSerializer(c).data)

    @extend_schema(request=None, responses={200: ComunicadoSerializer})
    @action(detail=True, methods=["post"])
    def archivar(self, request, pk=None):
        c = services.archivar_comunicado(self.get_object(), request.user)
        return Response(ComunicadoSerializer(c).data)

    @extend_schema(responses=ComunicadoHistorialSerializer(many=True))
    @action(detail=True, methods=["get"])
    def historial(self, request, pk=None):
        c = self.get_object()
        qs = ComunicadoHistorial.objects.filter(comunicado=c).select_related("usuario").order_by("-fecha", "-id")
        return Response(ComunicadoHistorialSerializer(qs, many=True).data)


# ----------------------------------------------------------------------- avisos (RF14)
class AvisoViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Avisos publicados y vigentes visibles para el usuario autenticado."""

    serializer_class = AvisoSerializer
    permission_classes = [IsAuthenticated, PuedeVerComunicados]
    filterset_class = AvisoFilter
    search_fields = ["titulo", "contenido"]
    ordering_fields = ["fecha_publicacion", "titulo"]
    ordering = ["-fecha_publicacion", "-id"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Comunicado.objects.none()
        services.publicar_programados_vencidos()  # RF13: publicación perezosa
        return services.comunicados_visibles(self.request.user).select_related("categoria", "autor")


# ------------------------------------------------------------------- notificaciones (RF8, RF16)
class NotificacionViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Notificaciones del usuario autenticado."""

    serializer_class = NotificacionSerializer
    filterset_class = NotificacionFilter
    ordering_fields = ["created_at"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Notificacion.objects.none()
        return Notificacion.objects.filter(usuario=self.request.user).order_by("-created_at", "-id")

    @extend_schema(request=None, responses={200: NotificacionSerializer})
    @action(detail=True, methods=["post"])
    def leer(self, request, pk=None):
        n = self.get_object()
        if not n.leida:
            n.leida = True
            n.leida_en = timezone.now()
            n.save(update_fields=["leida", "leida_en"])
        return Response(NotificacionSerializer(n).data)

    @extend_schema(request=None, responses={200: OpenApiTypes.OBJECT})
    @action(detail=False, methods=["post"], url_path="leer-todas")
    def leer_todas(self, request):
        n = Notificacion.objects.filter(usuario=request.user, leida=False).update(
            leida=True, leida_en=timezone.now()
        )
        return Response({"actualizadas": n})

    @extend_schema(responses={200: OpenApiTypes.OBJECT})
    @action(detail=False, methods=["get"], url_path="no-leidas/conteo")
    def conteo(self, request):
        return Response({"no_leidas": Notificacion.objects.filter(usuario=request.user, leida=False).count()})


# ---------------------------------------------------------------- opciones para formularios
class OpcionesRolesView(APIView):
    permission_classes = [IsAuthenticated, PuedeGestionarComunicados]

    @extend_schema(responses=OpcionRolSerializer(many=True))
    def get(self, request):
        roles = Rol.objects.filter(activo=True).order_by("nombre")
        return Response(OpcionRolSerializer(roles, many=True).data)


class OpcionesUsuariosView(APIView):
    """Búsqueda de usuarios activos para elegir destinatarios (máx. 25)."""

    permission_classes = [IsAuthenticated, PuedeGestionarComunicados]

    @extend_schema(
        parameters=[OpenApiParameter("search", OpenApiTypes.STR)], responses=OpcionUsuarioSerializer(many=True)
    )
    def get(self, request):
        qs = Usuario.objects.filter(activo=True).order_by("apellidos", "nombres")
        texto = request.query_params.get("search", "").strip()
        if texto:
            qs = qs.filter(
                Q(nombres__icontains=texto) | Q(apellidos__icontains=texto)
                | Q(username__icontains=texto) | Q(email__icontains=texto)
            )
        ids = request.query_params.get("ids")
        if ids:
            lista = [int(i) for i in ids.split(",") if i.strip().isdigit()]
            qs = Usuario.objects.filter(activo=True, pk__in=lista).order_by("apellidos", "nombres")
        return Response(OpcionUsuarioSerializer(qs[:25], many=True).data)
