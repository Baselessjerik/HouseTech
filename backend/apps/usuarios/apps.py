from django.apps import AppConfig


class UsuariosConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "apps.usuarios"
    verbose_name = "Usuarios, roles y permisos"

    def ready(self):
        from . import schema  # noqa: F401  (registra el esquema de seguridad en Swagger)
