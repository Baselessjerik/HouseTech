import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):
    dependencies = [
        ("core", "0002_initial"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="Notificacion",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("tipo", models.CharField(max_length=15)),
                ("titulo", models.CharField(max_length=200)),
                ("mensaje", models.TextField()),
                ("referencia_tipo", models.CharField(blank=True, max_length=40, null=True)),
                ("referencia_id", models.BigIntegerField(blank=True, null=True)),
                ("canal", models.CharField(default="APP", max_length=6)),
                ("leida", models.BooleanField(default=False)),
                ("leida_en", models.DateTimeField(blank=True, null=True)),
                ("enviada_en", models.DateTimeField(blank=True, null=True)),
                ("created_at", models.DateTimeField(auto_now_add=True)),
                (
                    "usuario",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.DO_NOTHING,
                        related_name="notificaciones",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
            ],
            options={"db_table": "notificaciones", "ordering": ["-created_at", "-id"], "managed": False},
        ),
    ]

