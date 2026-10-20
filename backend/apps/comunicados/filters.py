from django.utils import timezone
from django_filters import rest_framework as filters

from .models import Bloqueo, Comunicado, Mantenimiento, Notificacion


class MantenimientoFilter(filters.FilterSet):
    estado = filters.CharFilter(field_name="estado__codigo", lookup_expr="iexact", help_text="PROGRAMADO, EN_CURSO...")
    desde = filters.IsoDateTimeFilter(method="filtrar_desde", help_text="Termina después de este instante")
    hasta = filters.IsoDateTimeFilter(method="filtrar_hasta", help_text="Empieza antes de este instante")

    class Meta:
        model = Mantenimiento
        fields = ["amenidad"]

    def filtrar_desde(self, qs, name, valor):
        return qs.filter(fecha_fin__gt=valor)

    def filtrar_hasta(self, qs, name, valor):
        return qs.filter(fecha_inicio__lt=valor)


class BloqueoFilter(filters.FilterSet):
    activo = filters.BooleanFilter(method="filtrar_activo", help_text="No cancelado y aún no finalizado")
    desde = filters.IsoDateTimeFilter(method="filtrar_desde")
    hasta = filters.IsoDateTimeFilter(method="filtrar_hasta")

    class Meta:
        model = Bloqueo
        fields = ["amenidad", "mantenimiento", "cancelado"]

    def filtrar_activo(self, qs, name, valor):
        vigente = qs.filter(cancelado=False, fecha_fin__gt=timezone.now())
        return vigente if valor else qs.exclude(pk__in=vigente.values("pk"))

    def filtrar_desde(self, qs, name, valor):
        return qs.filter(fecha_fin__gt=valor)

    def filtrar_hasta(self, qs, name, valor):
        return qs.filter(fecha_inicio__lt=valor)


class ComunicadoFilter(filters.FilterSet):
    class Meta:
        model = Comunicado
        fields = ["estado", "categoria", "audiencia"]


class AvisoFilter(filters.FilterSet):
    desde = filters.IsoDateTimeFilter(field_name="fecha_publicacion", lookup_expr="gte")
    hasta = filters.IsoDateTimeFilter(field_name="fecha_publicacion", lookup_expr="lte")

    class Meta:
        model = Comunicado
        fields = ["categoria"]


class NotificacionFilter(filters.FilterSet):
    class Meta:
        model = Notificacion
        fields = ["leida", "tipo"]
