import pytest
from rest_framework.test import APIClient

from apps.usuarios.models import Usuario

CLAVE = "Clave12345!"


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def usuario():
    return Usuario.objects.create_user(
        username="ana",
        email="ana@example.com",
        password=CLAVE,
        nombres="Ana",
        apellidos="Pérez",
        numero_documento="100200300",
    )


@pytest.fixture
def auth_client(client, usuario):
    response = client.post(
        "/api/v1/auth/login/",
        {"username": "ana", "password": CLAVE},
        format="json",
    )
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
    return client
