import pytest

pytestmark = pytest.mark.django_db

LOGIN = "/api/v1/auth/login/"
REGISTRO = "/api/v1/auth/registro/"
ME = "/api/v1/auth/me/"
CAMBIAR = "/api/v1/auth/cambiar-password/"
CLAVE_ANA = "Clave12345!"
NUEVA = "Nueva12345!x"


def datos(**cambios):
    base = {
        "tipo_documento": "CC", "numero_documento": "555666777", "nombres": "Luis",
        "apellidos": "Gómez", "username": "luis", "email": "luis@example.com",
        "password": "Segura12345!",
    }
    base.update(cambios)
    return base


def iniciar_sesion(client, username, password):
    return client.post(LOGIN, {"username": username, "password": password}, format="json")


def test_registro_crea_residente_y_permite_login(client):
    response = client.post(REGISTRO, datos(), format="json")
    assert response.status_code == 201
    assert "password" not in response.data
    assert response.data["roles"] == ["RESIDENTE"]
    assert iniciar_sesion(client, "luis", "Segura12345!").status_code == 200


def test_registro_ignora_intentos_de_asignarse_rol_o_estado(client):
    response = client.post(
        REGISTRO, datos(roles=["ADMIN"], rol="ADMIN", activo=False, is_staff=True), format="json"
    )
    assert response.status_code == 201
    assert response.data["roles"] == ["RESIDENTE"]
    assert response.data["activo"] is True


@pytest.mark.parametrize(
    "campo,valor",
    [("username", "ANA"), ("email", "ANA@EXAMPLE.COM"), ("numero_documento", "100200300")],
)
def test_registro_rechaza_duplicados(client, usuario, campo, valor):
    response = client.post(REGISTRO, datos(**{campo: valor}), format="json")
    assert response.status_code == 400
    assert campo in response.data


def test_registro_rechaza_clave_debil(client):
    response = client.post(REGISTRO, datos(password="123"), format="json")
    assert response.status_code == 400
    assert "password" in response.data


def test_actualizar_perfil_solo_campos_permitidos(auth_client, usuario):
    response = auth_client.patch(
        ME, {"nombres": "Anita", "telefono": "3001234567", "username": "otro", "activo": False},
        format="json",
    )
    assert response.status_code == 200
    assert response.data["nombres"] == "Anita"
    usuario.refresh_from_db()
    assert (usuario.nombres, usuario.telefono, usuario.username, usuario.activo) == (
        "Anita", "3001234567", "ana", True,
    )


def test_actualizar_perfil_rechaza_correo_de_otro_usuario(auth_client):
    from apps.usuarios.models import Usuario

    Usuario.objects.create_user(
        username="otro", email="otro@example.com", password="Otra12345!",
        nombres="O", apellidos="T", numero_documento="999",
    )
    assert auth_client.patch(ME, {"email": "OTRO@example.com"}, format="json").status_code == 400


def test_actualizar_perfil_permite_conservar_el_propio_correo(auth_client):
    assert auth_client.patch(ME, {"email": "ana@example.com"}, format="json").status_code == 200


def test_put_en_perfil_no_esta_permitido(auth_client):
    assert auth_client.put(ME, {"nombres": "X"}, format="json").status_code == 405


def test_cambiar_password_con_actual_incorrecta(auth_client):
    response = auth_client.post(
        CAMBIAR, {"password_actual": "mala", "password_nueva": NUEVA}, format="json"
    )
    assert response.status_code == 400
    assert "password_actual" in response.data


def test_cambiar_password_rechaza_clave_debil(auth_client):
    response = auth_client.post(
        CAMBIAR, {"password_actual": CLAVE_ANA, "password_nueva": "123"}, format="json"
    )
    assert response.status_code == 400
    assert "password_nueva" in response.data


def test_cambiar_password_ok(auth_client):
    response = auth_client.post(
        CAMBIAR, {"password_actual": CLAVE_ANA, "password_nueva": NUEVA}, format="json"
    )
    assert response.status_code == 204
    auth_client.credentials()
    assert iniciar_sesion(auth_client, "ana", CLAVE_ANA).status_code == 401
    assert iniciar_sesion(auth_client, "ana", NUEVA).status_code == 200
