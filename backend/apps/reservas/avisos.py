"""Mensajes de notificación del ciclo de vida de una reserva (solicitud, confirmación, recordatorios...)."""
from __future__ import annotations

from django.utils import timezone

from apps.core.notificaciones import notificar
from apps.usuarios.models import Usuario

_DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]


def cuando(reserva) -> str:
    ini, fin = timezone.localtime(reserva.fecha_inicio), timezone.localtime(reserva.fecha_fin)
    return f"{_DIAS[ini.weekday()]} {ini:%d/%m/%Y} de {ini:%H:%M} a {fin:%H:%M}"


def _detalle(reserva) -> str:
    return f"{reserva.amenidad.nombre}, {cuando(reserva)}"


def gestores():
    """Usuarios activos que administran amenidades (reciben las solicitudes pendientes)."""
    return Usuario.objects.filter(
        activo=True,
        usuario_roles__rol__activo=True,
        usuario_roles__rol__rol_permisos__permiso__codigo="amenidades.gestionar",
    ).distinct()


def _a_titular(reserva, titulo, mensaje, *, correo=True):
    notificar(reserva.usuario, tipo="RESERVA", titulo=titulo, mensaje=mensaje,
              referencia_tipo="reserva", referencia_id=reserva.pk, correo=correo)


def solicitud_creada(reserva):
    if reserva.estado.codigo == "CONFIRMADA":
        _a_titular(reserva, "Reserva confirmada", f"Tu reserva quedó confirmada: {_detalle(reserva)}.")
        return
    _a_titular(reserva, "Solicitud de reserva recibida",
               f"Recibimos tu solicitud: {_detalle(reserva)}. La administración la confirmará o rechazará pronto.")
    for admin in gestores():
        notificar(admin, tipo="RESERVA", titulo="Nueva solicitud de reserva",
                  mensaje=f"{reserva.usuario.nombre_completo} solicitó {_detalle(reserva)}. Requiere confirmación.",
                  referencia_tipo="reserva", referencia_id=reserva.pk, correo=False)


def confirmada(reserva):
    _a_titular(reserva, "Reserva confirmada", f"Tu reserva fue confirmada: {_detalle(reserva)}.")


def rechazada(reserva):
    motivo = f" Motivo: {reserva.motivo_cancelacion}." if reserva.motivo_cancelacion else ""
    _a_titular(reserva, "Reserva rechazada", f"Tu solicitud fue rechazada: {_detalle(reserva)}.{motivo}")


def cancelada_por_otro(reserva):
    """Cancelación hecha por la administración o por un bloqueo (el titular no la hizo)."""
    motivo = f" Motivo: {reserva.motivo_cancelacion}." if reserva.motivo_cancelacion else ""
    _a_titular(reserva, "Reserva cancelada", f"Se canceló tu reserva: {_detalle(reserva)}.{motivo}")


def expirada(reserva):
    _a_titular(reserva, "Solicitud liberada",
               f"Tu solicitud no fue confirmada a tiempo y el horario quedó libre: {_detalle(reserva)}. "
               "Puedes volver a solicitarlo.")


def recordatorio(reserva):
    _a_titular(reserva, "Recordatorio de reserva", f"Te recordamos tu reserva: {_detalle(reserva)}.")


def pendiente_por_vencer(reserva, vence):
    limite = timezone.localtime(vence)
    for admin in gestores():
        notificar(admin, tipo="RESERVA", titulo="Solicitud por vencer",
                  mensaje=f"La solicitud de {reserva.usuario.nombre_completo} ({_detalle(reserva)}) se liberará "
                          f"automáticamente el {limite:%d/%m/%Y a las %H:%M} si no se confirma.",
                  referencia_tipo="reserva", referencia_id=reserva.pk, correo=False)
