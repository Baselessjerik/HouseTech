from rest_framework import serializers
from pathlib import PurePosixPath
from uuid import uuid4
import logging

from django.core.files.storage import default_storage
from django.db import DatabaseError
from apps.core.models import Estado
from apps.inmuebles.models import Inmueble, InmuebleUsuario
from .models import PQR, PQRAdjunto, TipoPQR

logger = logging.getLogger(__name__)


class TipoPQRSerializer(serializers.ModelSerializer):
    """Información de tipos de PQR para poblar el selector en el formulario."""

    class Meta:
        """Limita la salida del catálogo a campos utilizados por el formulario."""

        model = TipoPQR
        fields = ["id", "codigo", "nombre", "prefijo", "descripcion", "sla_dias"]


class InmuebleOpcionSerializer(serializers.ModelSerializer):
    """Información básica de inmuebles del residente para asociar a la PQR."""

    class Meta:
        """Define los datos mínimos que necesita el selector de inmuebles."""

        model = Inmueble
        fields = ["id", "codigo_interno", "tipo", "torre_bloque", "numero"]


class PQRDetalleSerializer(serializers.ModelSerializer):
    """Respuesta tras radicar o consultar el detalle de una PQR."""

    tipo = TipoPQRSerializer(read_only=True)
    estado_codigo = serializers.CharField(source="estado.codigo", read_only=True)
    estado_nombre = serializers.CharField(source="estado.nombre", read_only=True)
    solicitante_nombre = serializers.CharField(source="solicitante.nombre_completo", read_only=True)
    inmueble_codigo = serializers.CharField(source="inmueble.codigo_interno", read_only=True, default=None)

    class Meta:
        """Describe la representación de lectura enviada a clientes PQR."""

        # Atributos derivados y campos de radicación se devuelven solo como lectura.
        model = PQR
        fields = [
            "id",
            "radicado",
            "tipo",
            "asunto",
            "descripcion",
            "prioridad",
            "estado_codigo",
            "estado_nombre",
            "solicitante_nombre",
            "inmueble_codigo",
            "fecha_radicacion",
            "fecha_cierre",
        ]


class PQRTransicionEstadoSerializer(serializers.Serializer):
    """Valida el código del estado de destino solicitado por un gestor."""

    estado_codigo = serializers.ChoiceField(
        choices=[
            ("EN_REVISION", "En revisión"),
            ("EN_PROCESO", "En proceso"),
            ("ATENDIDA", "Atendida"),
            ("CERRADA", "Cerrada"),
        ]
    )


class PQRRegistroSerializer(serializers.ModelSerializer):
    """Valida y procesa los datos enviados desde el formulario de registro de PQR."""

    tipo_id = serializers.PrimaryKeyRelatedField(
        queryset=TipoPQR.objects.filter(activo=True),
        source="tipo",
        help_text="ID del tipo de PQR seleccionado (Petición, Queja, Reclamo)",
    )
    inmueble_id = serializers.PrimaryKeyRelatedField(
        queryset=Inmueble.objects.filter(activo=True),
        source="inmueble",
        required=False,
        allow_null=True,
        help_text="ID opcional del inmueble relacionado con la solicitud",
    )

    class Meta:
        """Define los campos aceptados al registrar o editar una solicitud."""

        model = PQR
        fields = [
            "tipo_id",
            "inmueble_id",
            "asunto",
            "descripcion",
            "prioridad",
        ]

    def validate_tipo_id(self, tipo: TipoPQR) -> TipoPQR:
        """Impide cambiar el tipo después de que la PQR ya tiene radicado."""
        if self.instance is not None and self.instance.tipo_id != tipo.pk:
            raise serializers.ValidationError(
                "No se puede cambiar el tipo de una PQR después de radicarla."
            )
        return tipo

    def validate_asunto(self, value: str) -> str:
        """Normaliza espacios y exige el mínimo de caracteres del asunto."""
        asunto_limpio = value.strip()
        if len(asunto_limpio) < 5:
            raise serializers.ValidationError("El asunto debe contener al menos 5 caracteres.")
        return asunto_limpio

    def validate_descripcion(self, value: str) -> str:
        """Normaliza espacios y exige una descripción suficientemente detallada."""
        desc_limpia = value.strip()
        if len(desc_limpia) < 10:
            raise serializers.ValidationError("La descripción debe ser detallada (mínimo 10 caracteres).")
        return desc_limpia

    def validate_inmueble_id(self, inmueble):
        """Si se especifica un inmueble, verificar que el residente tenga vínculo vigente con él."""
        if inmueble is None:
            return None

        usuario = self.context["request"].user
        # Se permite si el usuario tiene relación activa con el inmueble o si es administrador
        tiene_vinculo = InmuebleUsuario.objects.filter(
            inmueble=inmueble,
            usuario=usuario,
            fecha_fin__isnull=True,
        ).exists()

        if not tiene_vinculo and not usuario.tiene_permiso("pqr.gestionar"):
            raise serializers.ValidationError(
                "Solo puedes radicar una PQR sobre un inmueble en el cual figuras como residente, propietario o arrendatario activo."
            )
        return inmueble

    def create(self, validated_data):
        """Asigna solicitante y estado inicial antes de persistir la PQR."""
        # 1. Asignar solicitante: el usuario autenticado (nadie radica a nombre de otro)
        solicitante = self.context["request"].user

        # 2. Asignar estado inicial configurado en base de datos para el proceso PQR (RECIBIDA)
        estado_inicial = Estado.objects.filter(proceso="PQR", es_inicial=True).first()
        if not estado_inicial:
            raise serializers.ValidationError(
                {"estado": "No se encontró un estado inicial configurado para el proceso PQR."}
            )

        # 3. Crear instancia
        pqr = PQR.objects.create(
            solicitante=solicitante,
            estado=estado_inicial,
            estado_proceso="PQR",
            **validated_data,
        )

        # 4. Refrescar desde BD para leer los valores asignados por triggers (radicado, fecha_radicacion)
        pqr.refresh_from_db()
        return pqr

# Política inicial de carga. Confírmala con el negocio antes de producción:
# hasta 10 MiB por archivo, en formatos PDF, JPEG o PNG.
TAMANO_MAXIMO_ADJUNTO = 10 * 1024 * 1024

# Por cada extensión se fija el MIME canónico y la firma binaria que debe traer el archivo.
TIPOS_ADJUNTO_PERMITIDOS = {
    ".pdf": ("application/pdf", lambda contenido: contenido.startswith(b"%PDF-")),
    ".jpg": ("image/jpeg", lambda contenido: contenido.startswith(b"\xff\xd8\xff")),
    ".jpeg": ("image/jpeg", lambda contenido: contenido.startswith(b"\xff\xd8\xff")),
    ".png": (
        "image/png",
        lambda contenido: contenido.startswith(b"\x89PNG\r\n\x1a\n"),
    ),
}


class PQRAdjuntoSerializer(serializers.ModelSerializer):
    """Crea o reemplaza un archivo adjunto y registra sus metadatos."""

    archivo = serializers.FileField(write_only=True, required=False)

    class Meta:
        """Expone metadatos de lectura y acepta el archivo solo como entrada."""

        model = PQRAdjunto
        fields = [
            "id",
            "nombre_archivo",
            "tipo_mime",
            "tamano_bytes",
            "created_at",
            "archivo",
        ]
        read_only_fields = [
            "id",
            "nombre_archivo",
            "tipo_mime",
            "tamano_bytes",
            "created_at",
        ]

    def validate_archivo(self, archivo):
        """Rechaza archivos demasiado grandes o cuyo contenido no coincide con su extensión."""
        if archivo.size > TAMANO_MAXIMO_ADJUNTO:
            raise serializers.ValidationError(
                "El archivo no puede superar los 10 MiB."
            )

        # Normaliza separadores y examina solo el nombre base para que
        # una ruta enviada por el cliente nunca se use como ruta de storage.
        nombre = archivo.name.replace("\\", "/").rsplit("/", 1)[-1]
        extension = PurePosixPath(nombre).suffix.lower()

        tipo_configurado = TIPOS_ADJUNTO_PERMITIDOS.get(extension)
        if tipo_configurado is None:
            raise serializers.ValidationError(
                "Formato no permitido. Adjunta un archivo PDF, JPG o PNG."
            )

        # El MIME declarado por el cliente no es prueba del tipo real.
        # Se revisa la firma del archivo y luego se vuelve al inicio
        # para que storage pueda leerlo completo.
        _, comprobar_contenido = tipo_configurado
        firma = archivo.read(8)
        archivo.seek(0)

        if not comprobar_contenido(firma):
            raise serializers.ValidationError(
                "El contenido del archivo no coincide con un PDF, JPG o PNG válido."
            )

        return archivo

    def validate(self, attrs):
        """Exige un archivo en creación y en reemplazo, incluso con PATCH."""
        if "archivo" not in attrs:
            raise serializers.ValidationError(
                {"archivo": "Debes seleccionar el archivo que se va a guardar."}
            )
        return attrs

    @staticmethod
    def _guardar_archivo(archivo, pqr):
        """Almacena el archivo con ruta aleatoria y devuelve los metadatos verificados."""
        nombre_original = archivo.name.replace("\\", "/").rsplit("/", 1)[-1]
        extension = PurePosixPath(nombre_original).suffix.lower()
        tipo_mime, _ = TIPOS_ADJUNTO_PERMITIDOS[extension]
        ruta_solicitada = f"pqrs/{pqr.pk}/{uuid4().hex}{extension}"
        ruta_guardada = default_storage.save(ruta_solicitada, archivo)
        return ruta_guardada, nombre_original[:255], tipo_mime, archivo.size

    def create(self, validated_data):
        """Guarda el archivo con un nombre aleatorio y luego crea su fila de metadatos."""
        archivo = validated_data.pop("archivo")
        pqr = validated_data["pqr"]
        usuario = validated_data["subido_por"]
        ruta, nombre, tipo_mime, tamano = self._guardar_archivo(archivo, pqr)

        try:
            return PQRAdjunto.objects.create(
                pqr=pqr,
                nombre_archivo=nombre,
                ruta=ruta,
                tipo_mime=tipo_mime,
                tamano_bytes=tamano,
                subido_por=usuario,
            )
        except DatabaseError:
            # Evita dejar contenido huérfano si la fila no se pudo guardar.
            default_storage.delete(ruta)
            raise

    def update(self, instance, validated_data):
        """Reemplaza el contenido del adjunto conservando su identificador."""
        archivo = validated_data.pop("archivo")
        ruta_anterior = instance.ruta
        ruta, nombre, tipo_mime, tamano = self._guardar_archivo(
            archivo,
            instance.pqr,
        )

        instance.nombre_archivo = nombre
        instance.ruta = ruta
        instance.tipo_mime = tipo_mime
        instance.tamano_bytes = tamano
        instance.subido_por = validated_data.get("subido_por", instance.subido_por)

        try:
            instance.save(
                update_fields=[
                    "nombre_archivo",
                    "ruta",
                    "tipo_mime",
                    "tamano_bytes",
                    "subido_por",
                ]
            )
        except DatabaseError:
            # El archivo anterior sigue intacto si no pudo guardarse la referencia nueva.
            default_storage.delete(ruta)
            raise

        try:
            default_storage.delete(ruta_anterior)
        except OSError:
            logger.exception(
                "No se pudo eliminar el archivo anterior del adjunto %s.",
                instance.pk,
            )

        return instance