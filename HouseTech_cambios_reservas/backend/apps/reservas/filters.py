import datetime as dt

from django_filters import rest_framework as filters

from .models import BloqueoAmenidad, Reserva
from .services import inicio_dia


class ReservaFilter(filters.FilterSet):
    """Filtros del listado e histórico de reservas."""

    amenidad = filters.NumberFilter(field_name="amenidad_id")
    usuario = filters.NumberFilter(field_name="usuario_id")
    inmueble = filters.NumberFilter(field_name="inmueble_id")
    estado = filters.CharFilter(method="filtrar_estado", help_text="Códigos separados por coma: CONFIRMADA,CANCELADA")
    desde = filters.DateFilter(method="filtrar_desde", help_text="Reservas que terminan después de esta fecha")
    hasta = filters.DateFilter(method="filtrar_hasta", help_text="Reservas que empiezan hasta esta fecha (inclusive)")
    solo_mias = filters.BooleanFilter(method="filtrar_mias")

    class Meta:
        model = Reserva
        fields: list = []

    def filtrar_estado(self, qs, name, value):
        codigos = [c.strip().upper() for c in value.split(",") if c.strip()]
        return qs.filter(estado__codigo__in=codigos)

    def filtrar_desde(self, qs, name, value):
        return qs.filter(fecha_fin__gt=inicio_dia(value))

    def filtrar_hasta(self, qs, name, value):
        return qs.filter(fecha_inicio__lt=inicio_dia(value + dt.timedelta(days=1)))

    def filtrar_mias(self, qs, name, value):
        return qs.filter(usuario=self.request.user) if value else qs


class BloqueoFilter(filters.FilterSet):
    amenidad = filters.NumberFilter(field_name="amenidad_id")
    desde = filters.DateFilter(method="filtrar_desde")
    hasta = filters.DateFilter(method="filtrar_hasta")

    class Meta:
        model = BloqueoAmenidad
        fields = ["cancelado"]

    def filtrar_desde(self, qs, name, value):
        return qs.filter(fecha_fin__gt=inicio_dia(value))

    def filtrar_hasta(self, qs, name, value):
        return qs.filter(fecha_inicio__lt=inicio_dia(value + dt.timedelta(days=1)))
