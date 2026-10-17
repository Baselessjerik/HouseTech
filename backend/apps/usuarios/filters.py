from django_filters import rest_framework as filters

from .models import Usuario


class UsuarioFilter(filters.FilterSet):
    rol = filters.CharFilter(method="filtrar_rol", help_text="Código de rol, ej. ADMIN")

    class Meta:
        model = Usuario
        fields = ["activo", "tipo_documento"]

    def filtrar_rol(self, queryset, name, value):
        return queryset.filter(usuario_roles__rol__codigo__iexact=value).distinct()
