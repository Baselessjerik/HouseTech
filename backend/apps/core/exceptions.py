"""Traduce errores de integridad de PostgreSQL (índices únicos, CHECK, triggers) a HTTP."""
from django.db import IntegrityError
from rest_framework import status
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler
from rest_framework.views import set_rollback

_MENSAJES = {
    "23505": "Ya existe un registro con esos datos.",
    "23503": "El registro referencia datos que no existen o que están en uso.",
    "23514": "Los datos no cumplen las restricciones definidas.",
}


def exception_handler(exc, context):
    response = drf_exception_handler(exc, context)
    if response is not None or not isinstance(exc, IntegrityError):
        return response

    causa = exc.__cause__  # excepción original de psycopg
    sqlstate = getattr(causa, "sqlstate", None)
    if sqlstate == "23P01":  # lanzado por los triggers (solapamiento de reservas, etc.)
        detalle = getattr(getattr(causa, "diag", None), "message_primary", None) or "Conflicto."
        codigo_http = status.HTTP_409_CONFLICT
    else:
        detalle = _MENSAJES.get(sqlstate, "Violación de integridad de datos.")
        codigo_http = status.HTTP_409_CONFLICT if sqlstate == "23505" else status.HTTP_400_BAD_REQUEST

    set_rollback()  # la transacción de la petición quedó abortada
    return Response({"detail": detalle}, status=codigo_http)
