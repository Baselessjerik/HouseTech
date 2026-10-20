from django.db import OperationalError, connection
from drf_spectacular.types import OpenApiTypes
from drf_spectacular.utils import extend_schema
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from rest_framework.views import APIView


class HealthView(APIView):
    authentication_classes: list = []
    permission_classes = [AllowAny]

    @extend_schema(responses={200: OpenApiTypes.OBJECT, 503: OpenApiTypes.OBJECT})
    def get(self, request):
        try:
            with connection.cursor() as cursor:
                cursor.execute("SELECT 1")
        except OperationalError:
            return Response({"status": "db_down"}, status=503)
        return Response({"status": "ok"})


# --- notificaciones del usuario autenticado --------------------------------------------------
from django.utils import timezone  # noqa: E402
from django_filters import rest_framework as django_filters  # noqa: E402
from rest_framework import mixins, viewsets  # noqa: E402
from rest_framework.decorators import action  # noqa: E402

from .models import Notificacion  # noqa: E402
from .serializers import NotificacionSerializer  # noqa: E402


class NotificacionFilter(django_filters.FilterSet):
    class Meta:
        model = Notificacion
        fields = ["leida", "tipo"]


class NotificacionViewSet(mixins.ListModelMixin, mixins.RetrieveModelMixin, viewsets.GenericViewSet):
    """Cada usuario solo ve las suyas (recordatorios, confirmaciones, avisos de reservas...)."""

    serializer_class = NotificacionSerializer
    filterset_class = NotificacionFilter
    ordering_fields = ["created_at"]

    def get_queryset(self):
        if getattr(self, "swagger_fake_view", False):
            return Notificacion.objects.none()
        return Notificacion.objects.filter(usuario=self.request.user)

    @extend_schema(request=None, responses=NotificacionSerializer)
    @action(detail=True, methods=["post"])
    def leer(self, request, pk=None):
        notificacion = self.get_object()
        if not notificacion.leida:
            notificacion.leida, notificacion.leida_en = True, timezone.now()
            notificacion.save(update_fields=["leida", "leida_en"])
        return Response(self.get_serializer(notificacion).data)

    @extend_schema(request=None, responses=OpenApiTypes.OBJECT)
    @action(detail=False, methods=["post"], url_path="leer-todas")
    def leer_todas(self, request):
        marcadas = self.get_queryset().filter(leida=False).update(leida=True, leida_en=timezone.now())
        return Response({"marcadas": marcadas})

    @extend_schema(responses=OpenApiTypes.OBJECT)
    @action(detail=False, methods=["get"])
    def resumen(self, request):
        return Response({"no_leidas": self.get_queryset().filter(leida=False).count()})
