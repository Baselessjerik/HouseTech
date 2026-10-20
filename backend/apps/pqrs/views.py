# Ubicación: backend/apps/pqrs/views.py

import logging

from django.core.files.storage import default_storage
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from drf_spectacular.utils import extend_schema
from rest_framework import exceptions, generics, permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.permissions import requiere_permiso
from apps.inmuebles.models import Inmueble
from .models import PQR, PQRAdjunto, TipoPQR
from .serializers import (
    InmuebleOpcionSerializer,
    PQRAdjuntoSerializer,
    PQRDetalleSerializer,
    PQRRegistroSerializer,
    TipoPQRSerializer,
)

PuedeRadicarPQR = requiere_permiso("pqr.radicar")
logger = logging.getLogger(__name__)


def pqrs_accesibles_para(usuario):
    """Limita las consultas a las PQR propias o a todas para quien puede gestionarlas."""
    queryset = PQR.objects.select_related("estado")

    if usuario.tiene_permiso("pqr.gestionar"):
        return queryset

    return queryset.filter(solicitante=usuario)


class TipoPQRListView(generics.ListAPIView):
    """Expone el catálogo activo para clasificar nuevas solicitudes."""

    queryset = TipoPQR.objects.filter(activo=True).order_by("id")
    serializer_class = TipoPQRSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    pagination_class = None


class MisInmueblesPQRListView(generics.ListAPIView):
    """Devuelve inmuebles activos con vínculo vigente para el residente autenticado."""

    serializer_class = InmuebleOpcionSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    pagination_class = None

    def get_queryset(self):
        """Restringe el selector a inmuebles vinculados actualmente al usuario."""
        usuario = self.request.user
        return Inmueble.objects.filter(
            vinculos__usuario=usuario,
            vinculos__fecha_fin__isnull=True,
            activo=True,
        ).distinct().order_by("torre_bloque", "numero")


class PQRListCreateView(generics.ListCreateAPIView):
    """Lista solicitudes accesibles y registra PQR con los datos del usuario."""

    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]

    def get_serializer_class(self):
        """Usa validación de entrada al crear y representación detallada al consultar."""
        if self.request.method == "POST":
            return PQRRegistroSerializer
        return PQRDetalleSerializer

    def get_queryset(self):
        """Aplica permisos de visibilidad y carga las relaciones usadas por la respuesta."""
        usuario = self.request.user
        if usuario.tiene_permiso("pqr.gestionar"):
            return PQR.objects.select_related("tipo", "estado", "solicitante", "inmueble").order_by("-fecha_radicacion")
        return PQR.objects.filter(solicitante=usuario).select_related("tipo", "estado", "solicitante", "inmueble").order_by("-fecha_radicacion")

    def create(self, request, *args, **kwargs):
        """Persiste la solicitud y devuelve el radicado generado por la base de datos."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        pqr = serializer.save()
        return Response(PQRDetalleSerializer(pqr).data, status=status.HTTP_201_CREATED)


class PQRRetrieveUpdateDestroyView(generics.RetrieveUpdateDestroyAPIView):
    """Permite ver detalle (GET), editar (PATCH/PUT) y eliminar (DELETE) una PQR."""

    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]

    def get_serializer_class(self):
        """Selecciona el serializador de edición o el de lectura según el método."""
        if self.request.method in ["PUT", "PATCH"]:
            return PQRRegistroSerializer
        return PQRDetalleSerializer

    def get_queryset(self):
        """Evita que un residente acceda a solicitudes de otras personas."""
        usuario = self.request.user
        if usuario.tiene_permiso("pqr.gestionar"):
            return PQR.objects.select_related("tipo", "estado", "solicitante", "inmueble")
        return PQR.objects.filter(solicitante=usuario).select_related("tipo", "estado", "solicitante", "inmueble")

    def perform_update(self, serializer):
        """Restringe la edición del residente a solicitudes aún no revisadas."""
        pqr = self.get_object()
        # Regla de negocio: un residente solo puede editar si sigue en estado RECIBIDA
        if not self.request.user.tiene_permiso("pqr.gestionar") and pqr.estado.codigo != "RECIBIDA":
            raise exceptions.PermissionDenied("Solo puedes editar una PQR mientras esté en estado 'Recibida'.")
        serializer.save()

    def perform_destroy(self, instance):
        """Restringe el borrado del residente a solicitudes aún no revisadas."""
        # Regla de negocio: solo se puede eliminar si aún está en estado RECIBIDA
        if not self.request.user.tiene_permiso("pqr.gestionar") and instance.estado.codigo != "RECIBIDA":
            raise exceptions.PermissionDenied("No es posible eliminar una PQR que ya ha sido revisada o atendida.")
        instance.delete()


class PQRAdjuntoListCreateView(generics.ListCreateAPIView):
    """Lista los adjuntos de una PQR o carga un archivo nuevo."""

    serializer_class = PQRAdjuntoSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    parser_classes = [MultiPartParser, FormParser]
    pagination_class = None

    def _obtener_pqr(self):
        """Comprueba que la PQR exista y sea accesible para el usuario actual."""
        return get_object_or_404(
            pqrs_accesibles_para(self.request.user),
            pk=self.kwargs["pqr_id"],
        )

    def get_queryset(self):
        """Devuelve únicamente adjuntos pertenecientes a la PQR autorizada."""
        pqr = self._obtener_pqr()
        return PQRAdjunto.objects.filter(pqr=pqr).order_by("created_at")

    def perform_create(self, serializer):
        """Asocia el archivo a la PQR y al usuario autenticado."""
        pqr = self._obtener_pqr()
        es_gestor = self.request.user.tiene_permiso("pqr.gestionar")

        # Conserva la regla actual del módulo: el residente solo puede
        # modificar una PQR mientras siga en estado RECIBIDA.
        if not es_gestor and pqr.estado.codigo != "RECIBIDA":
            raise exceptions.PermissionDenied(
                "Solo puedes adjuntar archivos mientras la PQR esté en estado 'Recibida'."
            )

        serializer.save(
            pqr=pqr,
            subido_por=self.request.user,
        )


class PQRAdjuntoRetrieveUpdateDestroyView(generics.RetrieveUpdateDestroyAPIView):
    """Permite consultar, reemplazar o eliminar un adjunto de una PQR."""

    serializer_class = PQRAdjuntoSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    parser_classes = [MultiPartParser, FormParser]
    lookup_url_kwarg = "adjunto_id"

    def get_queryset(self):
        """Busca el adjunto dentro de la PQR autorizada para evitar cruces de ID."""
        pqr = get_object_or_404(
            pqrs_accesibles_para(self.request.user),
            pk=self.kwargs["pqr_id"],
        )
        return PQRAdjunto.objects.filter(pqr=pqr)

    def _validar_pqr_modificable(self):
        """Aplica al reemplazo y borrado la regla de estado para residentes."""
        pqr = get_object_or_404(
            pqrs_accesibles_para(self.request.user),
            pk=self.kwargs["pqr_id"],
        )
        if (
            not self.request.user.tiene_permiso("pqr.gestionar")
            and pqr.estado.codigo != "RECIBIDA"
        ):
            raise exceptions.PermissionDenied(
                "Solo puedes modificar archivos mientras la PQR esté en estado 'Recibida'."
            )

    def perform_update(self, serializer):
        """Guarda el nuevo archivo y registra al usuario que lo reemplazó."""
        self._validar_pqr_modificable()
        serializer.save(subido_por=self.request.user)

    def perform_destroy(self, instance):
        """Borra los metadatos y luego el objeto del almacenamiento."""
        self._validar_pqr_modificable()
        ruta = instance.ruta
        instance.delete()
        try:
            default_storage.delete(ruta)
        except OSError:
            logger.exception(
                "No se pudo eliminar el archivo del adjunto %s.",
                instance.pk,
            )


class PQRAdjuntoDownloadView(APIView):
    """Descarga un adjunto después de validar acceso a su PQR."""

    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]

    def get(self, request, pqr_id, adjunto_id):
        """Entrega el archivo solo después de comprobar acceso a la PQR asociada."""
        pqr = get_object_or_404(
            pqrs_accesibles_para(request.user),
            pk=pqr_id,
        )
        adjunto = get_object_or_404(
            PQRAdjunto.objects.filter(pqr=pqr),
            pk=adjunto_id,
        )

        try:
            archivo = default_storage.open(adjunto.ruta, "rb")
        except FileNotFoundError as error:
            # La fila de metadatos existe, pero el objeto no está en storage.
            raise Http404("El archivo adjunto ya no está disponible.") from error

        # Se entrega como descarga autenticada; no se publica una URL directa.
        return FileResponse(
            archivo,
            as_attachment=True,
            filename=adjunto.nombre_archivo,
            content_type=adjunto.tipo_mime or "application/octet-stream",
        )