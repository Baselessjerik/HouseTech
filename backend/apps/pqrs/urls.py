# Ubicación: backend/apps/pqrs/urls.py

from django.urls import path
from .views import (
    MisInmueblesPQRListView,
    PQRAdjuntoDownloadView,
    PQRAdjuntoListCreateView,
    PQRAdjuntoRetrieveUpdateDestroyView,
    PQRListCreateView,
    PQRRetrieveUpdateDestroyView,
    TipoPQRListView,
)

app_name = "pqrs"

urlpatterns = [
    # Catálogos y opciones del formulario de radicación.
    path("pqrs/tipos/", TipoPQRListView.as_view(), name="tipos-pqr"),
    path(
        "pqrs/mis-inmuebles/",
        MisInmueblesPQRListView.as_view(),
        name="mis-inmuebles-pqr",
    ),
    path("pqrs/", PQRListCreateView.as_view(), name="pqrs-list-create"),
    # Lectura, actualización y borrado de una solicitud individual.
    path(
        "pqrs/<int:pk>/",
        PQRRetrieveUpdateDestroyView.as_view(),
        name="pqrs-detail-update-delete",
    ),
    # Gestión de metadatos y archivos asociados a cada solicitud.
    path(
        "pqrs/<int:pqr_id>/adjuntos/",
        PQRAdjuntoListCreateView.as_view(),
        name="pqr-adjuntos",
    ),
    path(
        "pqrs/<int:pqr_id>/adjuntos/<int:adjunto_id>/",
        PQRAdjuntoRetrieveUpdateDestroyView.as_view(),
        name="pqr-adjunto-detail",
    ),
    path(
        "pqrs/<int:pqr_id>/adjuntos/<int:adjunto_id>/descargar/",
        PQRAdjuntoDownloadView.as_view(),
        name="pqr-adjunto-descargar",
    ),
]