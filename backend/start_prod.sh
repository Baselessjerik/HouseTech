#!/usr/bin/env sh
set -eu

python manage.py migrate --noinput
python manage.py collectstatic --noinput

# En despliegues académicos (ALLOW_DEMO_SEED=True) carga usuarios y datos demo de forma idempotente
case "$(printf '%s' "${ALLOW_DEMO_SEED:-false}" | tr '[:upper:]' '[:lower:]')" in
  1|true|yes|si)
    python manage.py seed_demo
    python manage.py seed_modulo2
    ;;
esac

exec gunicorn config.wsgi:application \
  --bind "0.0.0.0:${PORT:-8000}" \
  --workers "${GUNICORN_WORKERS:-2}" \
  --timeout 120

