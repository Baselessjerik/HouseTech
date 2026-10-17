import pytest
from rest_framework.test import APIClient

from apps.core.models import Auditoria
from apps.usuarios.models import Rol, Usuario, UsuarioRol

pytestmark = pytest.mark.django_db

CLAVE = "Clave12345!"
LOGIN = "/api/v1/auth/login/"
ME = "/api/v1/auth/me/"


@pytest.fixture
def client():
    return APIClient()


@pytest.fixture
def usuario():
    return Usuario.objects.create_user(
        username="ana", email="ana@example.com", password=CLAVE,
        nombres="Ana", apellidos="Pérez", numero_documento="100200300",
    )


def iniciar_sesion(client, identificador="ana", clave=CLAVE):
    return client.post(LOGIN, {"username": identificador, "password": clave}, format="json")


def test_health(client):
    assert client.get("/api/v1/health/").json() == {"status": "ok"}


def test_login_correcto_devuelve_tokens_y_perfil(client, usuario):
    r = iniciar_sesion(client)
    assert r.status_code == 200
    assert {"access", "refresh", "usuario"} <= set(r.data)
    assert r.data["usuario"]["username"] == "ana"


def test_login_con_correo_sin_distinguir_mayusculas(client, usuario):
    assert iniciar_sesion(client, "ANA@Example.com").status_code == 200


def test_login_clave_incorrecta(client, usuario):
    response = iniciar_sesion(client, clave="mala")
    assert response.status_code == 401
    assert response.data["detail"] == "El usuario, correo o contraseña no son correctos."


def test_login_usuario_inactivo(client, usuario):
    usuario.activo = False
    usuario.save()
    response = iniciar_sesion(client)
    assert response.status_code == 401
    assert response.data["detail"] == "El usuario, correo o contraseña no son correctos."


def test_me_requiere_token(client):
    assert client.get(ME).status_code == 401


def test_me_devuelve_roles_y_permisos(client, usuario):
    UsuarioRol.objects.create(usuario=usuario, rol=Rol.objects.get(codigo="RESIDENTE"))
    access = iniciar_sesion(client).data["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {access}")
    r = client.get(ME)
    assert r.status_code == 200
    assert r.data["roles"] == ["RESIDENTE"]
    assert "pqr.radicar" in r.data["permisos"]
    assert "usuarios.gestionar" not in r.data["permisos"]


@pytest.mark.parametrize(
    ("rol", "permitidos", "no_permitidos"),
    [
        (
            "ADMIN",
            {"usuarios.gestionar", "roles.gestionar", "reportes.ver", "auditoria.ver"},
            set(),
        ),
        (
            "RESIDENTE",
            {"comunicados.ver", "inmuebles.consultar", "pqr.radicar", "reservas.solicitar"},
            {"usuarios.gestionar", "pqr.gestionar", "roles.gestionar"},
        ),
        (
            "RESPONSABLE_PQR",
            {"comunicados.ver", "inmuebles.consultar", "pqr.gestionar", "pqr.radicar"},
            {"usuarios.gestionar", "roles.gestionar", "reservas.solicitar"},
        ),
    ],
)
def test_login_y_jwt_exponen_permisos_segun_rol(
    client, usuario, rol, permitidos, no_permitidos
):
    UsuarioRol.objects.create(usuario=usuario, rol=Rol.objects.get(codigo=rol))

    login = iniciar_sesion(client)
    assert login.status_code == 200
    assert login.data["access"]
    assert login.data["refresh"]

    client.credentials(HTTP_AUTHORIZATION=f"Bearer {login.data['access']}")
    perfil = client.get(ME)

    assert perfil.status_code == 200
    assert perfil.data["roles"] == [rol]
    assert permitidos <= set(perfil.data["permisos"])
    assert not no_permitidos.intersection(perfil.data["permisos"])


def test_refresh_jwt_emite_un_access_token_utilizable(client, usuario):
    tokens = iniciar_sesion(client).data

    response = client.post(
        "/api/v1/auth/refresh/",
        {"refresh": tokens["refresh"]},
        format="json",
    )

    assert response.status_code == 200
    assert response.data["access"]
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {response.data['access']}")
    assert client.get(ME).status_code == 200


def test_logout_revoca_access_y_refresh(client, usuario):
    tokens = iniciar_sesion(client).data
    client.credentials(HTTP_AUTHORIZATION=f"Bearer {tokens['access']}")
    r = client.post("/api/v1/auth/logout/", {"refresh": tokens["refresh"]}, format="json")
    assert r.status_code == 204
    assert client.get(ME).status_code == 401  # access revocado
    client.credentials()
    r = client.post("/api/v1/auth/refresh/", {"refresh": tokens["refresh"]}, format="json")
    assert r.status_code == 401  # refresh revocado


def test_auditoria_registra_quien_hizo_el_cambio(client, usuario):
    """Protege la trampa de SET LOCAL: si falla, usuario_id queda en NULL."""
    iniciar_sesion(client)  # actualiza ultimo_login -> dispara el trigger de auditoría
    assert Auditoria.objects.filter(
        tabla="usuarios", operacion="UPDATE", usuario_id=usuario.pk
    ).exists()
