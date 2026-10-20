"""Estado de los modelos managed = False del Módulo 2 (no crea tablas: las crea schema.sql)."""
from django.db import migrations, models


def _id():
    return ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID"))


def _opts(tabla, **extra):
    return {"db_table": tabla, "managed": False, **extra}


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("core", "0002_initial"),
        ("usuarios", "0001_initial"),
    ]

    operations = [
        migrations.CreateModel(
            name="AmenidadRef",
            fields=[
                _id(),
                ("nombre", models.CharField(max_length=100)),
                ("descripcion", models.TextField(blank=True, null=True)),
                ("capacidad", models.IntegerField(blank=True, null=True)),
                ("condiciones_uso", models.TextField(blank=True, null=True)),
                ("activa", models.BooleanField(default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options=_opts("amenidades"),
        ),
        migrations.CreateModel(
            name="ReservaRef",
            fields=[
                _id(),
                ("fecha_inicio", models.DateTimeField()),
                ("fecha_fin", models.DateTimeField()),
                ("num_personas", models.IntegerField(blank=True, null=True)),
            ],
            options=_opts("reservas"),
        ),
        migrations.CreateModel(
            name="Mantenimiento",
            fields=[
                _id(),
                ("titulo", models.CharField(max_length=150)),
                ("descripcion", models.TextField(blank=True, null=True)),
                ("fecha_inicio", models.DateTimeField()),
                ("fecha_fin", models.DateTimeField()),
                ("responsable", models.CharField(blank=True, max_length=150, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options=_opts("mantenimientos"),
        ),
        migrations.CreateModel(
            name="Bloqueo",
            fields=[
                _id(),
                ("fecha_inicio", models.DateTimeField()),
                ("fecha_fin", models.DateTimeField()),
                ("motivo", models.TextField()),
                ("cancelado", models.BooleanField(default=False)),
                ("cancelado_en", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options=_opts("bloqueos_amenidad"),
        ),
        migrations.CreateModel(
            name="CategoriaComunicado",
            fields=[
                _id(),
                ("nombre", models.CharField(max_length=80, unique=True)),
                ("descripcion", models.CharField(blank=True, max_length=200, null=True)),
                ("color", models.CharField(blank=True, max_length=9, null=True)),
                ("activa", models.BooleanField(default=True)),
            ],
            options=_opts("categorias_comunicado", ordering=["nombre"]),
        ),
        migrations.CreateModel(
            name="Comunicado",
            fields=[
                _id(),
                ("titulo", models.CharField(max_length=200)),
                ("contenido", models.TextField()),
                ("estado", models.CharField(
                    choices=[("BORRADOR", "Borrador"), ("PROGRAMADO", "Programado"),
                             ("PUBLICADO", "Publicado"), ("ARCHIVADO", "Archivado")],
                    default="BORRADOR", max_length=12)),
                ("audiencia", models.CharField(
                    choices=[("TODOS", "Todos"), ("ROL", "Rol"), ("USUARIOS", "Usuarios")],
                    default="TODOS", max_length=10)),
                ("fecha_programada", models.DateTimeField(blank=True, null=True)),
                ("fecha_publicacion", models.DateTimeField(blank=True, null=True)),
                ("fecha_expiracion", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
            ],
            options=_opts("comunicados"),
        ),
        migrations.CreateModel(
            name="ComunicadoDestinatario",
            fields=[
                ("pk", models.CompositePrimaryKey("comunicado_id", "usuario_id", blank=True, editable=False,
                                                  primary_key=True, serialize=False)),
            ],
            options=_opts("comunicado_destinatarios"),
        ),
        migrations.CreateModel(
            name="ComunicadoHistorial",
            fields=[
                _id(),
                ("estado_anterior", models.CharField(max_length=12, null=True)),
                ("titulo_anterior", models.CharField(max_length=200, null=True)),
                ("contenido_anterior", models.TextField(null=True)),
                ("fecha", models.DateTimeField()),
            ],
            options=_opts("comunicados_historial", ordering=["-fecha", "-id"]),
        ),
        migrations.CreateModel(
            name="Notificacion",
            fields=[
                _id(),
                ("tipo", models.CharField(
                    choices=[("COMUNICADO", "Comunicado"), ("MANTENIMIENTO", "Mantenimiento"),
                             ("BLOQUEO", "Bloqueo"), ("RESERVA", "Reserva"), ("PQR", "Pqr"),
                             ("SISTEMA", "Sistema")], max_length=15)),
                ("titulo", models.CharField(max_length=200)),
                ("mensaje", models.TextField()),
                ("referencia_tipo", models.CharField(blank=True, max_length=40, null=True)),
                ("referencia_id", models.BigIntegerField(blank=True, null=True)),
                ("canal", models.CharField(
                    choices=[("PUSH", "Push"), ("EMAIL", "Email"), ("APP", "App")],
                    default="APP", max_length=6)),
                ("leida", models.BooleanField(default=False)),
                ("leida_en", models.DateTimeField(blank=True, null=True)),
                ("enviada_en", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options=_opts("notificaciones", ordering=["-created_at", "-id"]),
        ),
    ]
