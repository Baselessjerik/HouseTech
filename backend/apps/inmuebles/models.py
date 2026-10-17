import datetime

from django.conf import settings
from django.db import models


class Inmueble(models.Model):
    class Tipo(models.TextChoices):
        APARTAMENTO = "APARTAMENTO"
        CASA = "CASA"
        LOCAL = "LOCAL"
        PARQUEADERO = "PARQUEADERO"
        OTRO = "OTRO"

    copropiedad = models.ForeignKey(
        "core.Copropiedad", on_delete=models.DO_NOTHING, related_name="inmuebles"
    )
    tipo = models.CharField(max_length=15, choices=Tipo.choices, default=Tipo.APARTAMENTO)
    torre_bloque = models.CharField(max_length=30, null=True, blank=True)
    piso = models.SmallIntegerField(null=True, blank=True)
    numero = models.CharField(max_length=20)
    codigo_interno = models.CharField(max_length=40, unique=True)
    area_m2 = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    activo = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "inmuebles"

    def __str__(self):
        return self.codigo_interno


class InmuebleUsuario(models.Model):
    """Vínculo propietario / arrendatario / residente. Vigente = fecha_fin NULL."""

    class Relacion(models.TextChoices):
        PROPIETARIO = "PROPIETARIO"
        ARRENDATARIO = "ARRENDATARIO"
        RESIDENTE = "RESIDENTE"

    inmueble = models.ForeignKey(Inmueble, on_delete=models.DO_NOTHING, related_name="vinculos")
    usuario = models.ForeignKey(
        settings.AUTH_USER_MODEL, on_delete=models.DO_NOTHING, related_name="vinculos_inmueble"
    )
    tipo_relacion = models.CharField(max_length=15, choices=Relacion.choices)
    fecha_inicio = models.DateField(default=datetime.date.today)
    fecha_fin = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "inmueble_usuario"
