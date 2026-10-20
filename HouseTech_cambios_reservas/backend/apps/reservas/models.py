"""Amenidades (zonas comunes) y reservas. Esquema real: core/sql/schema.sql + sql/reservas_v2.sql."""
from django.conf import settings
from django.db import models


class Amenidad(models.Model):
    copropiedad = models.ForeignKey(
        "core.Copropiedad", on_delete=models.DO_NOTHING, related_name="amenidades"
    )
    nombre = models.CharField(max_length=100)
    descripcion = models.TextField(null=True, blank=True)
    capacidad = models.IntegerField(null=True, blank=True)  # aforo máximo por reserva
    condiciones_uso = models.TextField(null=True, blank=True)
    activa = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "amenidades"
        verbose_name_plural = "amenidades"

    def __str__(self):
        return self.nombre


class AmenidadHorario(models.Model):
    """Horario de funcionamiento. dia_semana: 1 = lunes ... 7 = domingo (isoweekday)."""

    amenidad = models.ForeignKey(Amenidad, on_delete=models.DO_NOTHING, related_name="horarios")
    dia_semana = models.SmallIntegerField()
    hora_apertura = models.TimeField()
    hora_cierre = models.TimeField()
    activo = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = "amenidad_horarios"


class ReglaReserva(models.Model):
    """Políticas de reserva y de cancelación de una amenidad (una fila por amenidad)."""

    amenidad = models.OneToOneField(Amenidad, on_delete=models.DO_NOTHING, related_name="reglas")
    duracion_min_minutos = models.IntegerField(default=30)
    duracion_max_minutos = models.IntegerField(default=240)
    anticipacion_min_horas = models.IntegerField(default=1)
    anticipacion_max_dias = models.IntegerField(default=30)
    max_reservas_mes_inmueble = models.IntegerField(null=True, blank=True)
    horas_limite_cancelacion = models.IntegerField(default=24)
    requiere_confirmacion = models.BooleanField(default=True)
    horas_limite_confirmacion = models.IntegerField(default=24)  # plazo de la administración para confirmar
    horas_recordatorio = models.IntegerField(default=24)  # recordatorio X h antes del inicio; 0 = ninguno
    observaciones = models.TextField(null=True, blank=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "reglas_reserva"


class Reserva(models.Model):
    amenidad = models.ForeignKey(Amenidad, on_delete=models.DO_NOTHING, related_name="reservas")
    usuario = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.DO_NOTHING, related_name="reservas"
    )
    inmueble = models.ForeignKey(
        "inmuebles.Inmueble", null=True, blank=True, on_delete=models.DO_NOTHING, related_name="reservas"
    )
    fecha_inicio = models.DateTimeField()
    fecha_fin = models.DateTimeField()
    num_personas = models.IntegerField(null=True, blank=True)
    estado = models.ForeignKey("core.Estado", on_delete=models.DO_NOTHING, related_name="+")
    estado_proceso = models.CharField(max_length=20, default="RESERVA")
    observaciones = models.TextField(null=True, blank=True)
    confirmada_por = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.DO_NOTHING,
        related_name="+", db_column="confirmada_por",
    )
    confirmada_en = models.DateTimeField(null=True, blank=True)
    cancelada_por = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.DO_NOTHING,
        related_name="+", db_column="cancelada_por",
    )
    cancelada_en = models.DateTimeField(null=True, blank=True)
    motivo_cancelacion = models.TextField(null=True, blank=True)
    recordatorio_enviado_en = models.DateTimeField(null=True, blank=True)
    aviso_pendiente_en = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "reservas"


class ReservaHistorial(models.Model):
    """Solo lectura: la llena el trigger fn_reservas_historial (RF11)."""

    reserva = models.ForeignKey(Reserva, on_delete=models.DO_NOTHING, related_name="historial")
    estado_anterior = models.ForeignKey(
        "core.Estado", null=True, on_delete=models.DO_NOTHING, related_name="+"
    )
    estado_nuevo = models.ForeignKey("core.Estado", on_delete=models.DO_NOTHING, related_name="+")
    usuario = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, on_delete=models.DO_NOTHING, related_name="+"
    )
    detalle = models.TextField(null=True)
    fecha = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "reservas_historial"
        ordering = ["fecha", "id"]


class BloqueoAmenidad(models.Model):
    amenidad = models.ForeignKey(Amenidad, on_delete=models.DO_NOTHING, related_name="bloqueos")
    fecha_inicio = models.DateTimeField()
    fecha_fin = models.DateTimeField()
    motivo = models.TextField()
    cancelado = models.BooleanField(default=False)
    cancelado_en = models.DateTimeField(null=True, blank=True)
    creado_por = models.ForeignKey(
        settings.AUTH_USER_MODEL, null=True, blank=True, on_delete=models.DO_NOTHING,
        related_name="+", db_column="creado_por",
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "bloqueos_amenidad"
