import pytest

from apps.comunicados.models import Bloqueo, Mantenimiento, Notificacion

from .conftest import iso

pytestmark = pytest.mark.django_db

URL = "/api/v1/mantenimientos/"


def datos(amenidad, inicio, fin, **extra):
    return {
        "amenidad": amenidad.pk if amenidad else None,
        "titulo": "Limpieza de filtros",
        "descripcion": "Cambio de filtros",
        "fecha_inicio": iso(inicio),
        "fecha_fin": iso(fin),
        "responsable": "Proveedor SAS",
        **extra,
    }


def test_solo_administradores(client_anonimo, residente_client, piscina, futuro):
    assert client_anonimo.get(URL).status_code == 401
    assert residente_client.get(URL).status_code == 403
    assert residente_client.post(URL, datos(piscina, futuro(2), futuro(4)), format="json").status_code == 403


def test_crear_mantenimiento_queda_programado(admin_client, piscina, futuro):
    r = admin_client.post(URL, datos(piscina, futuro(2), futuro(4)), format="json")
    assert r.status_code == 201, r.data
    assert r.data["estado"] == "PROGRAMADO"
    assert r.data["amenidad_nombre"] == "Piscina"
    assert r.data["bloqueos_activos"] == 0


def test_mantenimiento_sin_amenidad(admin_client, futuro):
    r = admin_client.post(URL, datos(None, futuro(2), futuro(4)), format="json")
    assert r.status_code == 201 and r.data["amenidad"] is None


def test_crear_con_bloqueo_asociado(admin_client, residente, piscina, futuro):
    r = admin_client.post(URL, datos(piscina, futuro(2), futuro(4), crear_bloqueo=True), format="json")
    assert r.status_code == 201, r.data
    assert r.data["bloqueos_activos"] == 1
    b = Bloqueo.objects.get()
    assert b.mantenimiento_id == r.data["id"]
    assert Notificacion.objects.filter(usuario=residente, tipo="MANTENIMIENTO").count() == 1


def test_crear_bloqueo_sin_amenidad_falla(admin_client, futuro):
    r = admin_client.post(URL, datos(None, futuro(2), futuro(4), crear_bloqueo=True), format="json")
    assert r.status_code == 400 and "crear_bloqueo" in r.data


def test_fechas_invalidas(admin_client, piscina, futuro):
    assert admin_client.post(URL, datos(piscina, futuro(4), futuro(2)), format="json").status_code == 400
    assert admin_client.post(URL, datos(piscina, futuro(-5), futuro(-2)), format="json").status_code == 400


def test_flujo_de_estados(admin_client, piscina, futuro):
    pk = admin_client.post(URL, datos(piscina, futuro(2), futuro(4)), format="json").data["id"]
    assert admin_client.post(f"{URL}{pk}/finalizar/").status_code == 400  # no se salta EN_CURSO
    assert admin_client.post(f"{URL}{pk}/iniciar/").data["estado"] == "EN_CURSO"
    assert admin_client.post(f"{URL}{pk}/finalizar/").data["estado"] == "FINALIZADO"
    assert admin_client.post(f"{URL}{pk}/cancelar/").status_code == 400  # ya es final
    assert admin_client.patch(f"{URL}{pk}/", {"titulo": "Otro"}, format="json").status_code == 400


def test_cancelar_libera_los_bloqueos(admin_client, piscina, futuro):
    pk = admin_client.post(URL, datos(piscina, futuro(2), futuro(4), crear_bloqueo=True), format="json").data["id"]
    r = admin_client.post(f"{URL}{pk}/cancelar/")
    assert r.status_code == 200 and r.data["estado"] == "CANCELADO"
    assert Bloqueo.objects.get().cancelado is True


def test_modificar_fechas_actualiza_el_bloqueo(admin_client, piscina, futuro):
    pk = admin_client.post(URL, datos(piscina, futuro(2), futuro(4), crear_bloqueo=True), format="json").data["id"]
    r = admin_client.patch(f"{URL}{pk}/", {"fecha_fin": iso(futuro(6)), "titulo": "Nuevo título"}, format="json")
    assert r.status_code == 200, r.data
    b = Bloqueo.objects.get()
    assert b.fecha_fin == futuro(6)
    assert Mantenimiento.objects.get(pk=pk).titulo == "Nuevo título"


def test_filtro_por_estado(admin_client, piscina, futuro):
    pk = admin_client.post(URL, datos(piscina, futuro(2), futuro(4)), format="json").data["id"]
    admin_client.post(f"{URL}{pk}/iniciar/")
    admin_client.post(URL, datos(piscina, futuro(10), futuro(12)), format="json")
    r = admin_client.get(URL, {"estado": "EN_CURSO"})
    assert [m["id"] for m in r.data["results"]] == [pk]
