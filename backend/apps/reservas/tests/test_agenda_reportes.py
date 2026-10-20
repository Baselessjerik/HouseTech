import csv
import datetime as dt
import io

import pytest
from django.utils import timezone

from apps.reservas import services
from apps.reservas.models import Reserva

from .conftest import cuerpo, en_dias

pytestmark = pytest.mark.django_db

RESERVAS = "/api/v1/reservas/"
AGENDA = "/api/v1/agenda/"
OCUPACION = "/api/v1/reportes/ocupacion/"
HISTORICO = "/api/v1/reportes/reservas/"


def hoy_mas(dias):
    return (timezone.localdate() + dt.timedelta(days=dias)).isoformat()


# --- RF12: agenda -------------------------------------------------------------------------------------
def test_agenda_oculta_datos_ajenos_al_residente(residente_client, otro_client, admin_client, salon):
    residente_client.post(RESERVAS, cuerpo(salon, desde=10, hasta=12), format="json")
    otro_client.post(RESERVAS, cuerpo(salon, desde=14, hasta=16), format="json")
    params = {"desde": hoy_mas(0), "hasta": hoy_mas(30)}

    vista = residente_client.get(AGENDA, params).data["eventos"]
    assert len(vista) == 2
    propia = next(e for e in vista if e["mia"])
    ajena = next(e for e in vista if not e["mia"])
    assert propia["residente"] is None  # el residente no necesita su propio nombre
    assert ajena["titulo"] == "Ocupado" and ajena["estado"] is None and ajena["num_personas"] is None

    admin_vista = admin_client.get(AGENDA, params).data["eventos"]
    assert {e["residente"] for e in admin_vista} == {"Rosa Residente", "Omar Vecino"}


def test_agenda_incluye_bloqueos_y_filtra(admin_client, residente_client, salon):
    admin_client.post("/api/v1/bloqueos/", {"amenidad": salon.pk, "fecha_inicio": en_dias(4, 9).isoformat(), "fecha_fin": en_dias(4, 11).isoformat(), "motivo": "Fumigación"}, format="json")
    residente_client.post(RESERVAS, cuerpo(salon), format="json")
    r = admin_client.get(AGENDA, {"desde": hoy_mas(0), "hasta": hoy_mas(30)})
    assert {e["tipo"] for e in r.data["eventos"]} == {"RESERVA", "BLOQUEO"}
    solo = admin_client.get(f"/api/v1/amenidades/{salon.pk}/calendario/", {"desde": hoy_mas(0), "hasta": hoy_mas(30)})
    assert len(solo.data["eventos"]) == 2
    assert admin_client.get(AGENDA, {"desde": hoy_mas(0), "hasta": hoy_mas(400)}).status_code == 400
    assert admin_client.get(AGENDA, {"estado": "INVENTADO"}).status_code == 400


# --- reportes de ocupación ----------------------------------------------------------------------------------
def _crear(residente, salon, desde, hasta, codigo, dia=-3, personas=10):
    return Reserva.objects.create(
        amenidad=salon, usuario=residente, num_personas=personas, estado=services.estado_reserva(codigo),
        fecha_inicio=en_dias(dia, desde), fecha_fin=en_dias(dia, hasta),
    )


def test_reporte_de_ocupacion(admin_client, residente, salon):
    _crear(residente, salon, 10, 12, "FINALIZADA", dia=-3, personas=10)   # 2 h, 50 % del aforo
    _crear(residente, salon, 14, 18, "FINALIZADA", dia=-2, personas=20)   # 4 h, 100 % del aforo
    _crear(residente, salon, 10, 11, "CANCELADA", dia=-1)                 # no cuenta como ocupación
    params = {"desde": hoy_mas(-6), "hasta": hoy_mas(0)}  # 7 días x 14 h de funcionamiento = 98 h

    r = admin_client.get(OCUPACION, params)
    assert r.status_code == 200, r.data
    fila = r.data["amenidades"][0]
    assert fila["horas_disponibles"] == 98.0
    assert fila["horas_reservadas"] == 6.0
    assert fila["ocupacion_pct"] == round(6 / 98 * 100, 2)
    assert fila["reservas"] == 2
    assert fila["reservas_por_estado"]["CANCELADA"] == 1
    assert fila["tasa_cancelacion_pct"] == round(1 / 3 * 100, 2)
    assert fila["uso_aforo_promedio_pct"] == 75.0
    assert fila["personas_promedio"] == 15.0
    assert r.data["resumen"]["horas_reservadas"] == 6.0
    assert len(r.data["serie"]) == 2  # dos días con uso


def test_reporte_filtros(admin_client, residente, otro_residente, salon):
    _crear(residente, salon, 10, 12, "FINALIZADA", dia=-3)
    _crear(otro_residente, salon, 14, 16, "FINALIZADA", dia=-2)
    base = {"desde": hoy_mas(-6), "hasta": hoy_mas(0)}
    assert admin_client.get(OCUPACION, {**base, "usuario": residente.pk}).data["amenidades"][0]["horas_reservadas"] == 2.0
    assert admin_client.get(OCUPACION, {**base, "estado": "CONFIRMADA"}).data["amenidades"][0]["horas_reservadas"] == 0.0
    assert admin_client.get(OCUPACION, {**base, "amenidad": "99999"}).data["amenidades"] == []
    assert admin_client.get(OCUPACION, {**base, "agrupar": "mes"}).data["serie"]
    assert admin_client.get(OCUPACION, {"desde": hoy_mas(0), "hasta": hoy_mas(-1)}).status_code == 400
    assert admin_client.get(OCUPACION, {"desde": hoy_mas(-500), "hasta": hoy_mas(0)}).status_code == 400
    assert admin_client.get(OCUPACION, {**base, "estado": "X"}).status_code == 400


def test_reporte_csv_y_permisos(admin_client, residente_client, residente, salon):
    _crear(residente, salon, 10, 12, "FINALIZADA")
    r = admin_client.get(OCUPACION, {"desde": hoy_mas(-6), "hasta": hoy_mas(0), "formato": "csv"})
    assert r.status_code == 200 and r["Content-Type"].startswith("text/csv")
    filas = list(csv.reader(io.StringIO(r.content.decode("utf-8-sig"))))
    assert filas[0][0] == "Amenidad" and filas[1][0] == "Salón social"
    assert residente_client.get(OCUPACION).status_code == 403
    assert residente_client.get(HISTORICO).status_code == 403


# --- histórico con filtros --------------------------------------------------------------------------------------------------
def test_historico_con_filtros_y_csv(admin_client, residente, otro_residente, salon):
    _crear(residente, salon, 10, 12, "FINALIZADA", dia=-10)
    _crear(otro_residente, salon, 10, 12, "CANCELADA", dia=-3)
    assert admin_client.get(HISTORICO).data["count"] == 2
    assert admin_client.get(HISTORICO, {"usuario": residente.pk}).data["count"] == 1
    assert admin_client.get(HISTORICO, {"estado": "CANCELADA"}).data["count"] == 1
    assert admin_client.get(HISTORICO, {"desde": hoy_mas(-5), "hasta": hoy_mas(0)}).data["count"] == 1
    assert admin_client.get(HISTORICO, {"amenidad": salon.pk}).data["count"] == 2
    assert admin_client.get(HISTORICO, {"inmueble": 99999}).data["count"] == 0

    r = admin_client.get(HISTORICO, {"formato": "csv"})
    assert r.status_code == 200
    filas = list(csv.reader(io.StringIO(r.content.decode("utf-8-sig"))))
    assert len(filas) == 3 and filas[0][0] == "ID"
