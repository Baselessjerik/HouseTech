"""Crea notificaciones en la app (tabla `notificaciones`) y, opcionalmente, envía un correo."""
import logging

from django.core.mail import send_mail
from django.db import transaction
from django.utils import timezone

from .models import Notificacion

logger = logging.getLogger(__name__)


def _enviar_correo(destino: str, asunto: str, mensaje: str) -> None:
    try:
        send_mail(asunto, mensaje, None, [destino], fail_silently=False)
    except Exception:  # un fallo de SMTP nunca debe romper el flujo de negocio
        logger.exception("No se pudo enviar el correo '%s' a %s", asunto, destino)


def notificar(usuario, *, tipo, titulo, mensaje, referencia_tipo=None, referencia_id=None, correo=True) -> Notificacion:
    """Guarda la notificación y programa el correo para cuando la transacción se confirme
    (así no se avisa de algo que luego se revierte)."""
    notificacion = Notificacion.objects.create(
        usuario=usuario, tipo=tipo, titulo=titulo, mensaje=mensaje,
        referencia_tipo=referencia_tipo, referencia_id=referencia_id,
        canal="APP", enviada_en=timezone.now(),
    )
    if correo and usuario.email:
        transaction.on_commit(lambda: _enviar_correo(usuario.email, titulo, mensaje))
    return notificacion
