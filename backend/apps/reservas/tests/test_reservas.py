import datetime as dt

import pytest
from django.utils import timezone

from apps.core.models import Auditoria
from apps.reservas import services
from apps.reservas.models import Reserva, ReservaHistorial

from .conftest import cuerpo, en_dias

pytestmark = pytest.mark.django_db

RESERVAS = "/api/v1/reservas/"
BLOQUEOS = "/api/v1/bloqueos/"
AMENIDADES = "/api/v1/amenidades/"


def codigos(respuesta):
    return {m["codigo"] for m in respuesta.data["motivos"]}


# --- crear ---------------------------------------------------------------------------------
def test_residente_solicita_reserva(residente_client, residente, salon):
    r = residente_client.post(RESERVAS, cuerpo(salon), format="json")
    assert r.status_code == 201, r.data
    assert r.data["estado"] == "SOLICITADA"  # el salón requiere confirmación
    assert r.data["inmueble_codigo"] == "T1-101"  # se asigna su único inmueble vigente
    assert r.data["puede_cancelar"] is True


def test_sin_confirmacion_requerida_queda_confirmada(residente_client, salon):
    salon.reglas.requiere_confirmacion = False
    salon.reglas.save()
    r = residente_client.post(RESERVAS, cuerpo(salon), format="json")
    assert r.status_code == 201 and r.data["estado"] == "CONFIRMADA"


def test_sin_permiso_o_sin_sesion(client, auth_client, salon):
    from rest_framework.test import APIClient

    assert APIClient().post(RESERVAS, cuerpo(salon), format="json").status_code == 401
    assert auth_client.post(RESERVAS, cuerpo(salon), format="json").status_code == 403  # ana no tiene rol


# --- RF5-RF6: solapamientos y sobre-reservas ---------------------------------------------------
def test_no_permite_solapar_reservas(residente_client, otro_client, salon):
    assert residente_client.post(RESERVAS, cuerpo(salon, desde=10, hasta=12), format="json").status_code == 201
    r = otro_client.post(RESERVAS, cuerpo(salon, desde=11, hasta=13), format="json")
    assert r.status_code == 409
    assert "RESERVA_SOLAPADA" in codigos(r)


def test_reservas_contiguas_si_se_permiten(residente_client, otro_client, salon):
    assert residente_client.post(RESERVAS, cuerpo(salon, desde=10, hasta=12), format="json").status_code == 201
    assert otro_client.post(RESERVAS, cuerpo(salon, desde=12, hasta=14), format="json").status_code == 201


def test_reserva_cancelada_libera_el_horario(residente_client, otro_client, salon):
    r = residente_client.post(RESERVAS, cuerpo(salon), format="json")
    assert residente_client.post(f"{RESERVAS}{r.data['id']}/cancelar/", {}, format="json").status_code == 200
    assert otro_client.post(RESERVAS, cuerpo(salon), format="json").status_code == 201


def test_no_permite_reservar_sobre_un_bloqueo(admin_client, residente_client, salon):
    b = admin_client.post(
        BLOQUEOS,
        {"amenidad": salon.pk, "fecha_inicio": en_dias(5, 9).isoformat(), "fecha_fin": en_dias(5, 13).isoformat(), "motivo": "Pintura"},
        format="json",
    )
    assert b.status_code == 201, b.data
    r = residente_client.post(RESERVAS, cuerpo(salon, desde=12, hasta=14), format="json")
    assert r.status_code == 409 and "BLOQUEADA" in codigos(r)
    # un bloqueo cancelado ya no impide reservar
    assert admin_client.post(f"{BLOQUEOS}{b.data['id']}/cancelar/").status_code == 200
    assert residente_client.post(RESERVAS, cuerpo(salon, desde=12, hasta=14), format="json").status_code == 201


def test_bloqueo_con_reservas_vigentes_exige_confirmar_cancelacion(admin_client, residente_client, salon):
    reserva = residente_client.post(RESERVAS, cuerpo(salon), format="json").data
    cuerpo_bloqueo = {
        "amenidad": salon.pk, "fecha_inicio": en_dias(5, 9).isoformat(),
        "fecha_fin": en_dias(5, 18).isoformat(), "motivo": "Mantenimiento",
    }
    assert admin_client.post(BLOQUEOS, cuerpo_bloqueo, format="json").status_code == 409
    r = admin_client.post(BLOQUEOS, {**cuerpo_bloqueo, "cancelar_reservas": True}, format="json")
    assert r.status_code == 201 and r.data["reservas_canceladas"] == [reserva["id"]]
    assert Reserva.objects.get(pk=reserva["id"]).estado.codigo == "CANCELADA"


def test_aforo_excedido(residente_client, salon):
    r = residente_client.post(RESERVAS, cuerpo(salon, personas=21), format="json")
    assert r.status_code == 400 and "AFORO_EXCEDIDO" in codigos(r)


def test_fuera_de_horario(residente_client, salon):
    r = residente_client.post(RESERVAS, cuerpo(salon, desde=6, hasta=8), format="json")
    assert r.status_code == 400 and "FUERA_HORARIO" in codigos(r)
    r = residente_client.post(RESERVAS, cuerpo(salon, desde=21, hasta=23), format="json")
    assert "FUERA_HORARIO" in codigos(r)


def test_duracion_y_anticipacion(residente_client, salon):
    corta = {**cuerpo(salon), "fecha_fin": en_dias(5, 10, 30).isoformat()}  # 30 min < mínimo de 60
    assert "DURACION_MIN" in codigos(residente_client.post(RESERVAS, corta, format="json"))
    larga = cuerpo(salon, desde=8, hasta=14)  # 6 h > máximo de 4 h
    assert "DURACION_MAX" in codigos(residente_client.post(RESERVAS, larga, format="json"))
    lejana = cuerpo(salon, dias=90)  # más allá de los 60 días permitidos
    assert "ANTICIPACION_MAX" in codigos(residente_client.post(RESERVAS, lejana, format="json"))
    pasada = cuerpo(salon, dias=-2)
    assert "ANTICIPACION_MIN" in codigos(residente_client.post(RESERVAS, pasada, format="json"))


def test_cupo_mensual_por_inmueble(residente_client, salon):
    """Máximo 2 reservas al mes por inmueble (regla del salón). Se usan días del mes siguiente."""
    primero = (timezone.localdate().replace(day=1) + dt.timedelta(days=32)).replace(day=1)

    def en_mes(dia):
        return (primero + dt.timedelta(days=dia - 1) - timezone.localdate()).days

    assert residente_client.post(RESERVAS, cuerpo(salon, dias=en_mes(10)), format="json").status_code == 201
    assert residente_client.post(RESERVAS, cuerpo(salon, dias=en_mes(12)), format="json").status_code == 201
    r = residente_client.post(RESERVAS, cuerpo(salon, dias=en_mes(14)), format="json")
    assert r.status_code == 400 and "CUPO_MENSUAL" in codigos(r)


def test_amenidad_inactiva_no_admite_reservas(residente, salon):
    salon.activa = False
    salon.save()
    motivos = services.verificar_disponibilidad(salon, en_dias(5, 10), en_dias(5, 12), num_personas=5)
    assert "AMENIDAD_INACTIVA" in {m["codigo"] for m in motivos}


def test_respaldo_en_base_de_datos_contra_solapamiento(residente, otro_residente, salon):
    """El trigger SQL también protege cuando se salta la validación del servicio."""
    from django.db import IntegrityError, transaction

    estado = services.estado_reserva("SOLICITADA")
    kw = dict(amenidad=salon, fecha_inicio=en_dias(7, 10), fecha_fin=en_dias(7, 12), num_personas=5, estado=estado)
    Reserva.objects.create(usuario=residente, **kw)
    with pytest.raises(IntegrityError), transaction.atomic():
        Reserva.objects.create(usuario=otro_residente, **kw)
    with pytest.raises(IntegrityError), transaction.atomic():  # aforo
        Reserva.objects.create(usuario=otro_residente, **{**kw, "fecha_inicio": en_dias(8, 10), "fecha_fin": en_dias(8, 11), "num_personas": 999})


# --- verificar / disponibilidad ----------------------------------------------------------------
def test_verificar_disponibilidad(residente_client, otro_client, salon):
    ok = residente_client.get(f"{AMENIDADES}{salon.pk}/verificar/", {"inicio": en_dias(5, 10).isoformat(), "fin": en_dias(5, 12).isoformat(), "num_personas": 5})
    assert ok.status_code == 200 and ok.data == {"disponible": True, "motivos": []}
    residente_client.post(RESERVAS, cuerpo(salon), format="json")
    ocupado = otro_client.get(f"{AMENIDADES}{salon.pk}/verificar/", {"inicio": en_dias(5, 11).isoformat(), "fin": en_dias(5, 13).isoformat()})
    assert ocupado.data["disponible"] is False
    assert ocupado.data["motivos"][0]["codigo"] == "RESERVA_SOLAPADA"


def test_disponibilidad_del_dia_resta_reservas_y_bloqueos(residente_client, admin_client, salon):
    residente_client.post(RESERVAS, cuerpo(salon, desde=10, hasta=12), format="json")
    admin_client.post(BLOQUEOS, {"amenidad": salon.pk, "fecha_inicio": en_dias(5, 15).isoformat(), "fecha_fin": en_dias(5, 17).isoformat(), "motivo": "Aseo"}, format="json")
    fecha = en_dias(5, 0).date().isoformat()
    r = residente_client.get(f"{AMENIDADES}{salon.pk}/disponibilidad/", {"fecha": fecha})
    assert r.status_code == 200
    assert r.data["horarios"] == [{"apertura": "08:00", "cierre": "22:00"}]
    assert {o["tipo"] for o in r.data["ocupados"]} == {"RESERVA", "BLOQUEO"}
    horas = [(l["inicio"][11:16], l["fin"][11:16]) for l in r.data["libres"]]
    assert horas == [("08:00", "10:00"), ("12:00", "15:00"), ("17:00", "22:00")]


# --- cancelación: política -----------------------------------------------------------------------------
def test_politica_de_cancelacion(residente_client, admin_client, residente, salon):
    estado = services.estado_reserva("CONFIRMADA")
    cerca = Reserva.objects.create(
        amenidad=salon, usuario=residente, fecha_inicio=timezone.now() + dt.timedelta(hours=10),
        fecha_fin=timezone.now() + dt.timedelta(hours=12), num_personas=3, estado=estado,
    )
    r = residente_client.post(f"{RESERVAS}{cerca.pk}/cancelar/", {}, format="json")
    assert r.status_code == 400 and "24 hora" in r.data["detail"]  # límite de 24 h
    # el administrador sí puede
    assert admin_client.post(f"{RESERVAS}{cerca.pk}/cancelar/", {"motivo": "Emergencia"}, format="json").status_code == 200


def test_residente_no_cancela_reserva_ajena(residente_client, otro_client, salon):
    r = residente_client.post(RESERVAS, cuerpo(salon), format="json")
    assert otro_client.post(f"{RESERVAS}{r.data['id']}/cancelar/", {}, format="json").status_code == 404  # ni la ve


# --- confirmar / rechazar ------------------------------------------------------------------------------------
def test_confirmar_y_rechazar(residente_client, admin_client, salon):
    a = residente_client.post(RESERVAS, cuerpo(salon, dias=5), format="json").data["id"]
    b = residente_client.post(RESERVAS, cuerpo(salon, dias=6), format="json").data["id"]
    assert residente_client.post(f"{RESERVAS}{a}/confirmar/").status_code == 403
    assert admin_client.post(f"{RESERVAS}{a}/confirmar/").data["estado"] == "CONFIRMADA"
    r = admin_client.post(f"{RESERVAS}{b}/rechazar/", {"motivo": "Evento del conjunto"}, format="json")
    assert r.data["estado"] == "RECHAZADA"
    assert admin_client.post(f"{RESERVAS}{b}/confirmar/").status_code == 400  # transición inválida


# --- RF11: historial -------------------------------------------------------------------------------------------------------
def test_historial_de_la_reserva(residente_client, admin_client, residente, admin, salon):
    rid = residente_client.post(RESERVAS, cuerpo(salon), format="json").data["id"]
    admin_client.post(f"{RESERVAS}{rid}/confirmar/")
    residente_client.post(f"{RESERVAS}{rid}/cancelar/", {"motivo": "Ya no puedo"}, format="json")

    r = residente_client.get(f"{RESERVAS}{rid}/historial/")
    assert r.status_code == 200
    assert [(e["estado_anterior"], e["estado_nuevo"]) for e in r.data] == [
        (None, "SOLICITADA"), ("SOLICITADA", "CONFIRMADA"), ("CONFIRMADA", "CANCELADA"),
    ]
    assert r.data[0]["usuario"] == residente.pk and r.data[1]["usuario"] == admin.pk
    assert r.data[2]["detalle"] == "Ya no puedo"
    assert ReservaHistorial.objects.filter(reserva_id=rid).count() == 3
    assert Auditoria.objects.filter(tabla="reservas", registro_id=str(rid)).exists()


def test_historial_de_otro_usuario_no_visible(otro_client, residente_client, salon):
    rid = residente_client.post(RESERVAS, cuerpo(salon), format="json").data["id"]
    assert otro_client.get(f"{RESERVAS}{rid}/historial/").status_code == 404


def test_listado_solo_muestra_reservas_propias_y_filtra(residente_client, otro_client, admin_client, salon):
    residente_client.post(RESERVAS, cuerpo(salon, dias=5), format="json")
    otro_client.post(RESERVAS, cuerpo(salon, dias=6), format="json")
    assert residente_client.get(RESERVAS).data["count"] == 1
    assert admin_client.get(RESERVAS).data["count"] == 2
    assert admin_client.get(RESERVAS, {"estado": "CANCELADA"}).data["count"] == 0
    assert admin_client.get(RESERVAS, {"estado": "SOLICITADA,CONFIRMADA"}).data["count"] == 2


def test_finalizar_vencidas(residente, salon):
    estado = services.estado_reserva("CONFIRMADA")
    vieja = Reserva.objects.create(
        amenidad=salon, usuario=residente, fecha_inicio=timezone.now() - dt.timedelta(hours=5),
        fecha_fin=timezone.now() - dt.timedelta(hours=3), num_personas=2, estado=estado,
    )
    assert services.finalizar_vencidas() == 1
    vieja.refresh_from_db()
    assert vieja.estado.codigo == "FINALIZADA"
    assert ReservaHistorial.objects.filter(reserva=vieja, estado_nuevo__codigo="FINALIZADA").exists()
