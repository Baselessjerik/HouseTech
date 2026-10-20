"""Liberación automática de solicitudes no confirmadas, recordatorios y notificaciones."""
import datetime as dt

import pytest
from django.utils import timezone

from apps.core.models import Notificacion
from apps.reservas import services
from apps.reservas.automatizacion import procesar_reservas
from apps.reservas.models import Reserva, ReservaHistorial

from .conftest import cuerpo, en_dias

pytestmark = pytest.mark.django_db

RESERVAS = "/api/v1/reservas/"
BLOQUEOS = "/api/v1/bloqueos/"
NOTIFICACIONES = "/api/v1/notificaciones/"
OCUPACION = "/api/v1/reportes/ocupacion/"


def horas(n):
    return dt.timedelta(hours=n)


def solicitar(cliente, salon, **kw):
    r = cliente.post(RESERVAS, cuerpo(salon, **kw), format="json")
    assert r.status_code == 201, r.data
    return r.data["id"]


def envejecer(reserva_id, horas_atras):
    """created_at es auto_now_add: se retrocede con update() para simular el paso del tiempo."""
    Reserva.objects.filter(pk=reserva_id).update(created_at=timezone.now() - horas(horas_atras))


def crear_orm(usuario, salon, codigo, inicio, fin, **extra):
    return Reserva.objects.create(
        amenidad=salon, usuario=usuario, num_personas=3, estado=services.estado_reserva(codigo),
        fecha_inicio=inicio, fecha_fin=fin, **extra,
    )


def titulos(usuario):
    return list(Notificacion.objects.filter(usuario=usuario).values_list("titulo", flat=True))


# --- solicitar / confirmar / rechazar / cancelar → notificaciones ------------------------------------
def test_solicitud_avisa_al_titular_y_a_los_administradores(residente_client, residente, admin, salon):
    solicitar(residente_client, salon)
    assert "Solicitud de reserva recibida" in titulos(residente)
    assert "Nueva solicitud de reserva" in titulos(admin)


def test_reserva_sin_confirmacion_requerida_solo_avisa_confirmada(residente_client, residente, admin, salon):
    salon.reglas.requiere_confirmacion = False
    salon.reglas.save()
    solicitar(residente_client, salon)
    assert titulos(residente) == ["Reserva confirmada"]
    assert titulos(admin) == []


def test_confirmar_rechazar_y_cancelar_notifican_al_titular(residente_client, admin_client, residente, salon):
    salon.reglas.max_reservas_mes_inmueble = None  # tres reservas del mismo inmueble
    salon.reglas.save()
    a, b, c = (solicitar(residente_client, salon, dias=d) for d in (5, 6, 7))
    admin_client.post(f"{RESERVAS}{a}/confirmar/")
    admin_client.post(f"{RESERVAS}{b}/rechazar/", {"motivo": "Evento del conjunto"}, format="json")
    admin_client.post(f"{RESERVAS}{c}/cancelar/", {"motivo": "Emergencia"}, format="json")
    mensajes = {n.titulo: n.mensaje for n in Notificacion.objects.filter(usuario=residente)}
    assert "Reserva confirmada" in mensajes
    assert "Evento del conjunto" in mensajes["Reserva rechazada"]
    assert "Emergencia" in mensajes["Reserva cancelada"]


def test_cancelar_uno_mismo_no_genera_aviso_de_cancelacion(residente_client, residente, salon):
    rid = solicitar(residente_client, salon)
    residente_client.post(f"{RESERVAS}{rid}/cancelar/", {}, format="json")
    assert "Reserva cancelada" not in titulos(residente)


def test_bloqueo_que_cancela_reservas_avisa_al_titular(admin_client, residente_client, residente, salon):
    solicitar(residente_client, salon)
    admin_client.post(BLOQUEOS, {
        "amenidad": salon.pk, "fecha_inicio": en_dias(5, 9).isoformat(), "fecha_fin": en_dias(5, 18).isoformat(),
        "motivo": "Mantenimiento", "cancelar_reservas": True,
    }, format="json")
    assert "Reserva cancelada" in titulos(residente)


def test_correo_se_envia_al_confirmarse_la_transaccion(
    admin_client, residente_client, salon, mailoutbox, django_capture_on_commit_callbacks
):
    rid = solicitar(residente_client, salon)
    mailoutbox.clear()
    with django_capture_on_commit_callbacks(execute=True):
        admin_client.post(f"{RESERVAS}{rid}/confirmar/")
    assert [m.to for m in mailoutbox] == [["rosa@example.com"]]
    assert mailoutbox[0].subject == "Reserva confirmada"


# --- liberación automática ------------------------------------------------------------------------------
def test_libera_solicitudes_no_confirmadas_a_tiempo(residente_client, otro_client, residente, salon):
    rid = solicitar(residente_client, salon)
    ahora = timezone.now()

    assert procesar_reservas(ahora + horas(23))["liberadas"] == 0  # aún dentro del plazo de 24 h
    resultado = procesar_reservas(ahora + horas(25))
    assert resultado["liberadas"] == 1

    reserva = Reserva.objects.get(pk=rid)
    assert reserva.estado.codigo == "EXPIRADA" and reserva.estado.es_final
    assert "no fue confirmada" in reserva.motivo_cancelacion
    ultimo = ReservaHistorial.objects.filter(reserva=reserva).order_by("-id").first()
    assert (ultimo.estado_anterior.codigo, ultimo.estado_nuevo.codigo) == ("SOLICITADA", "EXPIRADA")
    assert ultimo.usuario_id is None  # la hizo el sistema, no una persona
    assert "Solicitud liberada" in titulos(residente)

    assert procesar_reservas(ahora + horas(26))["liberadas"] == 0  # idempotente
    # el horario quedó libre para otra persona
    assert otro_client.post(RESERVAS, cuerpo(salon), format="json").status_code == 201


def test_no_libera_reservas_confirmadas(residente_client, admin_client, salon):
    rid = solicitar(residente_client, salon)
    admin_client.post(f"{RESERVAS}{rid}/confirmar/")
    assert procesar_reservas(timezone.now() + horas(100))["liberadas"] == 0
    assert Reserva.objects.get(pk=rid).estado.codigo == "CONFIRMADA"


def test_el_plazo_nunca_supera_el_inicio_de_la_reserva(residente, salon):
    ahora = timezone.now()
    r = crear_orm(residente, salon, "SOLICITADA", ahora + horas(3), ahora + horas(4))
    assert services.limite_confirmacion(r) == r.fecha_inicio  # plazo de 24 h, pero empieza en 3 h
    assert procesar_reservas(ahora + horas(4))["liberadas"] == 1


def test_plazo_configurable_por_amenidad(residente_client, salon):
    salon.reglas.horas_limite_confirmacion = 2
    salon.reglas.save()
    solicitar(residente_client, salon)
    ahora = timezone.now()
    assert procesar_reservas(ahora + horas(1))["liberadas"] == 0
    assert procesar_reservas(ahora + horas(3))["liberadas"] == 1


def test_no_se_puede_confirmar_una_solicitud_vencida(residente_client, admin_client, salon):
    rid = solicitar(residente_client, salon)
    envejecer(rid, 30)
    r = admin_client.post(f"{RESERVAS}{rid}/confirmar/")
    assert r.status_code == 400 and "plazo" in r.data["detail"]
    assert Reserva.objects.get(pk=rid).estado.codigo == "SOLICITADA"


def test_una_solicitud_vencida_no_bloquea_nuevas_reservas(residente_client, otro_client, salon):
    primera = solicitar(residente_client, salon)
    envejecer(primera, 30)  # venció pero el proceso periódico todavía no corrió
    assert otro_client.post(RESERVAS, cuerpo(salon), format="json").status_code == 201
    assert Reserva.objects.get(pk=primera).estado.codigo == "EXPIRADA"


def test_solicitud_pendiente_muestra_cuando_vence(residente_client, salon):
    rid = solicitar(residente_client, salon)
    datos = residente_client.get(f"{RESERVAS}{rid}/").data
    assert datos["vence_confirmacion_en"] is not None
    assert residente_client.post(f"{RESERVAS}{rid}/cancelar/", {}, format="json").data["vence_confirmacion_en"] is None


def test_expiradas_aparecen_en_el_reporte(admin_client, residente_client, salon):
    solicitar(residente_client, salon)
    procesar_reservas(timezone.now() + horas(25))
    hoy = timezone.localdate()
    r = admin_client.get(OCUPACION, {"desde": hoy.isoformat(), "hasta": (hoy + dt.timedelta(days=10)).isoformat()})
    assert r.data["amenidades"][0]["reservas_por_estado"]["EXPIRADA"] == 1


# --- recordatorios ------------------------------------------------------------------------------------------
def test_recordatorio_antes_del_inicio_una_sola_vez(residente, salon):
    ahora = timezone.now()
    r = crear_orm(residente, salon, "CONFIRMADA", ahora + horas(20), ahora + horas(22), confirmada_en=ahora - horas(30))
    assert procesar_reservas(ahora)["recordatorios"] == 1
    assert "Recordatorio de reserva" in titulos(residente)
    r.refresh_from_db()
    assert r.recordatorio_enviado_en is not None
    assert procesar_reservas(ahora + horas(1))["recordatorios"] == 0


def test_no_recuerda_si_falta_mas_que_la_ventana(residente, salon):
    ahora = timezone.now()
    crear_orm(residente, salon, "CONFIRMADA", ahora + horas(72), ahora + horas(74), confirmada_en=ahora)
    assert procesar_reservas(ahora)["recordatorios"] == 0
    assert procesar_reservas(ahora + horas(50))["recordatorios"] == 1  # ya faltan 22 h


def test_no_recuerda_lo_que_acaba_de_confirmarse(residente, salon):
    ahora = timezone.now()
    r = crear_orm(residente, salon, "CONFIRMADA", ahora + horas(10), ahora + horas(12), confirmada_en=ahora)
    assert procesar_reservas(ahora)["recordatorios"] == 0
    r.refresh_from_db()
    assert r.recordatorio_enviado_en is not None  # queda marcado para no repetirlo después


def test_recordatorio_desactivado_con_cero_horas(residente, salon):
    salon.reglas.horas_recordatorio = 0
    salon.reglas.save()
    ahora = timezone.now()
    crear_orm(residente, salon, "CONFIRMADA", ahora + horas(2), ahora + horas(3), confirmada_en=ahora - horas(30))
    assert procesar_reservas(ahora)["recordatorios"] == 0


def test_no_recuerda_reservas_canceladas(residente, salon):
    ahora = timezone.now()
    crear_orm(residente, salon, "CANCELADA", ahora + horas(10), ahora + horas(12))
    assert procesar_reservas(ahora)["recordatorios"] == 0


def test_avisa_a_administradores_de_solicitudes_por_vencer(residente_client, admin, salon):
    rid = solicitar(residente_client, salon)
    envejecer(rid, 20)  # quedan 4 h de las 24 h de plazo
    assert procesar_reservas()["avisos_pendientes"] == 1
    assert "Solicitud por vencer" in titulos(admin)
    assert procesar_reservas()["avisos_pendientes"] == 0  # una sola vez


def test_no_avisa_de_solicitudes_recien_creadas(residente_client, salon):
    solicitar(residente_client, salon)
    assert procesar_reservas()["avisos_pendientes"] == 0


def test_procesar_finaliza_reservas_terminadas(residente, salon):
    ahora = timezone.now()
    r = crear_orm(residente, salon, "CONFIRMADA", ahora - horas(5), ahora - horas(3))
    assert procesar_reservas(ahora)["finalizadas"] == 1
    r.refresh_from_db()
    assert r.estado.codigo == "FINALIZADA"


# --- endpoint de ejecución manual y API de notificaciones -------------------------------------------------------
def test_endpoint_procesar_solo_para_administradores(admin_client, residente_client):
    assert residente_client.post(f"{RESERVAS}procesar/").status_code == 403
    r = admin_client.post(f"{RESERVAS}procesar/")
    assert r.status_code == 200
    assert set(r.data) == {"liberadas", "recordatorios", "avisos_pendientes", "finalizadas"}


def test_api_de_notificaciones(residente_client, otro_client, admin_client, residente, salon):
    solicitar(residente_client, salon)
    lista = residente_client.get(NOTIFICACIONES)
    assert lista.status_code == 200 and lista.data["count"] == 1
    assert otro_client.get(NOTIFICACIONES).data["count"] == 0  # solo ve las suyas

    assert residente_client.get(f"{NOTIFICACIONES}resumen/").data == {"no_leidas": 1}
    nid = lista.data["results"][0]["id"]
    assert otro_client.post(f"{NOTIFICACIONES}{nid}/leer/").status_code == 404
    leida = residente_client.post(f"{NOTIFICACIONES}{nid}/leer/")
    assert leida.data["leida"] is True and leida.data["leida_en"] is not None
    assert residente_client.get(NOTIFICACIONES, {"leida": "false"}).data["count"] == 0

    solicitar(residente_client, salon, dias=6)
    assert residente_client.post(f"{NOTIFICACIONES}leer-todas/").data == {"marcadas": 1}
    assert residente_client.get(f"{NOTIFICACIONES}resumen/").data == {"no_leidas": 0}


def test_notificaciones_requieren_sesion():
    from rest_framework.test import APIClient

    assert APIClient().get(NOTIFICACIONES).status_code == 401
