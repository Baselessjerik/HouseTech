import os

from .base import *  # noqa: F401,F403
from .base import DATABASES, MIDDLEWARE, env

# Sirve estáticos (Swagger /api/docs/) con DEBUG=False sin Nginx dedicado
MIDDLEWARE = [
    MIDDLEWARE[0],
    "whitenoise.middleware.WhiteNoiseMiddleware",
    *MIDDLEWARE[1:],
]

DEBUG = False
SECRET_KEY = env("SECRET_KEY")  # obligatoria: si falta, falla al arrancar

ALLOWED_HOSTS = env.list("ALLOWED_HOSTS", default=[])
_render_host = os.environ.get("RENDER_EXTERNAL_HOSTNAME", "").strip()
if _render_host and _render_host not in ALLOWED_HOSTS:
    ALLOWED_HOSTS.append(_render_host)

CORS_ALLOWED_ORIGINS = env.list("CORS_ALLOWED_ORIGINS", default=[])
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])

# Proxy inverso HTTPS (Render / Railway / Fly.io): evita bucles 301 y genera URLs https://
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
USE_X_FORWARDED_HOST = True
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=True)
SESSION_COOKIE_SECURE = True
CSRF_COOKIE_SECURE = True

# Reutilización de conexiones en PostgreSQL cloud (Neon / Supabase / Render)
DATABASES["default"]["CONN_MAX_AGE"] = env.int("DB_CONN_MAX_AGE", default=60)
DATABASES["default"]["CONN_HEALTH_CHECKS"] = True
