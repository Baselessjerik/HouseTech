import re
from datetime import timedelta

import pytest
from django.utils import timezone

from apps.usuarios.models import RecuperacionPassword

pytestmark = pytest.mark.django_db

RECUPERAR = "/api/v1/auth/recuperar/"
RESTABLECER = "/api/v1/auth/restablecer/"
VALIDAR_CODIGO = "/api/v1/auth/validar-codigo/"
LOGIN = "/api/v1/auth/login/"
CLAVE = "Clave12345!"
NUEVA = "Nueva12345!x"


def pedir_codigo(client, mailoutbox, identificador="ana@example.com"):
    r = client.post(RECUPERAR, {"identificador": identificador}, format="json")
    assert r.status_code == 200
    return re.search(r"\b(\d{6})\b", mailoutbox[-1].body).group(1)


def restablecer(client, codigo, clave=NUEVA, identificador="ana@example.com"):
    return client.post(
        RESTABLECER, {"identificador": identificador, "codigo": codigo, "password_nueva": clave}, format="json"
    )


def test_solicitar_envia_codigo_por_correo(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    assert len(mailoutbox) == 1
    assert mailoutbox[0].to == ["ana@example.com"]
    assert len(codigo) == 6


def test_solicitar_no_revela_si_la_cuenta_existe(client, usuario, mailoutbox):
    existente = client.post(RECUPERAR, {"identificador": "ana"}, format="json")
    inexistente = client.post(RECUPERAR, {"identificador": "nadie@example.com"}, format="json")
    assert existente.status_code == inexistente.status_code == 200
    assert existente.data == inexistente.data
    assert len(mailoutbox) == 1  # solo salió el de la cuenta real


def test_restablecer_cambia_la_clave_y_el_codigo_no_se_reutiliza(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    assert restablecer(client, codigo).status_code == 204
    assert client.post(LOGIN, {"username": "ana", "password": CLAVE}, format="json").status_code == 401
    assert client.post(LOGIN, {"username": "ana", "password": NUEVA}, format="json").status_code == 200
    assert restablecer(client, codigo, clave="Otra12345!xyz").status_code == 400  # ya usado


def test_codigo_incorrecto(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    incorrecto = "000000" if codigo != "000000" else "111111"
    r = restablecer(client, incorrecto)
    assert r.status_code == 400
    assert "codigo" in r.data


def test_validar_codigo_no_cambia_la_clave_ni_consumo_el_codigo(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    respuesta = client.post(
        VALIDAR_CODIGO,
        {"identificador": "ana@example.com", "codigo": codigo},
        format="json",
    )
    assert respuesta.status_code == 204
    assert client.post(LOGIN, {"username": "ana", "password": CLAVE}, format="json").status_code == 200
    assert restablecer(client, codigo).status_code == 204


def test_validar_codigo_rechaza_codigo_incorrecto(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    incorrecto = "000000" if codigo != "000000" else "111111"
    respuesta = client.post(
        VALIDAR_CODIGO,
        {"identificador": "ana@example.com", "codigo": incorrecto},
        format="json",
    )
    assert respuesta.status_code == 400


def test_codigo_vencido(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    RecuperacionPassword.objects.update(expira_en=timezone.now() - timedelta(minutes=1))
    assert restablecer(client, codigo).status_code == 400


def test_un_codigo_nuevo_invalida_el_anterior(client, usuario, mailoutbox):
    primero = pedir_codigo(client, mailoutbox)
    segundo = pedir_codigo(client, mailoutbox)
    assert restablecer(client, primero).status_code == 400
    assert restablecer(client, segundo).status_code == 204


def test_clave_debil_no_gasta_el_codigo(client, usuario, mailoutbox):
    codigo = pedir_codigo(client, mailoutbox)
    r = restablecer(client, codigo, clave="123")
    assert r.status_code == 400
    assert "password_nueva" in r.data
    assert restablecer(client, codigo).status_code == 204


def test_usuario_inactivo_no_recibe_codigo(client, usuario, mailoutbox):
    usuario.activo = False
    usuario.save()
    assert client.post(RECUPERAR, {"identificador": "ana"}, format="json").status_code == 200
    assert len(mailoutbox) == 0


def test_solicitar_tiene_limite_de_intentos(client, usuario):
    for _ in range(10):
        assert client.post(RECUPERAR, {"identificador": "ana"}, format="json").status_code == 200
    assert client.post(RECUPERAR, {"identificador": "ana"}, format="json").status_code == 429
