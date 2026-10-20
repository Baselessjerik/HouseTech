"""Tablas del Módulo 2 (Comunicados, mantenimientos y bloqueos).

El esquema real lo crea core/sql/schema.sql: todos los modelos son managed = False.

`AmenidadRef` y `ReservaRef` son modelos MÍNIMOS de lectura de tablas que pertenecen a
otro módulo (amenidades y reservas). Al unir los 4 módulos se pueden sustituir por los
modelos reales sin cambiar la BD.
"""
import datetime  # noqa: F401  (usado por migraciones generadas)

from django.conf import settings
from django.db import models

from apps.core.models import Copropiedad, Estado

USUARIO = settings.AUTH_USER_MODEL


# --------------------------------------------------------------------------- lectura
class AmenidadRef(models.Model):
    copropiedad = models.ForeignKey(Copropiedad, on_delete=models.DO_NOTHING, related_name="+")
    nombre = models.CharField(max_length=100)
    descripcion = models.TextField(null=True, blank=True)
    capacidad = models.IntegerField(null=True, blank=True)
    condiciones_uso = models.TextField(null=True, blank=True)
    activa = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "amenidades"

    def __str__(self):
        return self.nombre


class ReservaRef(models.Model):
    amenidad = models.ForeignKey(AmenidadRef, on_delete=models.DO_NOTHING, related_name="reservas_ref")
    usuario = models.ForeignKey(USUARIO, on_delete=models.DO_NOTHING, related_name="+")
    fecha_inicio = models.DateTimeField()
    fecha_fin = models.DateTimeField()
    estado = models.ForeignKey(Estado, on_delete=models.DO_NOTHING, related_name="+")
    num_personas = models.IntegerField(null=True, blank=True)

    class Meta:
        managed = False
        db_table = "reservas"


# --------------------------------------------------------------- mantenimientos / bloqueos
class Mantenimiento(models.Model):
    amenidad = models.ForeignKey(
        AmenidadRef, null=True, blank=True, on_delete=models.DO_NOTHING, related_name="mantenimientos"
    )
    titulo = models.CharField(max_length=150)
    descripcion = models.TextField(null=True, blank=True)
    fecha_inicio = models.DateTimeField()
    fecha_fin = models.DateTimeField()
    estado = models.ForeignKey(Estado, on_delete=models.DO_NOTHING, related_name="+")
    responsable = models.CharField(max_length=150, null=True, blank=True)
    creado_por = models.ForeignKey(
        USUARIO, null=True, blank=True, on_delete=models.DO_NOTHING, related_name="+", db_column="creado_por"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "mantenimientos"

    def __str__(self):
        return self.titulo


class Bloqueo(models.Model):
    amenidad = models.ForeignKey(AmenidadRef, on_delete=models.DO_NOTHING, related_name="bloqueos")
    mantenimiento = models.ForeignKey(
        Mantenimiento, null=True, blank=True, on_delete=models.DO_NOTHING, related_name="bloqueos"
    )
    fecha_inicio = models.DateTimeField()
    fecha_fin = models.DateTimeField()
    motivo = models.TextField()
    cancelado = models.BooleanField(default=False)
    cancelado_en = models.DateTimeField(null=True, blank=True)
    creado_por = models.ForeignKey(
        USUARIO, null=True, blank=True, on_delete=models.DO_NOTHING, related_name="+", db_column="creado_por"
    )
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "bloqueos_amenidad"


# ------------------------------------------------------------------------ comunicados
class CategoriaComunicado(models.Model):
    nombre = models.CharField(max_length=80, unique=True)
    descripcion = models.CharField(max_length=200, null=True, blank=True)
    color = models.CharField(max_length=9, null=True, blank=True)
    activa = models.BooleanField(default=True)

    class Meta:
        managed = False
        db_table = "categorias_comunicado"
        ordering = ["nombre"]

    def __str__(self):
        return self.nombre


class Comunicado(models.Model):
    class Estado(models.TextChoices):
        BORRADOR = "BORRADOR"
        PROGRAMADO = "PROGRAMADO"
        PUBLICADO = "PUBLICADO"
        ARCHIVADO = "ARCHIVADO"

    class Audiencia(models.TextChoices):
        TODOS = "TODOS"
        ROL = "ROL"
        USUARIOS = "USUARIOS"

    categoria = models.ForeignKey(
        CategoriaComunicado, null=True, blank=True, on_delete=models.DO_NOTHING, related_name="comunicados"
    )
    titulo = models.CharField(max_length=200)
    contenido = models.TextField()
    autor = models.ForeignKey(USUARIO, null=True, blank=True, on_delete=models.DO_NOTHING, related_name="+")
    estado = models.CharField(max_length=12, choices=Estado.choices, default=Estado.BORRADOR)
    audiencia = models.CharField(max_length=10, choices=Audiencia.choices, default=Audiencia.TODOS)
    rol_destino = models.ForeignKey(
        "usuarios.Rol", null=True, blank=True, on_delete=models.DO_NOTHING, related_name="+"
    )
    fecha_programada = models.DateTimeField(null=True, blank=True)
    fecha_publicacion = models.DateTimeField(null=True, blank=True)
    fecha_expiracion = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        managed = False
        db_table = "comunicados"

    def __str__(self):
        return self.titulo


class ComunicadoDestinatario(models.Model):
    pk = models.CompositePrimaryKey("comunicado_id", "usuario_id")
    comunicado = models.ForeignKey(Comunicado, on_delete=models.DO_NOTHING, related_name="destinatarios_rel")
    usuario = models.ForeignKey(USUARIO, on_delete=models.DO_NOTHING, related_name="+")

    class Meta:
        managed = False
        db_table = "comunicado_destinatarios"


class ComunicadoHistorial(models.Model):
    """Solo lectura: la llena el trigger fn_comunicados_historial."""

    comunicado = models.ForeignKey(Comunicado, on_delete=models.DO_NOTHING, related_name="historial")
    usuario = models.ForeignKey(USUARIO, null=True, on_delete=models.DO_NOTHING, related_name="+")
    estado_anterior = models.CharField(max_length=12, null=True)
    titulo_anterior = models.CharField(max_length=200, null=True)
    contenido_anterior = models.TextField(null=True)
    fecha = models.DateTimeField()

    class Meta:
        managed = False
        db_table = "comunicados_historial"
        ordering = ["-fecha", "-id"]


# ----------------------------------------------------------------------- notificaciones
class Notificacion(models.Model):
    class Tipo(models.TextChoices):
        COMUNICADO = "COMUNICADO"
        MANTENIMIENTO = "MANTENIMIENTO"
        BLOQUEO = "BLOQUEO"
        RESERVA = "RESERVA"
        PQR = "PQR"
        SISTEMA = "SISTEMA"

    class Canal(models.TextChoices):
        PUSH = "PUSH"
        EMAIL = "EMAIL"
        APP = "APP"

    usuario = models.ForeignKey(USUARIO, on_delete=models.DO_NOTHING, related_name="+")
    tipo = models.CharField(max_length=15, choices=Tipo.choices)
    titulo = models.CharField(max_length=200)
    mensaje = models.TextField()
    referencia_tipo = models.CharField(max_length=40, null=True, blank=True)
    referencia_id = models.BigIntegerField(null=True, blank=True)
    canal = models.CharField(max_length=6, choices=Canal.choices, default=Canal.APP)
    leida = models.BooleanField(default=False)
    leida_en = models.DateTimeField(null=True, blank=True)
    enviada_en = models.DateTimeField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        managed = False
        db_table = "notificaciones"
        ordering = ["-created_at", "-id"]
