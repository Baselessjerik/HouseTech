"""Liberación automática y recordatorios: SQL (sql/reservas_v3.sql) + estado de los modelos."""
from pathlib import Path

from django.db import migrations, models

SQL_PATH = Path(__file__).resolve().parent.parent / "sql" / "reservas_v3.sql"


def aplicar_sql(apps, schema_editor):
    with schema_editor.connection.cursor() as cursor:
        cursor.execute(SQL_PATH.read_text(encoding="utf-8"))


class Migration(migrations.Migration):
    dependencies = [("reservas", "0001_initial"), ("core", "0003_notificacion")]

    operations = [
        migrations.RunPython(aplicar_sql, migrations.RunPython.noop),
        # Modelos managed = False: estas operaciones solo actualizan el estado de Django.
        migrations.AddField("reglareserva", "horas_limite_confirmacion", models.IntegerField(default=24)),
        migrations.AddField("reglareserva", "horas_recordatorio", models.IntegerField(default=24)),
        migrations.AddField("reserva", "recordatorio_enviado_en", models.DateTimeField(blank=True, null=True)),
        migrations.AddField("reserva", "aviso_pendiente_en", models.DateTimeField(blank=True, null=True)),
    ]
