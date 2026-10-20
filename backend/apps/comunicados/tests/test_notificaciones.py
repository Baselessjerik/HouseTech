import pytest

from apps.comunicados.models import Notificacion

pytestmark = pytest.mark.django_db

URL = "/api/v1/notificaciones/"


@pytest.fixture
def notificaciones(residente, residente2):
    mias = [
        Notificacion.objects.create(usuario=residente, tipo="COMUNICADO", titulo=f"N{i}", mensaje="m")
        for i in range(3)
    ]
    Notificacion.objects.create(usuario=residente2, tipo="BLOQUEO", titulo="Ajena", mensaje="m")
    return mias


def test_requiere_autenticacion(client_anonimo):
    assert client_anonimo.get(URL).status_code == 401


def test_solo_ve_las_propias(residente_client, notificaciones):
    r = residente_client.get(URL)
    assert r.data["count"] == 3
    assert all(n["titulo"] != "Ajena" for n in r.data["results"])


def test_conteo_y_leer_una(residente_client, notificaciones):
    assert residente_client.get(URL + "no-leidas/conteo/").data == {"no_leidas": 3}
    r = residente_client.post(f"{URL}{notificaciones[0].pk}/leer/")
    assert r.status_code == 200 and r.data["leida"] is True and r.data["leida_en"]
    assert residente_client.get(URL + "no-leidas/conteo/").data == {"no_leidas": 2}
    assert residente_client.get(URL, {"leida": "false"}).data["count"] == 2


def test_no_puede_leer_las_de_otro(residente2_client, notificaciones):
    assert residente2_client.post(f"{URL}{notificaciones[0].pk}/leer/").status_code == 404


def test_leer_todas(residente_client, residente2_client, notificaciones):
    assert residente_client.post(URL + "leer-todas/").data == {"actualizadas": 3}
    assert residente_client.get(URL + "no-leidas/conteo/").data == {"no_leidas": 0}
    assert residente2_client.get(URL + "no-leidas/conteo/").data == {"no_leidas": 1}
