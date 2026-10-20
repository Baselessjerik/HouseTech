from django.core.management.base import BaseCommand

from apps.comunicados.services import publicar_programados_vencidos


class Command(BaseCommand):
    help = (
        "Publica los comunicados PROGRAMADOS cuya fecha ya llegó y notifica a su audiencia (RF13/RF16). "
        "Es idempotente: agéndalo cada minuto, p. ej. con cron:  * * * * *  python manage.py publicar_comunicados_programados"
    )

    def handle(self, *args, **opciones):
        publicados = publicar_programados_vencidos()
        self.stdout.write(self.style.SUCCESS(f"Comunicados publicados: {publicados}"))
