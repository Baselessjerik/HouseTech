from django.conf import settings
from django.db import models


class TipoPQR(models.Model):
    """Catálogo de tipos de PQR (Petición, Queja, Reclamo).

    Define el prefijo con el que se construye el número de radicado y el SLA estimado en días.
    """

    codigo = models.CharField(max_length=20, unique=True)
    nombre = models.CharField(max_length=60)
    prefijo = models.CharField(max_length=5, unique=True)
    descripcion = models.CharField(max_length=200, null=True, blank=True)
    sla_dias = models.SmallIntegerField(null=True, blank=True)
    activo = models.BooleanField(default=True)

    class Meta:
        """Define la tabla SQL existente y el orden del catálogo."""

        # La estructura se crea desde schema.sql; Django solo consulta estos registros.
        managed = False
        db_table = "tipos_pqr"
        ordering = ["id"]

    def __str__(self):
        """Devuelve el nombre legible del tipo y su código estable."""
        return f"{self.nombre} ({self.codigo})"


class PQR(models.Model):
    """Entidad principal de PQR radicada por un residente."""

    class Prioridad(models.TextChoices):
        """Valores admitidos por la prioridad de una solicitud."""

        BAJA = "BAJA", "Baja"
        MEDIA = "MEDIA", "Media"
        ALTA = "ALTA", "Alta"

    # El trigger trg_pqr_before crea el consecutivo único a partir del tipo y el año.
    radicado = models.CharField(max_length=30, unique=True, null=True, blank=True)
    tipo = models.ForeignKey(
        TipoPQR,
        on_delete=models.RESTRICT,
        db_column="tipo_id",
        related_name="pqrs",
    )
    solicitante = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.RESTRICT,
        db_column="solicitante_id",
        related_name="pqrs_radicadas",
    )
    inmueble = models.ForeignKey(
        "inmuebles.Inmueble",
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="inmueble_id",
        related_name="pqrs",
    )
    asunto = models.CharField(max_length=200)
    descripcion = models.TextField()
    prioridad = models.CharField(
        max_length=6,
        choices=Prioridad.choices,
        default=Prioridad.MEDIA,
    )
    # Los estados del flujo se comparten con el catálogo general de procesos.
    estado = models.ForeignKey(
        "core.Estado",
        on_delete=models.DO_NOTHING,
        db_column="estado_id",
        related_name="pqrs",
    )
    estado_proceso = models.CharField(max_length=20, default="PQR")
    responsable = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="responsable_id",
        related_name="pqrs_asignadas",
    )
    fecha_radicacion = models.DateTimeField(auto_now_add=True)
    fecha_cierre = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        """Vincula el modelo con la tabla PQR creada en el esquema SQL."""

        # La tabla está administrada por el esquema SQL compartido del proyecto.
        managed = False
        db_table = "pqr"
        ordering = ["-fecha_radicacion"]

    def __str__(self):
        """Identifica la solicitud por su radicado y asunto."""
        return f"{self.radicado or 'SIN-RADICAR'}: {self.asunto}"


class PQRAdjunto(models.Model):
    """Metadatos de evidencias; el contenido se conserva en el storage configurado."""

    pqr = models.ForeignKey(
        PQR,
        on_delete=models.CASCADE,
        db_column="pqr_id",
        related_name="adjuntos",
    )
    nombre_archivo = models.CharField(max_length=255)
    # Ruta interna aleatoria de almacenamiento; nunca se expone como URL pública.
    ruta = models.CharField(max_length=500)
    tipo_mime = models.CharField(max_length=100, null=True, blank=True)
    tamano_bytes = models.BigIntegerField(null=True, blank=True)
    subido_por = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="subido_por",
        related_name="+",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        """Vincula los metadatos con su tabla y orden cronológico."""

        # La tabla está administrada por el esquema SQL compartido del proyecto.
        managed = False
        db_table = "pqr_adjuntos"
        ordering = ["created_at"]


class PQRRespuesta(models.Model):
    """Respuestas formales o soluciones emitidas a la PQR."""

    pqr = models.ForeignKey(
        PQR,
        on_delete=models.CASCADE,
        db_column="pqr_id",
        related_name="respuestas",
    )
    responsable = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="responsable_id",
        related_name="+",
    )
    respuesta = models.TextField()
    es_solucion = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        """Vincula las respuestas con su tabla y orden cronológico."""

        # La tabla está administrada por el esquema SQL compartido del proyecto.
        managed = False
        db_table = "pqr_respuestas"
        ordering = ["created_at"]


class PQRHistorial(models.Model):
    """Trazabilidad de cambios de estado y asignaciones (manejado por triggers)."""

    pqr = models.ForeignKey(
        PQR,
        on_delete=models.CASCADE,
        db_column="pqr_id",
        related_name="historial",
    )
    estado_anterior = models.ForeignKey(
        "core.Estado",
        null=True,
        blank=True,
        on_delete=models.DO_NOTHING,
        db_column="estado_anterior_id",
        related_name="+",
    )
    estado_nuevo = models.ForeignKey(
        "core.Estado",
        on_delete=models.DO_NOTHING,
        db_column="estado_nuevo_id",
        related_name="+",
    )
    responsable = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="responsable_id",
        related_name="+",
    )
    usuario = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        db_column="usuario_id",
        related_name="+",
    )
    comentario = models.TextField(null=True, blank=True)
    fecha = models.DateTimeField(auto_now_add=True)

    class Meta:
        """Vincula el historial con la tabla que alimentan los triggers."""

        # El historial se alimenta por triggers de base de datos.
        managed = False
        db_table = "pqr_historial"
        ordering = ["fecha"]