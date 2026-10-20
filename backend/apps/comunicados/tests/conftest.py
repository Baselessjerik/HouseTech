"""Fixtures propias del Módulo 2 (no dependen de los tests de otros módulos)."""
from datetime import timedelta

import pytest
from django.core.cache import cache
from django.utils import timezone
from rest_framework.test import APIClient

from apps.comunicados.models import AmenidadRef, Bloqueo, ReservaRef
from apps.core.models import Copropiedad, Estado
from apps.usuarios.models import Rol, Usuario, UsuarioRol

CLAVE = "Clave12345!"


@pytest.fixture(autouse=True)
def limpiar_cache():
    cache.clear()
    yield


def _usuario(username, doc, rol=None):
    u = Usuario.objects.create_user(
        username=username, email=f"{username}@example.com", password=CLAVE,
        nombres=username.capitalize(), apellidos="Prueba", numero_documento=doc,
    )
    if rol:
        UsuarioRol.objects.create(usuario=u, rol=Rol.objects.get(codigo=rol))
    return u


def _cliente(username):
    c = APIClient()
    r = c.post("/api/v1/auth/login/", {"username": username, "password": CLAVE}, format="json")
    assert r.status_code == 200, r.data
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
    return c


@pytest.fixture
def client_anonimo():
    return APIClient()


@pytest.fixture
def admin(db):
    return _usuario("admin2", "2001", "ADMIN")


@pytest.fixture
def residente(db):
    return _usuario("rosa", "2002", "RESIDENTE")


@pytest.fixture
def residente2(db):
    return _usuario("luis", "2003", "RESIDENTE")


@pytest.fixture
def sin_rol(db):
    return _usuario("sinrol", "2004")


@pytest.fixture
def admin_client(admin):
    return _cliente("admin2")


@pytest.fixture
def residente_client(residente):
    return _cliente("rosa")


@pytest.fixture
def residente2_client(residente2):
    return _cliente("luis")


@pytest.fixture
def sin_rol_client(sin_rol):
    return _cliente("sinrol")


@pytest.fixture
def copropiedad(db):
    return Copropiedad.objects.create(nombre="Conjunto de pruebas", nit="900999999-1")


@pytest.fixture
def piscina(copropiedad):
    return AmenidadRef.objects.create(copropiedad=copropiedad, nombre="Piscina", capacidad=20)


@pytest.fixture
def salon(copropiedad):
    return AmenidadRef.objects.create(copropiedad=copropiedad, nombre="Salón social", capacidad=50)


@pytest.fixture
def hacer_reserva():
    """Crea una reserva (estado SOLICITADA por defecto). El trigger de la BD valida cruces."""

    def _crear(amenidad, usuario, inicio, fin, estado="SOLICITADA"):
        return ReservaRef.objects.create(
            amenidad=amenidad, usuario=usuario, fecha_inicio=inicio, fecha_fin=fin,
            estado=Estado.objects.get(proceso="RESERVA", codigo=estado),
        )

    return _crear


@pytest.fixture
def hacer_bloqueo(admin):
    def _crear(amenidad, inicio, fin, motivo="Prueba"):
        return Bloqueo.objects.create(
            amenidad=amenidad, fecha_inicio=inicio, fecha_fin=fin, motivo=motivo, creado_por=admin
        )

    return _crear


@pytest.fixture
def futuro():
    """Devuelve una función que da un instante futuro (en horas)."""
    base = timezone.now().replace(minute=0, second=0, microsecond=0)
    return lambda horas: base + timedelta(hours=horas)


def iso(dt):
    return dt.isoformat()
