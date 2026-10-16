"""Tablas transversales. El esquema real lo crea sql/schema.sql (managed = False)."""
from django.conf import settings
from django.db import models


class Copropiedad(models.Model):
    nombre = models.CharField(max_length=150)
    nit = models.CharField(max_length=30, unique=True, null=True, blank=True)
    direccion = models.CharField(max_length=200, null=True, blank=True)
    ciudad = models.CharField(max_length=100, null=True, blank=True)
    telefono = models.CharField(max_length=30, null=True, blank=True)
    email = models.CharField(max_length=150, null=True, blank=True)
    descripcion = models.TextField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "copropiedad"
        verbose_name_plural = "copropiedades"

    def __str__(self):
        return self.nombre


class Estado(models.Model):
    """Estados configurables por proceso (PQR, RESERVA, MANTENIMIENTO)."""

    proceso = models.CharField(max_length=20)
    codigo = models.CharField(max_length=30)
    nombre = models.CharField(max_length=60)
    orden = models.SmallIntegerField(default=0)
    es_inicial = models.BooleanField(default=False)
    es_final = models.BooleanField(default=False)
    activo = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = "estados"

    def __str__(self):
        return f"{self.proceso}:{self.codigo}"


class Auditoria(models.Model):
    """Solo lectura: la llenan los triggers de la BD, nunca la aplicación."""

    fecha = models.DateTimeField()
    usuario = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        on_delete=models.DO_NOTHING,  # la BD ya hace SET NULL
        related_name="+",
    )
    tabla = models.CharField(max_length=63)
    registro_id = models.CharField(max_length=40, null=True)
    operacion = models.CharField(max_length=6)
    datos_anteriores = models.JSONField(null=True)
    datos_nuevos = models.JSONField(null=True)

    class Meta:
        managed = False
        db_table = "auditoria"
        ordering = ["-fecha"]
