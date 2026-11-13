from django.urls import include, path
from drf_spectacular.views import SpectacularAPIView, SpectacularSwaggerView

urlpatterns = [
    # API v1 (cada app registra sus propias rutas)
    path("api/v1/", include("apps.core.urls")),
    path("api/v1/", include("apps.usuarios.urls")),
    path("api/v1/", include("apps.comunicados.urls")),  # MODULO-2
    # Documentación OpenAPI / Swagger
    path("api/schema/", SpectacularAPIView.as_view(), name="schema"),
    path("api/docs/", SpectacularSwaggerView.as_view(url_name="schema"), name="swagger-ui"),
]
