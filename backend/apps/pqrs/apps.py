from django.apps import AppConfig


class PqrsConfig(AppConfig):
    """Configuración de la aplicación PQR para Django."""

    # Usa claves BigAutoField en los modelos que no declaran su clave primaria.
    default_auto_field = "django.db.models.BigAutoField"
    # Ruta Python que identifica esta aplicación dentro del proyecto.
    name = "apps.pqrs"
    # Nombre legible que Django muestra en interfaces administrativas.
    verbose_name = "Peticiones, Quejas y Reclamos"