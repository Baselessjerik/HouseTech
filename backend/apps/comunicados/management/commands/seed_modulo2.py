from datetime import timedelta

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from apps.comunicados import services
from apps.comunicados.models import AmenidadRef, Bloqueo, CategoriaComunicado, Comunicado, Mantenimiento
from apps.core.db import set_audit_user
from apps.core.models import Copropiedad, Estado
from apps.usuarios.models import Usuario

AMENIDADES = [
    ("Piscina", "Piscina para adultos y niños", 30),
    ("Salón social", "Salón para eventos y reuniones", 60),
    ("Gimnasio", "Gimnasio con equipos de cardio y pesas", 15),
    ("Cancha múltiple", "Cancha de microfútbol y baloncesto", 20),
]


class Command(BaseCommand):
    help = (
        "Datos demo del Módulo 2 (amenidades, mantenimientos, bloqueos y comunicados). Solo desarrollo, "
        "idempotente. Requiere haber ejecutado antes `seed_demo`."
    )

    def handle(self, *args, **opciones):
        if not settings.DEBUG:
            raise CommandError("seed_modulo2 solo se permite con DEBUG=True.")
        admin = Usuario.objects.filter(username__iexact="admin").first()
        copropiedad = Copropiedad.objects.order_by("id").first()
        if admin is None or copropiedad is None:
            raise CommandError("Ejecuta primero `python manage.py seed_demo` (crea la copropiedad y el usuario admin).")

        ahora = timezone.now()
        with transaction.atomic():
            set_audit_user(admin.pk)
            amenidades = {}
            for nombre, descripcion, capacidad in AMENIDADES:
                a, _ = AmenidadRef.objects.get_or_create(
                    copropiedad=copropiedad, nombre=nombre,
                    defaults={"descripcion": descripcion, "capacidad": capacidad},
                )
                amenidades[nombre] = a
            self.stdout.write(f"Amenidades: {len(amenidades)}")

            if not Mantenimiento.objects.filter(titulo="Mantenimiento de la piscina").exists():
                m = Mantenimiento.objects.create(
                    amenidad=amenidades["Piscina"], titulo="Mantenimiento de la piscina",
                    descripcion="Limpieza profunda y cambio de filtros.",
                    fecha_inicio=ahora + timedelta(days=3), fecha_fin=ahora + timedelta(days=5),
                    estado=Estado.objects.get(proceso="MANTENIMIENTO", codigo="PROGRAMADO"),
                    responsable="Aquaservicios S.A.S.", creado_por=admin,
                )
                Bloqueo.objects.create(
                    amenidad=amenidades["Piscina"], mantenimiento=m, fecha_inicio=m.fecha_inicio,
                    fecha_fin=m.fecha_fin, motivo=f"Mantenimiento: {m.titulo}", creado_por=admin,
                )
            if not Bloqueo.objects.filter(motivo="Evento privado de la administración").exists():
                Bloqueo.objects.create(
                    amenidad=amenidades["Salón social"], fecha_inicio=ahora + timedelta(days=7),
                    fecha_fin=ahora + timedelta(days=7, hours=6),
                    motivo="Evento privado de la administración", creado_por=admin,
                )

            categorias = {c.nombre: c for c in CategoriaComunicado.objects.all()}
            demo = [
                ("Corte de agua programado", "Mantenimiento",
                 "El jueves se suspenderá el servicio de agua de 8:00 a. m. a 2:00 p. m. por trabajos en el tanque.",
                 "publicar"),
                ("Asamblea ordinaria de copropietarios", "Asambleas",
                 "Se convoca a la asamblea ordinaria en el salón social. Tu asistencia es muy importante.",
                 "publicar"),
                ("Normas de uso del gimnasio", "General",
                 "Recordamos el uso de toalla, el horario de 5:00 a. m. a 10:00 p. m. y el límite de 15 personas.",
                 "borrador"),
                ("Jornada de fumigación", "Seguridad",
                 "La fumigación de zonas comunes se realizará el próximo sábado. Mantén cerradas las ventanas.",
                 "programar"),
            ]
            for titulo, categoria, contenido, accion in demo:
                if Comunicado.objects.filter(titulo=titulo).exists():
                    continue
                c = services.crear_comunicado(
                    {"titulo": titulo, "contenido": contenido, "categoria": categorias.get(categoria),
                     "audiencia": "TODOS"},
                    admin,
                )
                if accion == "publicar":
                    services.publicar_comunicado(c, admin)
                elif accion == "programar":
                    services.programar_comunicado(c, ahora + timedelta(days=2))
            self.stdout.write("Mantenimientos, bloqueos y comunicados de ejemplo listos.")
        self.stdout.write(self.style.SUCCESS("seed_modulo2 completado."))
