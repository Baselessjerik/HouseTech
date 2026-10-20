import datetime as dt

import pytest
from django.utils import timezone

from apps.core.models import Copropiedad
from apps.inmuebles.models import Inmueble, InmuebleUsuario
from apps.reservas.models import Amenidad, AmenidadHorario, ReglaReserva
from apps.usuarios.models import Rol, Usuario, UsuarioRol

# Reutiliza los fixtures de autenticación del módulo de usuarios
from apps.usuarios.tests.conftest import (  # noqa: F401
    CLAVE, admin, admin_client, auth_client, cliente_de, client, limpiar_cache, usuario,
)


@pytest.fixture
def copropiedad():
    return Copropiedad.objects.create(nombre="Conjunto Prueba", nit="900-1")


@pytest.fixture
def residente(copropiedad):
    u = Usuario.objects.create_user(
        username="rosa", email="rosa@example.com", password=CLAVE,
        nombres="Rosa", apellidos="Residente", numero_documento="2000",
    )
    UsuarioRol.objects.create(usuario=u, rol=Rol.objects.get(codigo="RESIDENTE"))
    inmueble = Inmueble.objects.create(copropiedad=copropiedad, numero="101", codigo_interno="T1-101")
    InmuebleUsuario.objects.create(inmueble=inmueble, usuario=u, tipo_relacion="PROPIETARIO")
    return u


@pytest.fixture
def otro_residente(copropiedad):
    u = Usuario.objects.create_user(
        username="omar", email="omar@example.com", password=CLAVE,
        nombres="Omar", apellidos="Vecino", numero_documento="2001",
    )
    UsuarioRol.objects.create(usuario=u, rol=Rol.objects.get(codigo="RESIDENTE"))
    inmueble = Inmueble.objects.create(copropiedad=copropiedad, numero="202", codigo_interno="T1-202")
    InmuebleUsuario.objects.create(inmueble=inmueble, usuario=u, tipo_relacion="PROPIETARIO")
    return u


@pytest.fixture
def residente_client(residente, cliente_de):
    return cliente_de("rosa")


@pytest.fixture
def otro_client(otro_residente, cliente_de):
    return cliente_de("omar")


@pytest.fixture
def salon(copropiedad):
    """Salón social: aforo 20, abierto todos los días 08:00-22:00, confirma el administrador."""
    a = Amenidad.objects.create(copropiedad=copropiedad, nombre="Salón social", capacidad=20)
    ReglaReserva.objects.create(
        amenidad=a, duracion_min_minutos=60, duracion_max_minutos=240, anticipacion_min_horas=1,
        anticipacion_max_dias=60, max_reservas_mes_inmueble=2, horas_limite_cancelacion=24,
        requiere_confirmacion=True,
    )
    AmenidadHorario.objects.bulk_create([
        AmenidadHorario(amenidad=a, dia_semana=d, hora_apertura=dt.time(8), hora_cierre=dt.time(22))
        for d in range(1, 8)
    ])
    return a


def en_dias(dias, hora, minuto=0):
    """Fecha/hora local futura: `dias` días desde hoy a la hora indicada."""
    base = timezone.localtime() + dt.timedelta(days=dias)
    return base.replace(hour=hora, minute=minuto, second=0, microsecond=0)


def cuerpo(amenidad, dias=5, desde=10, hasta=12, personas=10, **extra):
    return {
        "amenidad": amenidad.pk,
        "fecha_inicio": en_dias(dias, desde).isoformat(),
        "fecha_fin": en_dias(dias, hasta).isoformat(),
        "num_personas": personas,
        **extra,
    }
