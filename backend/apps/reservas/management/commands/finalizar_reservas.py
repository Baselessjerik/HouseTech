from django.core.management.base import BaseCommand

from apps.reservas.services import finalizar_vencidas


class Command(BaseCommand):
    help = "Pasa a FINALIZADA las reservas confirmadas cuyo horario ya terminó (ejecutar periódicamente, p. ej. cada hora)."

    def handle(self, *args, **opciones):
        total = finalizar_vencidas()
        self.stdout.write(self.style.SUCCESS(f"{total} reserva(s) finalizada(s)."))
