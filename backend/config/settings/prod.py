from .base import *  # noqa: F401,F403
from .base import env

DEBUG = False
SECRET_KEY = env("SECRET_KEY")  # obligatoria: si falta, falla al arrancar
ALLOWED_HOSTS = env.list("ALLOWED_HOSTS")
CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])

SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True
