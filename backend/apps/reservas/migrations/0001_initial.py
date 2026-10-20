"""Ajustes SQL del módulo (sql/reservas_v2.sql) + estado de los modelos (managed = False)."""
from pathlib import Path

import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models

SQL_PATH = Path(__file__).resolve().parent.parent / "sql" / "reservas_v2.sql"


def aplicar_sql(apps, schema_editor):
    with schema_editor.connection.cursor() as cursor:
        cursor.execute(SQL_PATH.read_text(encoding="utf-8"))  # sin parámetros: script de varias sentencias


def _fk(to, **kw):
    kw.setdefault("on_delete", django.db.models.deletion.DO_NOTHING)
    return models.ForeignKey(to=to, **kw)


def _user_fk(columna, **kw):
    return _fk(settings.AUTH_USER_MODEL, null=True, blank=True, related_name="+", db_column=columna, **kw)


class Migration(migrations.Migration):
    initial = True

    dependencies = [
        ("core", "0002_initial"),
        ("inmuebles", "0001_initial"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.RunPython(aplicar_sql, migrations.RunPython.noop),
        migrations.CreateModel(
            name="Amenidad",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("nombre", models.CharField(max_length=100)),
                ("descripcion", models.TextField(blank=True, null=True)),
                ("capacidad", models.IntegerField(blank=True, null=True)),
                ("condiciones_uso", models.TextField(blank=True, null=True)),
                ("activa", models.BooleanField(default=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("copropiedad", _fk("core.copropiedad", related_name="amenidades")),
            ],
            options={"verbose_name_plural": "amenidades", "db_table": "amenidades", "managed": False},
        ),
        migrations.CreateModel(
            name="AmenidadHorario",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("dia_semana", models.SmallIntegerField()),
                ("hora_apertura", models.TimeField()),
                ("hora_cierre", models.TimeField()),
                ("activo", models.BooleanField(default=True)),
                ("amenidad", _fk("reservas.amenidad", related_name="horarios")),
            ],
            options={"db_table": "amenidad_horarios", "managed": False},
        ),
        migrations.CreateModel(
            name="ReglaReserva",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("duracion_min_minutos", models.IntegerField(default=30)),
                ("duracion_max_minutos", models.IntegerField(default=240)),
                ("anticipacion_min_horas", models.IntegerField(default=1)),
                ("anticipacion_max_dias", models.IntegerField(default=30)),
                ("max_reservas_mes_inmueble", models.IntegerField(blank=True, null=True)),
                ("horas_limite_cancelacion", models.IntegerField(default=24)),
                ("requiere_confirmacion", models.BooleanField(default=True)),
                ("observaciones", models.TextField(blank=True, null=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                (
                    "amenidad",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.DO_NOTHING,
                        related_name="reglas",
                        to="reservas.amenidad",
                    ),
                ),
            ],
            options={"db_table": "reglas_reserva", "managed": False},
        ),
        migrations.CreateModel(
            name="Reserva",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("fecha_inicio", models.DateTimeField()),
                ("fecha_fin", models.DateTimeField()),
                ("num_personas", models.IntegerField(blank=True, null=True)),
                ("estado_proceso", models.CharField(default="RESERVA", max_length=20)),
                ("observaciones", models.TextField(blank=True, null=True)),
                ("confirmada_en", models.DateTimeField(blank=True, null=True)),
                ("cancelada_en", models.DateTimeField(blank=True, null=True)),
                ("motivo_cancelacion", models.TextField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("amenidad", _fk("reservas.amenidad", related_name="reservas")),
                ("usuario", _fk(settings.AUTH_USER_MODEL, related_name="reservas")),
                ("inmueble", _fk("inmuebles.inmueble", null=True, blank=True, related_name="reservas")),
                ("estado", _fk("core.estado", related_name="+")),
                ("confirmada_por", _user_fk("confirmada_por")),
                ("cancelada_por", _user_fk("cancelada_por")),
            ],
            options={"db_table": "reservas", "managed": False},
        ),
        migrations.CreateModel(
            name="ReservaHistorial",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("detalle", models.TextField(null=True)),
                ("fecha", models.DateTimeField()),
                ("reserva", _fk("reservas.reserva", related_name="historial")),
                ("estado_anterior", _fk("core.estado", null=True, related_name="+")),
                ("estado_nuevo", _fk("core.estado", related_name="+")),
                ("usuario", _fk(settings.AUTH_USER_MODEL, null=True, related_name="+")),
            ],
            options={"db_table": "reservas_historial", "managed": False, "ordering": ["fecha", "id"]},
        ),
        migrations.CreateModel(
            name="BloqueoAmenidad",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("fecha_inicio", models.DateTimeField()),
                ("fecha_fin", models.DateTimeField()),
                ("motivo", models.TextField()),
                ("cancelado", models.BooleanField(default=False)),
                ("cancelado_en", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                ("updated_at", models.DateTimeField(auto_now=True)),
                ("amenidad", _fk("reservas.amenidad", related_name="bloqueos")),
                ("creado_por", _user_fk("creado_por")),
            ],
            options={"db_table": "bloqueos_amenidad", "managed": False},
        ),
    ]
