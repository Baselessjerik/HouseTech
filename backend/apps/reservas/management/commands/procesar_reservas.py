from django.core.management.base import BaseCommand

from apps.reservas.automatizacion import procesar_reservas


class Command(BaseCommand):
    help = (
        "Libera las solicitudes de reserva no confirmadas a tiempo, envía recordatorios y finaliza las reservas "
        "vencidas. Ejecutar periódicamente (p. ej. cada 5 minutos)."
    )

    def handle(self, *args, **opciones):
        r = procesar_reservas()
        self.stdout.write(self.style.SUCCESS(
            f"liberadas={r['liberadas']} recordatorios={r['recordatorios']} "
            f"avisos_pendientes={r['avisos_pendientes']} finalizadas={r['finalizadas']}"
        ))
