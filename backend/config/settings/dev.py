from .base import *  # noqa: F401,F403
from .base import env

DEBUG = True
SECRET_KEY = env("SECRET_KEY", default="dev-solo-local-no-usar-en-produccion")
# 10.0.2.2 = el host visto desde el emulador de Android
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=["localhost", "127.0.0.1", "10.0.2.2"])

CORS_ALLOW_ALL_ORIGINS = True  # Flutter web en desarrollo
EMAIL_BACKEND = "django.core.mail.backends.console.EmailBackend"  # los correos salen por consola
