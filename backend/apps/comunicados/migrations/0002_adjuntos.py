"""Adjuntos de comunicados: crea la tabla comunicado_adjuntos (el módulo 1 no la trae).

El contenido se guarda en la propia BD (BYTEA) para no depender de carpetas de archivos ni de
configuración compartida (MEDIA_ROOT). Es reversible: el paso inverso borra la tabla.
"""
from django.db import migrations, models

CREAR = """
CREATE TABLE comunicado_adjuntos (
    id              BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    comunicado_id   BIGINT NOT NULL REFERENCES comunicados(id) ON DELETE CASCADE,
    nombre_original VARCHAR(255) NOT NULL,
    tipo_contenido  VARCHAR(120) NOT NULL DEFAULT 'application/octet-stream',
    tamano_bytes    INTEGER NOT NULL CHECK (tamano_bytes > 0),
    contenido       BYTEA NOT NULL,
    subido_por      BIGINT REFERENCES usuarios(id) ON DELETE SET NULL,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_comunicado_adjuntos_comunicado ON comunicado_adjuntos (comunicado_id);
"""

BORRAR = "DROP TABLE IF EXISTS comunicado_adjuntos;"


class Migration(migrations.Migration):
    dependencies = [
        ("comunicados", "0001_initial"),
    ]

    operations = [
        migrations.RunSQL(CREAR, reverse_sql=BORRAR),
        migrations.CreateModel(
            name="ComunicadoAdjunto",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("nombre_original", models.CharField(max_length=255)),
                ("tipo_contenido", models.CharField(default="application/octet-stream", max_length=120)),
                ("tamano_bytes", models.IntegerField()),
                ("contenido", models.BinaryField()),
                ("created_at", models.DateTimeField(auto_now_add=True)),
            ],
            options={"db_table": "comunicado_adjuntos", "managed": False, "ordering": ["id"]},
        ),
    ]
