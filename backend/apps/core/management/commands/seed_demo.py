import datetime as dt

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from apps.core.models import Copropiedad
from apps.reservas.models import Amenidad, AmenidadHorario, ReglaReserva
from apps.usuarios.models import Rol, Usuario, UsuarioRol

# username, email, nombres, apellidos, documento, rol
USUARIOS_DEMO = [
    ("admin", "admin@housetech.local", "Administrador", "Demo", "1000000001", "ADMIN"),
    ("residente", "residente@housetech.local", "Rosa", "Residente", "1000000002", "RESIDENTE"),
    ("responsable", "responsable@housetech.local", "Pedro", "Responsable", "1000000003", "RESPONSABLE_PQR"),
]

# nombre, capacidad, apertura, cierre, confirmación, máx. reservas/mes por inmueble, horas límite de cancelación
AMENIDADES_DEMO = [
    ("Salón social", 40, "08:00", "22:00", True, 2, 48),
    ("Piscina", 25, "09:00", "20:00", False, None, 2),
    ("Gimnasio", 12, "05:00", "21:00", False, None, 1),
    ("Cancha múltiple", 20, "06:00", "21:00", False, 4, 12),
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

            self._amenidades(copropiedad)

        self.stdout.write(self.style.SUCCESS(f"Listo. Clave demo: {opciones['password']}"))

    def _amenidades(self, copropiedad):
        for nombre, capacidad, apertura, cierre, confirmar, max_mes, horas_cancelar in AMENIDADES_DEMO:
            amenidad, creada = Amenidad.objects.get_or_create(
                copropiedad=copropiedad, nombre=nombre, defaults={"capacidad": capacidad}
            )
            ReglaReserva.objects.get_or_create(
                amenidad=amenidad,
                defaults={
                    "requiere_confirmacion": confirmar,
                    "max_reservas_mes_inmueble": max_mes,
                    "horas_limite_cancelacion": horas_cancelar,
                },
            )
            if not AmenidadHorario.objects.filter(amenidad=amenidad).exists():
                AmenidadHorario.objects.bulk_create(
                    [
                        AmenidadHorario(
                            amenidad=amenidad,
                            dia_semana=dia,
                            hora_apertura=dt.time.fromisoformat(apertura),
                            hora_cierre=dt.time.fromisoformat(cierre),
                        )
                        for dia in range(1, 8)
                    ]
                )
            self.stdout.write(f"  amenidad {nombre:<16} {'creada' if creada else 'ya existía'}")
