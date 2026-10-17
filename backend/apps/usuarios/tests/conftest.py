import pytest
from django.core.cache import cache
from rest_framework.test import APIClient

from apps.usuarios.models import Rol, Usuario, UsuarioRol

CLAVE = "Clave12345!"


@pytest.fixture(autouse=True)
def limpiar_cache():
    """El límite de intentos (throttling) vive en caché: se reinicia en cada test."""
    cache.clear()
    yield


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def usuario():
    return Usuario.objects.create_user(
        username="ana", email="ana@example.com", password=CLAVE,
        nombres="Ana", apellidos="Pérez", numero_documento="100200300",
    )


@pytest.fixture
def auth_client(client, usuario):
    """Cliente ya autenticado como `ana` (la misma instancia que `client`)."""
    r = client.post("/api/v1/auth/login/", {"username": "ana", "password": CLAVE}, format="json")
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
    return client


@pytest.fixture
def cliente_de():
    """Fábrica: cliente nuevo y autenticado como el usuario indicado."""

    def _crear(username, password=CLAVE):
        c = APIClient()
        r = c.post("/api/v1/auth/login/", {"username": username, "password": password}, format="json")
        assert r.status_code == 200, r.data
        c.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
        return c

    return _crear


@pytest.fixture
def admin():
    u = Usuario.objects.create_user(
        username="root", email="root@example.com", password=CLAVE,
        nombres="Root", apellidos="Admin", numero_documento="1",
    )
    UsuarioRol.objects.create(usuario=u, rol=Rol.objects.get(codigo="ADMIN"))
    return u


@pytest.fixture
def admin_client(admin, cliente_de):
    return cliente_de("root")
