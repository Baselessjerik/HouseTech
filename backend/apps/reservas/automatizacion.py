"""Proceso periódico de reservas: libera solicitudes sin confirmar, envía recordatorios y finaliza vencidas.

Se ejecuta con `python manage.py procesar_reservas` (el servicio `scheduler` de docker-compose lo repite
cada 5 minutos) o a demanda con `POST /api/v1/reservas/procesar/`. Es idempotente: ejecutarlo varias veces
no duplica avisos ni cambios.
"""
from __future__ import annotations

import datetime as dt

from django.db import transaction
from django.utils import timezone

from . import avisos
from .models import Reserva
from .services import (
    como_sistema,
    finalizar_vencidas,
    limite_confirmacion,
    liberar_no_confirmadas,
    obtener_regla,
    solicitudes_pendientes,
)

# Una solicitud recién creada ya avisó a la administración: no repetir el aviso antes de esto.
ESPERA_AVISO_PENDIENTE = dt.timedelta(hours=1)
MAX_HORAS_AVISO_PENDIENTE = 6


def enviar_recordatorios(ahora: dt.datetime | None = None) -> int:
    """Recordatorio al titular `horas_recordatorio` antes del inicio de una reserva CONFIRMADA (una sola vez).

    Si la reserva se confirmó cuando ya estaba dentro de esa ventana, el titular acaba de ser avisado:
    se marca como enviado sin repetirle el mensaje.
    """
    ahora = ahora or timezone.now()
    enviados = 0
    with transaction.atomic():
        candidatas = (
            Reserva.objects.filter(
                estado__codigo="CONFIRMADA", recordatorio_enviado_en__isnull=True, fecha_inicio__gt=ahora
            )
            .select_related("amenidad", "amenidad__reglas", "usuario", "estado")
            .select_for_update(of=("self",))
        )
        with como_sistema():
            for r in candidatas:
                ventana = dt.timedelta(hours=obtener_regla(r.amenidad).horas_recordatorio)
                if not ventana or r.fecha_inicio - ahora > ventana:
                    continue  # recordatorio desactivado o todavía falta
                confirmada_dentro_de_ventana = r.confirmada_en and r.confirmada_en > r.fecha_inicio - ventana
                if not confirmada_dentro_de_ventana:
                    avisos.recordatorio(r)
                    enviados += 1
                r.recordatorio_enviado_en = ahora
                r.save(update_fields=["recordatorio_enviado_en", "updated_at"])
    return enviados


def avisar_pendientes_por_vencer(ahora: dt.datetime | None = None) -> int:
    """Avisa a los administradores de las solicitudes que están por liberarse sin haber sido atendidas."""
    ahora = ahora or timezone.now()
    avisados = 0
    with transaction.atomic():
        with como_sistema():
            for r in solicitudes_pendientes().select_for_update(of=("self",)).filter(aviso_pendiente_en__isnull=True):
                vence = limite_confirmacion(r)
                restante = vence - ahora
                horas_plazo = obtener_regla(r.amenidad).horas_limite_confirmacion
                umbral = dt.timedelta(hours=min(MAX_HORAS_AVISO_PENDIENTE, max(horas_plazo / 2, 0.5)))
                if restante <= dt.timedelta(0) or restante > umbral or ahora - r.created_at < ESPERA_AVISO_PENDIENTE:
                    continue
                avisos.pendiente_por_vencer(r, vence)
                r.aviso_pendiente_en = ahora
                r.save(update_fields=["aviso_pendiente_en", "updated_at"])
                avisados += 1
    return avisados


def procesar_reservas(ahora: dt.datetime | None = None) -> dict:
    ahora = ahora or timezone.now()
    # Primero se avisa de lo que está por vencer y solo después se libera lo ya vencido.
    avisos_pendientes = avisar_pendientes_por_vencer(ahora)
    liberadas = liberar_no_confirmadas(ahora)
    recordatorios = enviar_recordatorios(ahora)
    with como_sistema():
        finalizadas = finalizar_vencidas(ahora)
    return {
        "liberadas": len(liberadas),
        "recordatorios": recordatorios,
        "avisos_pendientes": avisos_pendientes,
        "finalizadas": finalizadas,
    }
