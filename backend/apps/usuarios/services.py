"""Lógica de negocio del módulo de usuarios (fuera de las vistas)."""
import hashlib
import hmac
import logging
import secrets
from datetime import timedelta

from django.conf import settings
from django.core.mail import EmailMultiAlternatives
from django.utils.html import escape
from django.utils import timezone
from rest_framework.exceptions import ValidationError

from .models import RecuperacionPassword, Rol, RolPermiso, UsuarioRol

logger = logging.getLogger(__name__)

VIGENCIA_CODIGO = timedelta(minutes=15)


# --- recuperación de contraseña (RF4) ----------------------------------------
def _hash_codigo(usuario_id, codigo: str) -> str:
    """HMAC con SECRET_KEY y el id del usuario: el código nunca se guarda en claro y
    dos usuarios con el mismo código no chocan con el UNIQUE de token_hash."""
    mensaje = f"{usuario_id}:{codigo}".encode()
    return hmac.new(settings.SECRET_KEY.encode(), mensaje, hashlib.sha256).hexdigest()


def emitir_codigo_recuperacion(usuario) -> None:
    ahora = timezone.now()
    # Un código nuevo invalida los anteriores. Se borran (no se marcan como usados) para que,
    # si el nuevo código coincidiera con uno viejo, no choque con el UNIQUE de token_hash.
    RecuperacionPassword.objects.filter(usuario=usuario).delete()

    codigo = f"{secrets.randbelow(10**6):06d}"
    RecuperacionPassword.objects.create(
        usuario=usuario,
        token_hash=_hash_codigo(usuario.pk, codigo),
        expira_en=ahora + VIGENCIA_CODIGO,
    )
    try:
        asunto = "HouseTech: verifica tu identidad para recuperar tu cuenta"
        mensaje = (
            f"Hola {usuario.nombres},\n\n"
            "Recibimos una solicitud para recuperar el acceso a tu cuenta de HouseTech.\n\n"
            f"Tu código de verificación es: {codigo}\n\n"
            f"Este código vence en {int(VIGENCIA_CODIGO.total_seconds() // 60)} minutos. "
            "Si no solicitaste este cambio, puedes ignorar este mensaje.\n\n"
            "Equipo HouseTech"
        )
        mensaje_html = (
            "<div style=\"font-family:Arial,sans-serif;color:#263238;line-height:1.5\">"
            f"<h2 style=\"color:#2446b8\">Recupera tu acceso a HouseTech</h2>"
            f"<p>Hola {escape(usuario.nombres)},</p>"
            "<p>Recibimos una solicitud para recuperar el acceso a tu cuenta.</p>"
            "<p>Usa este código de verificación:</p>"
            "<p style=\"font-size:28px;letter-spacing:6px;font-weight:700;"
            "color:#2446b8;margin:20px 0\">"
            f"{codigo}</p>"
            f"<p>El código vence en {int(VIGENCIA_CODIGO.total_seconds() // 60)} minutos.</p>"
            "<p>Si no solicitaste este cambio, puedes ignorar este mensaje.</p>"
            "<p>Equipo HouseTech</p>"
            "</div>"
        )
        correo = EmailMultiAlternatives(
            subject=asunto,
            body=mensaje,
            from_email=None,
            to=[usuario.email],
        )
        correo.attach_alternative(mensaje_html, "text/html")
        correo.send()
    except Exception:  # un fallo de SMTP no debe revelar si la cuenta existe
        logger.exception("No se pudo enviar el correo de recuperación (usuario %s)", usuario.pk)


def obtener_codigo_vigente(usuario, codigo: str):
    return RecuperacionPassword.objects.filter(
        usuario=usuario,
        token_hash=_hash_codigo(usuario.pk, codigo.strip()),
        usado_en__isnull=True,
        expira_en__gt=timezone.now(),
    ).first()


# --- roles y permisos (RF9) ----------------------------------------------------
def asignar_roles(usuario, roles, por) -> None:
    """Deja al usuario exactamente con `roles` (lista de Rol). `por` = quien lo hace."""
    actuales = set(UsuarioRol.objects.filter(usuario=usuario).values_list("rol_id", flat=True))
    nuevos = {r.pk for r in roles}

    admin_id = Rol.objects.get(codigo="ADMIN").pk
    if usuario.pk == por.pk and admin_id in actuales and admin_id not in nuevos:
        raise ValidationError({"roles": "No puedes quitarte a ti mismo el rol ADMIN."})

    quitar = actuales - nuevos
    if quitar:
        UsuarioRol.objects.filter(usuario=usuario, rol_id__in=quitar).delete()
    for rol in roles:
        if rol.pk not in actuales:
            UsuarioRol.objects.create(usuario=usuario, rol=rol, asignado_por=por)
    usuario.__dict__.pop("_permisos_cache", None)


def asignar_permisos(rol, permisos) -> None:
    """Deja al rol exactamente con `permisos` (lista de Permiso)."""
    actuales = set(RolPermiso.objects.filter(rol=rol).values_list("permiso_id", flat=True))
    nuevos = {p.pk for p in permisos}

    quitar = actuales - nuevos
    if quitar:
        RolPermiso.objects.filter(rol=rol, permiso_id__in=quitar).delete()
    for permiso in permisos:
        if permiso.pk not in actuales:
            RolPermiso.objects.create(rol=rol, permiso=permiso)
