from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.models import Copropiedad
from apps.usuarios.models import Rol, Usuario, UsuarioRol

# username, email, nombres, apellidos, documento, rol
USUARIOS_DEMO = [
    ("admin", "admin@housetech.local", "Administrador", "Demo", "1000000001", "ADMIN"),
    ("residente", "residente@housetech.local", "Rosa", "Residente", "1000000002", "RESIDENTE"),
    ("responsable", "responsable@housetech.local", "Pedro", "Responsable", "1000000003", "RESPONSABLE_PQR"),
]


class Command(BaseCommand):
    help = "Crea la copropiedad y usuarios demo (solo desarrollo). Es idempotente."

    def add_arguments(self, parser):
        parser.add_argument("--password", default="HouseTech2026!", help="Clave de los usuarios demo")

    def handle(self, *args, **opciones):
        if not settings.DEBUG:
            raise CommandError("seed_demo solo se permite con DEBUG=True.")

        with transaction.atomic():
            copropiedad, _ = Copropiedad.objects.get_or_create(
                nit="900123456-7",
                defaults={"nombre": "Conjunto Residencial Demo", "direccion": "Calle 1 # 2-3"},
            )
            self.stdout.write(f"Copropiedad: {copropiedad.nombre}")

            for username, email, nombres, apellidos, documento, codigo_rol in USUARIOS_DEMO:
                usuario = Usuario.objects.filter(username__iexact=username).first()
                if usuario is None:
                    usuario = Usuario.objects.create_user(
                        username=username,
                        email=email,
                        password=opciones["password"],
                        nombres=nombres,
                        apellidos=apellidos,
                        numero_documento=documento,
                    )
                    estado = "creado"
                else:
                    estado = "ya existía"
                UsuarioRol.objects.get_or_create(usuario=usuario, rol=Rol.objects.get(codigo=codigo_rol))
                self.stdout.write(f"  {username:<12} {codigo_rol:<16} {estado}")

        self.stdout.write(self.style.SUCCESS(f"Listo. Clave demo: {opciones['password']}"))
