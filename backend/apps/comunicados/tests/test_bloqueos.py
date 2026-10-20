import pytest

from apps.comunicados.models import Bloqueo, Notificacion
from apps.core.models import Auditoria

from .conftest import iso

pytestmark = pytest.mark.django_db

BLOQUEOS = "/api/v1/bloqueos/"
DISPONIBILIDAD = "/api/v1/amenidades/disponibilidad/"


def datos(amenidad, inicio, fin, **extra):
    return {"amenidad": amenidad.pk, "fecha_inicio": iso(inicio), "fecha_fin": iso(fin), "motivo": "Limpieza", **extra}


def test_requiere_autenticacion_y_permiso(client_anonimo, residente_client, piscina, futuro):
    assert client_anonimo.get(BLOQUEOS).status_code == 401
    assert residente_client.get(BLOQUEOS).status_code == 403
    r = residente_client.post(BLOQUEOS, datos(piscina, futuro(2), futuro(4)), format="json")
    assert r.status_code == 403


def test_admin_crea_bloqueo_y_queda_auditado(admin_client, admin, piscina, futuro):
    r = admin_client.post(BLOQUEOS, datos(piscina, futuro(2), futuro(4)), format="json")
    assert r.status_code == 201, r.data
    assert r.data["estado"] == "PROGRAMADO"
    assert r.data["amenidad_nombre"] == "Piscina"
    log = Auditoria.objects.filter(tabla="bloqueos_amenidad", operacion="INSERT").first()
    assert log is not None and log.usuario_id == admin.pk


@pytest.mark.parametrize(
    "campo,valor",
    [("motivo", ""), ("motivo", "  "), ("motivo", "ab")],
)
def test_motivo_obligatorio(admin_client, piscina, futuro, campo, valor):
    d = datos(piscina, futuro(2), futuro(4))
    d[campo] = valor
    r = admin_client.post(BLOQUEOS, d, format="json")
    assert r.status_code == 400 and "motivo" in r.data


def test_fin_debe_ser_posterior_al_inicio(admin_client, piscina, futuro):
    r = admin_client.post(BLOQUEOS, datos(piscina, futuro(4), futuro(2)), format="json")
    assert r.status_code == 400 and "fecha_fin" in r.data


def test_no_permite_fechas_en_el_pasado(admin_client, piscina, futuro):
    r = admin_client.post(BLOQUEOS, datos(piscina, futuro(-48), futuro(-24)), format="json")
    assert r.status_code == 400 and "fecha_inicio" in r.data


def test_bloqueos_cruzados_devuelven_409(admin_client, piscina, futuro, hacer_bloqueo):
    hacer_bloqueo(piscina, futuro(2), futuro(6))
    r = admin_client.post(BLOQUEOS, datos(piscina, futuro(4), futuro(8)), format="json")
    assert r.status_code == 409
    assert r.data["codigo"] == "bloqueo_cruzado"


def test_bloqueo_en_otra_amenidad_no_choca(admin_client, piscina, salon, futuro, hacer_bloqueo):
    hacer_bloqueo(piscina, futuro(2), futuro(6))
    r = admin_client.post(BLOQUEOS, datos(salon, futuro(2), futuro(6)), format="json")
    assert r.status_code == 201


def test_reservas_en_conflicto_piden_confirmacion(
    admin_client, residente, piscina, futuro, hacer_reserva
):
    reserva = hacer_reserva(piscina, residente, futuro(3), futuro(5))
    r = admin_client.post(BLOQUEOS, datos(piscina, futuro(2), futuro(6)), format="json")
    assert r.status_code == 409
    assert r.data["codigo"] == "reservas_en_conflicto"
    assert r.data["reservas"][0]["id"] == reserva.pk
    assert not Bloqueo.objects.exists()

    r = admin_client.post(BLOQUEOS + "?confirmar=true", datos(piscina, futuro(2), futuro(6)), format="json")
    assert r.status_code == 201, r.data
    avisado = Notificacion.objects.filter(usuario=residente, tipo="RESERVA")
    assert avisado.count() == 1


def test_rf5_no_se_puede_reservar_en_un_bloqueo_y_si_tras_cancelarlo(
    admin_client, residente, piscina, futuro, hacer_bloqueo, hacer_reserva
):
    from django.db import IntegrityError, transaction

    b = hacer_bloqueo(piscina, futuro(2), futuro(6))
    with pytest.raises(IntegrityError):
        with transaction.atomic():
            hacer_reserva(piscina, residente, futuro(3), futuro(4))
    r = admin_client.post(f"{BLOQUEOS}{b.pk}/cancelar/")
    assert r.status_code == 200 and r.data["estado"] == "CANCELADO"
    assert hacer_reserva(piscina, residente, futuro(3), futuro(4)).pk


def test_modificar_bloqueo(admin_client, piscina, futuro, hacer_bloqueo):
    b = hacer_bloqueo(piscina, futuro(2), futuro(6))
    r = admin_client.patch(f"{BLOQUEOS}{b.pk}/", {"motivo": "Nuevo motivo", "fecha_fin": iso(futuro(8))}, format="json")
    assert r.status_code == 200, r.data
    assert r.data["motivo"] == "Nuevo motivo"
    b.refresh_from_db()
    assert b.fecha_fin == futuro(8)


def test_no_se_puede_cambiar_la_amenidad(admin_client, piscina, salon, futuro, hacer_bloqueo):
    b = hacer_bloqueo(piscina, futuro(2), futuro(6))
    r = admin_client.patch(f"{BLOQUEOS}{b.pk}/", {"amenidad": salon.pk}, format="json")
    assert r.status_code == 400 and "amenidad" in r.data


def test_cancelar_dos_veces_o_editar_cancelado_falla(admin_client, piscina, futuro, hacer_bloqueo):
    b = hacer_bloqueo(piscina, futuro(2), futuro(6))
    assert admin_client.post(f"{BLOQUEOS}{b.pk}/cancelar/").status_code == 200
    assert admin_client.post(f"{BLOQUEOS}{b.pk}/cancelar/").status_code == 400
    assert admin_client.patch(f"{BLOQUEOS}{b.pk}/", {"motivo": "xyz"}, format="json").status_code == 400


def test_no_existe_delete(admin_client, piscina, futuro, hacer_bloqueo):
    b = hacer_bloqueo(piscina, futuro(2), futuro(6))
    assert admin_client.delete(f"{BLOQUEOS}{b.pk}/").status_code == 405
    assert admin_client.put(f"{BLOQUEOS}{b.pk}/", {}, format="json").status_code == 405


def test_filtro_activo(admin_client, piscina, futuro, hacer_bloqueo):
    activo = hacer_bloqueo(piscina, futuro(2), futuro(6))
    cancelado = hacer_bloqueo(piscina, futuro(10), futuro(12))
    admin_client.post(f"{BLOQUEOS}{cancelado.pk}/cancelar/")
    r = admin_client.get(BLOQUEOS, {"activo": "true"})
    assert [x["id"] for x in r.data["results"]] == [activo.pk]


def test_crear_bloqueo_notifica_a_residentes(admin_client, residente, residente2, sin_rol, piscina, futuro):
    admin_client.post(BLOQUEOS, datos(piscina, futuro(2), futuro(4)), format="json")
    assert Notificacion.objects.filter(usuario=residente, tipo="BLOQUEO").count() == 1
    assert Notificacion.objects.filter(usuario=residente2, tipo="BLOQUEO").count() == 1
    assert not Notificacion.objects.filter(usuario=sin_rol).exists()  # sin permiso comunicados.ver


# ------------------------------------------------------------------ disponibilidad (RF6)
def test_disponibilidad_refleja_bloqueo_y_reserva(
    residente_client, residente, piscina, salon, futuro, hacer_bloqueo, hacer_reserva
):
    from django.utils import timezone

    ahora = timezone.now()
    from datetime import timedelta

    hacer_bloqueo(piscina, ahora - timedelta(hours=1), ahora + timedelta(hours=1), motivo="Pintura")
    hacer_reserva(salon, residente, ahora - timedelta(minutes=30), ahora + timedelta(hours=2))
    r = residente_client.get(DISPONIBILIDAD)
    assert r.status_code == 200
    estados = {a["nombre"]: a for a in r.data}
    assert estados["Piscina"]["estado"] == "BLOQUEADA" and estados["Piscina"]["motivo"] == "Pintura"
    assert estados["Salón social"]["estado"] == "RESERVADA"


def test_disponibilidad_en_otro_momento(residente_client, piscina, futuro, hacer_bloqueo):
    hacer_bloqueo(piscina, futuro(48), futuro(52))
    ahora = residente_client.get(DISPONIBILIDAD)
    assert ahora.data[0]["estado"] == "DISPONIBLE"
    assert ahora.data[0]["proximo_bloqueo"] is not None
    luego = residente_client.get(DISPONIBILIDAD, {"momento": iso(futuro(49))})
    assert luego.data[0]["estado"] == "BLOQUEADA"


def test_disponibilidad_momento_invalido(residente_client):
    assert residente_client.get(DISPONIBILIDAD, {"momento": "mañana"}).status_code == 400


def test_disponibilidad_detalle(residente_client, piscina):
    r = residente_client.get(f"/api/v1/amenidades/{piscina.pk}/disponibilidad/")
    assert r.status_code == 200 and r.data["id"] == piscina.pk
    assert residente_client.get("/api/v1/amenidades/99999/disponibilidad/").status_code == 404
