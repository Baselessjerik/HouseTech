# Ubicación: backend/apps/pqrs/views.py

import logging

from django.core.files.storage import default_storage
from django.db import DatabaseError, transaction
from django.db.models import Q
from django.http import FileResponse, Http404
from django.shortcuts import get_object_or_404
from rest_framework import exceptions, generics, permissions, status
from rest_framework.parsers import FormParser, MultiPartParser
from rest_framework.response import Response
from rest_framework.views import APIView

from apps.core.models import Estado
from apps.core.permissions import requiere_permiso
from apps.inmuebles.models import Inmueble
from .models import (
    PQR,
    PQRAdjunto,
    PQRHistorial,
    PQRRespuesta,
    TipoPQR,
)
from .serializers import (
    InmuebleOpcionSerializer,
    PQRAdjuntoSerializer,
    PQRAsignarResponsableSerializer,
    PQRDetalleSerializer,
    PQRHistorialSerializer,
    PQRRegistroSerializer,
    PQRRespuestaSerializer,
    PQRTransicionEstadoSerializer,
    TipoPQRSerializer,
)

PuedeRadicarPQR = requiere_permiso("pqr.radicar")
PuedeGestionarPQR = requiere_permiso("pqr.gestionar")
PuedeAdministrarUsuarios = requiere_permiso("usuarios.gestionar")
logger = logging.getLogger(__name__)

TRANSICIONES_ESTADO_PQR = {
    "RECIBIDA": {"EN_REVISION", "ANULADA"},
    "EN_REVISION": {"EN_PROCESO", "ANULADA"},
    "EN_PROCESO": {"ATENDIDA", "ANULADA"},
    "ATENDIDA": {"CERRADA", "ANULADA"},
    "CERRADA": set(),
    "ANULADA": set(),
}

# Etapas en las que un no administrador puede anular una PQR.
ESTADOS_ANULABLES_SIN_ADMIN = {"RECIBIDA", "EN_REVISION"}


# Relaciones que usan los serializadores de lectura de PQR.
PQR_RELACIONES = ("tipo", "estado", "solicitante", "inmueble", "responsable")


def pqrs_accesibles_para(usuario):
    """Aplica visibilidad según el rol del usuario."""
    queryset = PQR.objects.select_related("estado")
    roles = set(usuario.codigos_roles())

    # 1. Administrador: ve absolutamente todas las PQRs
    if "ADMIN" in roles:
        return queryset

    # 2. Responsable PQR: ve las que le asignaron Y las que él mismo radicó
    if "RESPONSABLE_PQR" in roles:
        return queryset.filter(Q(responsable=usuario) | Q(solicitante=usuario))

    # 3. Residente: ve únicamente las PQRs donde él es el solicitante
    if "RESIDENTE" in roles:
        return queryset.filter(solicitante=usuario)

    # 4. Caso de seguridad: si no tiene ninguno de esos roles, no ve ninguna PQR
    return queryset.none()


def registrar_evento_pqr(pqr, usuario, comentario):
    """Registra un evento que no corresponde a transición o asignación."""
    PQRHistorial.objects.create(
        pqr=pqr,
        estado_anterior_id=pqr.estado_id,
        estado_nuevo_id=pqr.estado_id,
        responsable_id=pqr.responsable_id,
        usuario=usuario,
        comentario=comentario,
    )


def eliminar_archivo_adjunto(ruta, adjunto_id):
    """Limpia storage sin ocultar la excepción que motivó una reversión."""
    try:
        default_storage.delete(ruta)
    except OSError:
        logger.exception(
            "No se pudo eliminar el archivo del adjunto %s.",
            adjunto_id,
        )


class TipoPQRListView(generics.ListAPIView):
    """Expone el catálogo activo para clasificar nuevas solicitudes."""

    queryset = TipoPQR.objects.filter(activo=True).order_by("id")
    serializer_class = TipoPQRSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    pagination_class = None


class MisInmueblesPQRListView(generics.ListAPIView):
    """Devuelve inmuebles disponibles para radicar según el rol del usuario."""

    serializer_class = InmuebleOpcionSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    pagination_class = None

    def get_queryset(self):
        """Los gestores ven todos los inmuebles; el residente solo los vinculados."""
        usuario = self.request.user
        if usuario.tiene_permiso("pqr.gestionar"):
            return Inmueble.objects.filter(activo=True).order_by(
                "torre_bloque",
                "numero",
            )
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
        return (
            pqrs_accesibles_para(self.request.user)
            .select_related(*PQR_RELACIONES)
            .order_by("-fecha_radicacion")
        )

    def create(self, request, *args, **kwargs):
        """Persiste la solicitud y devuelve el radicado generado por la base de datos."""
        serializer = self.get_serializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        pqr = serializer.save()
        return Response(PQRDetalleSerializer(pqr).data, status=status.HTTP_201_CREATED)

class PQRRetrieveUpdateDestroyView(generics.RetrieveUpdateDestroyAPIView):
    """Permite consultar, editar y eliminar una PQR según sus permisos."""

    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]

    def get_serializer_class(self):
        """Selecciona el serializador de edición o el de lectura según el método."""
        if self.request.method in ["PUT", "PATCH"]:
            return PQRRegistroSerializer
        return PQRDetalleSerializer

    def get_queryset(self):
        """Evita que un residente acceda a solicitudes de otras personas."""
        return pqrs_accesibles_para(self.request.user).select_related(*PQR_RELACIONES)

    def perform_update(self, serializer):
        """Restringe y registra ediciones sin duplicar los eventos del trigger."""
        pqr = serializer.instance
        
        # Regla de bloqueo: si está CERRADA, rechaza modificaciones con 400 Bad Request
        if pqr.estado.codigo == "CERRADA":
            raise exceptions.ValidationError(
                {"detail": "Esta solicitud se encuentra cerrada y no admite modificaciones."}
            )

        # Regla de negocio: un residente solo puede editar si sigue en estado RECIBIDA
        if not self.request.user.tiene_permiso("pqr.gestionar") and pqr.estado.codigo != "RECIBIDA":
            raise exceptions.PermissionDenied("Solo puedes editar una PQR mientras esté en estado 'Recibida'.")

        campos_modificados = []
        for campo, valor_nuevo in serializer.validated_data.items():
            if hasattr(valor_nuevo, "pk"):
                valor_actual = getattr(pqr, f"{campo}_id")
                valor_nuevo = valor_nuevo.pk
            else:
                valor_actual = getattr(pqr, campo)
            if valor_actual != valor_nuevo:
                campos_modificados.append(campo)

        with transaction.atomic():
            serializer.save()
            if campos_modificados:
                registrar_evento_pqr(
                    pqr,
                    self.request.user,
                    "PQR editada; campos modificados: "
                    + ", ".join(sorted(campos_modificados)),
                )

    def destroy(self, request, *args, **kwargs):
        """Elimina el borrado físico (Hard Delete): las solicitudes nunca se borran."""
        raise exceptions.PermissionDenied(
            "El borrado físico de solicitudes no está permitido en el sistema."
        )

class PQRHistorialListView(generics.ListAPIView):
    """Devuelve el historial cronológico de una PQR accesible al usuario."""

    serializer_class = PQRHistorialSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    pagination_class = None

    def get_queryset(self):
        """Limita los eventos a PQR propias o visibles para gestores."""
        pqr = get_object_or_404(
            pqrs_accesibles_para(self.request.user),
            pk=self.kwargs["pqr_id"],
        )
        return (
            PQRHistorial.objects.filter(pqr=pqr)
            .select_related(
                "estado_anterior",
                "estado_nuevo",
                "responsable",
                "usuario",
            )
            .order_by("fecha", "id")
        )


class PQRTransicionEstadoView(APIView):
    """Permite a administradores y responsables avanzar una PQR de estado."""

    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]

    def patch(self, request, pk):
        """Valida y persiste una transición permitida del ciclo de vida."""
        serializer = PQRTransicionEstadoSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        estado_destino_codigo = serializer.validated_data["estado_codigo"]
        motivo = str(request.data.get("motivo", "")).strip()
        if estado_destino_codigo == "ANULADA" and len(motivo) < 5:
            raise exceptions.ValidationError(
                {"detail": "Debes indicar un motivo de anulación (mínimo 5 caracteres)."}
            )

        # Bloquea la fila de PQR mientras verifica y aplica el cambio, evitando
        # que solicitudes simultáneas validen el mismo estado anterior.
        with transaction.atomic():
            pqr = get_object_or_404(
                pqrs_accesibles_para(request.user).select_for_update(),
                pk=pk,
            )

            es_administrador = request.user.tiene_permiso("usuarios.gestionar")
            es_responsable_asignado = (
                request.user.tiene_permiso("pqr.gestionar")
                and pqr.responsable_id == request.user.pk
            )
            if (
                not (es_administrador or es_responsable_asignado)
                and estado_destino_codigo != "ANULADA"
            ):
                raise exceptions.PermissionDenied(
                    "Solo el administrador o el responsable asignado pueden "
                    "cambiar el estado de la PQR."
                )

            destinos_permitidos = TRANSICIONES_ESTADO_PQR.get(
                pqr.estado.codigo,
                set(),
            )

            if estado_destino_codigo not in destinos_permitidos:
                destinos_texto = ", ".join(sorted(destinos_permitidos)) or "ninguno"
                return Response(
                    {
                        "estado_codigo": (
                            f"No se permite pasar de '{pqr.estado.codigo}' "
                            f"a '{estado_destino_codigo}'. "
                            f"Destinos permitidos: {destinos_texto}."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if (
                estado_destino_codigo == "ANULADA"
                and not request.user.tiene_permiso("usuarios.gestionar")
                and pqr.estado.codigo not in ESTADOS_ANULABLES_SIN_ADMIN
            ):
                raise exceptions.PermissionDenied(
                    "Solo el administrador puede anular una PQR que ya está "
                    "en proceso o atendida."
                )

            estado_destino = Estado.objects.filter(
                proceso="PQR",
                codigo=estado_destino_codigo,
                activo=True,
            ).first()
            if estado_destino is None:
                return Response(
                    {
                        "estado_codigo": (
                            "El estado de destino no está configurado "
                            "como activo para el proceso PQR."
                        )
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )

            pqr.estado = estado_destino
            # Los triggers registran el historial y actualizan fecha_cierre
            # cuando el nuevo estado está marcado como final.
            pqr.save(update_fields=["estado", "updated_at"])
            pqr.refresh_from_db()

            if estado_destino_codigo == "ANULADA":
                registrar_evento_pqr(
                    pqr, request.user, f"PQR anulada. Motivo: {motivo}"
                )

        return Response(
            PQRDetalleSerializer(pqr).data,
            status=status.HTTP_200_OK,
        )


class PQRRespuestaListCreateView(generics.ListCreateAPIView):
    """Permite consultar respuestas y registrar respuestas autorizadas."""

    serializer_class = PQRRespuestaSerializer
    permission_classes = [permissions.IsAuthenticated, PuedeRadicarPQR]
    pagination_class = None

    def _obtener_pqr(self):
        """Busca la PQR dentro de las solicitudes visibles al usuario."""
        return get_object_or_404(
            pqrs_accesibles_para(self.request.user),
            pk=self.kwargs["pqr_id"],
        )

    def get_queryset(self):
        """Devuelve las respuestas de la PQR en orden cronológico."""
        pqr = self._obtener_pqr()
        return (
            PQRRespuesta.objects.filter(pqr=pqr)
            .select_related("responsable")
            .order_by("created_at", "id")
        )

    def perform_create(self, serializer):
        """Guarda la respuesta del administrador, del responsable asignado o del solicitante."""
        usuario = self.request.user

        with transaction.atomic():
            pqr = get_object_or_404(
                PQR.objects.select_for_update(),
                pk=self.kwargs["pqr_id"],
            )

            if (
                not usuario.tiene_permiso("pqr.gestionar")
                and pqr.solicitante_id != usuario.pk
            ):
                raise Http404

            es_administrador = usuario.tiene_permiso("usuarios.gestionar")
            es_responsable_asignado = (
                usuario.tiene_permiso("pqr.gestionar")
                and pqr.responsable_id == usuario.pk
            )
            es_solicitante = pqr.solicitante_id == usuario.pk
            es_atencion = es_administrador or es_responsable_asignado
            if not (es_atencion or es_solicitante):
                raise exceptions.PermissionDenied(
                    "Solo el administrador, el responsable asignado o quien "
                    "radicó la PQR pueden registrar una respuesta."
                )

            if pqr.estado.codigo in {"CERRADA", "ANULADA"}:
                raise exceptions.ValidationError(
                    {"detail": "La solicitud está cerrada o anulada y no admite nuevas respuestas."}
                )

            # Quien solo radicó la PQR envía mensajes de seguimiento: no marca
            # solución ni cambia el estado.
            extra = {} if es_atencion else {"es_solucion": False}
            respuesta = serializer.save(pqr=pqr, responsable=usuario, **extra)

            if es_atencion:
                destino_codigo = "CERRADA" if respuesta.es_solucion else "ATENDIDA"
                estado_destino = Estado.objects.filter(
                    proceso="PQR",
                    codigo=destino_codigo,
                    activo=True,
                ).first()
                if estado_destino is not None:
                    pqr.estado = estado_destino
                    pqr.save(update_fields=["estado", "updated_at"])
                    pqr.refresh_from_db()

            if respuesta.es_solucion:
                comentario_historial = (
                    f"PQR cerrada por {usuario.nombre_completo}. "
                    f"Solución final: {respuesta.respuesta}"
                )
            elif es_atencion:
                comentario_historial = "Respuesta registrada."
            else:
                comentario_historial = "Respuesta del solicitante registrada."
            registrar_evento_pqr(pqr, usuario, comentario_historial)


class PQRAsignarResponsableView(APIView):
    """Permite a un administrador asignar o reasignar el responsable de una PQR."""

    permission_classes = [
        permissions.IsAuthenticated,
        PuedeAdministrarUsuarios,
    ]

    def patch(self, request, pk):
        """Valida al responsable y guarda la asignación en la PQR."""
        serializer = PQRAsignarResponsableSerializer(data=request.data)
        serializer.is_valid(raise_exception=True)
        responsable = serializer.validated_data["responsable"]

        # Bloquea la PQR durante el cambio para serializar asignaciones
        # concurrentes y conservar una trazabilidad consistente.
        with transaction.atomic():
            pqr = get_object_or_404(
                PQR.objects.select_for_update(),
                pk=pk,
            )
            pqr.responsable = responsable
            if pqr.estado.codigo in {"RECIBIDA", "EN_REVISION"}:
                estado_proceso = Estado.objects.filter(
                    proceso="PQR",
                    codigo="EN_PROCESO",
                    activo=True,
                ).first()
                if estado_proceso is not None:
                    pqr.estado = estado_proceso
            # El trigger trg_pqr_hist registra el cambio en pqr_historial.
            pqr.save(update_fields=["responsable", "estado", "updated_at"])
            pqr.refresh_from_db()

        return Response(
            PQRDetalleSerializer(pqr).data,
            status=status.HTTP_200_OK,
        )


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

        adjunto = None
        try:
            with transaction.atomic():
                adjunto = serializer.save(
                    pqr=pqr,
                    subido_por=self.request.user,
                )
                registrar_evento_pqr(
                    pqr,
                    self.request.user,
                    f"Adjunto cargado: {adjunto.nombre_archivo}.",
                )
        except DatabaseError:
            # El archivo ya se guardó fuera de la transacción SQL; si el
            # evento no se puede persistir, se elimina para no dejar huérfanos.
            if adjunto is not None:
                eliminar_archivo_adjunto(adjunto.ruta, adjunto.pk)
            raise


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
        adjunto = serializer.instance
        ruta_anterior = adjunto.ruta
        try:
            with transaction.atomic():
                adjunto = serializer.save(subido_por=self.request.user)
                registrar_evento_pqr(
                    adjunto.pqr,
                    self.request.user,
                    f"Adjunto reemplazado: {adjunto.nombre_archivo}.",
                )
        except DatabaseError:
            # La nueva ruta se elimina si la transacción que registra el
            # reemplazo falla; el archivo anterior se conserva hasta commit.
            if adjunto.ruta != ruta_anterior:
                eliminar_archivo_adjunto(adjunto.ruta, adjunto.pk)
            raise

    def perform_destroy(self, instance):
        """Registra la eliminación y borra metadatos y archivo al confirmar."""
        self._validar_pqr_modificable()
        ruta = instance.ruta
        adjunto_id = instance.pk
        with transaction.atomic():
            registrar_evento_pqr(
                instance.pqr,
                self.request.user,
                f"Adjunto eliminado: {instance.nombre_archivo}.",
            )
            instance.delete()
            transaction.on_commit(
                lambda: eliminar_archivo_adjunto(ruta, adjunto_id)
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