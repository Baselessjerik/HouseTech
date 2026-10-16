"""Crea TODO el esquema (los 4 módulos) ejecutando sql/schema.sql.

El SQL es la fuente de verdad: los modelos son managed = False. Se le quitan las
líneas BEGIN;/COMMIT; porque Django ya corre cada migración dentro de una
transacción. El archivo original sigue funcionando con `psql -f`.
"""
import re
from pathlib import Path

from django.db import migrations

SQL_PATH = Path(__file__).resolve().parent.parent / "sql" / "schema.sql"
_CONTROL_TX = re.compile(r"^\s*(?:BEGIN|COMMIT);\s*$", re.IGNORECASE | re.MULTILINE)


def crear_esquema(apps, schema_editor):
    sql = _CONTROL_TX.sub("", SQL_PATH.read_text(encoding="utf-8"))
    with schema_editor.connection.cursor() as cursor:
        cursor.execute(sql)  # sin parámetros: se envía como script de varias sentencias


class Migration(migrations.Migration):
    initial = True
    dependencies = []
    operations = [migrations.RunPython(crear_esquema, migrations.RunPython.noop)]
