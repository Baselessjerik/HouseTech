"""Pruebas de regresión del Paquete B para comunicados, bloqueos y mantenimientos."""
from datetime import timedelta

import pytest
from django.utils import timezone

from apps.comunicados.models import (
    Bloqueo,
    CategoriaComunicado,
    Comunicado,
    ComunicadoHistorial,
    Mantenimiento,
)

from .conftest import iso

pytestmark = pytest.mark.django_db

BLOQUEOS = "/api/v1/bloqueos/"
MANTENIMIENTOS = "/api/v1/mantenimientos/"
COMUNICADOS = "/api/v1/comunicados/"
AVISOS = "/api/v1/avisos/"
CATEGORIAS = "/api/v1/categorias-comunicado/"
DISPONIBILIDAD = "/api/v1/amenidades/disponibilidad/"


def test_delete_categoria_solo_desactiva_y_conserva_historico(admin_client):
    cat = admin_client.post(CATEGORIAS, {"nombre": "Obras", "color": "#112233"}, format="json").data
    com = admin_client.post(
        COMUNICADOS,
        {"titulo": "Obra fachada", "contenido": "Detalle de la obra.", "categoria": cat["id"]},
        format="json",
    ).data

    r = admin_client.delete(f"{CATEGORIAS}{cat['id']}/")
    assert r.status_code == 204

    # La fila NO se borró físicamente: solo quedó activa=False y el comunicado mantiene su categoría
    cat_db = CategoriaComunicado.objects.get(pk=cat["id"])
    assert cat_db.activa is False
    assert Comunicado.objects.get(pk=com["id"]).categoria_id == cat["id"]


def test_disponibilidad_requiere_permisos(client_anonimo, sin_rol_client, residente_client, piscina):
    assert client_anonimo.get(DISPONIBILIDAD).status_code == 401
    assert sin_rol_client.get(DISPONIBILIDAD).status_code == 403
    assert sin_rol_client.get(f"/api/v1/amenidades/{piscina.pk}/disponibilidad/").status_code == 403
    assert residente_client.get(DISPONIBILIDAD).status_code == 200


def test_publicacion_perezosa_no_atribuye_al_residente(admin_client, residente_client, residente):
    com = admin_client.post(COMUNICADOS, {"titulo": "Programado", "contenido": "Contenido"}, format="json").data
    admin_client.post(
        f"{COMUNICADOS}{com['id']}/programar/",
        {"fecha_programada": iso(timezone.now() + timedelta(hours=2))},
        format="json",
    )
    Comunicado.objects.filter(pk=com["id"]).update(fecha_programada=timezone.now() - timedelta(minutes=2))

    # El residente consulta avisos -> dispara publicación perezosa
    r = residente_client.get(AVISOS)
    assert r.status_code == 200 and r.data["count"] == 1

    # El evento de publicación en historial debe ser del sistema (usuario_id=None), no del residente
    evento_pub = ComunicadoHistorial.objects.filter(
        comunicado_id=com["id"], estado_anterior="PROGRAMADO"
    ).order_by("-id").first()
    assert evento_pub is not None
    assert evento_pub.usuario_id is None
    assert evento_pub.usuario_id != residente.pk


def test_bloqueo_cancelar_reservas_valida_pasado_cruces_y_conserva_mantenimiento(
    admin_client, residente, piscina, futuro, hacer_bloqueo, hacer_reserva
):
    # 1. Rechaza pasado aunque cancelar_reservas=True
    r_pasado = admin_client.post(
        BLOQUEOS,
        {
            "amenidad": piscina.pk,
            "fecha_inicio": iso(futuro(-10)),
            "fecha_fin": iso(futuro(-8)),
            "motivo": "Pasado",
            "cancelar_reservas": True,
        },
        format="json",
    )
    assert r_pasado.status_code == 400

    # 2. Rechaza bloqueo cruzado (409) aunque cancelar_reservas=True
    hacer_bloqueo(piscina, futuro(2), futuro(6))
    r_cruce = admin_client.post(
        BLOQUEOS,
        {
            "amenidad": piscina.pk,
            "fecha_inicio": futuro(4).isoformat(),
            "fecha_fin": futuro(8).isoformat(),
            "motivo": "Solapado",
            "cancelar_reservas": True,
        },
        format="json",
    )
    assert r_cruce.status_code == 409
    assert r_cruce.data["codigo"] == "bloqueo_cruzado"

    # 3. Conserva mantenimiento al cancelar reservas
    mant = admin_client.post(
        MANTENIMIENTOS,
        {
            "amenidad": piscina.pk,
            "titulo": "Cambio bombas",
            "fecha_inicio": iso(futuro(20)),
            "fecha_fin": iso(futuro(24)),
        },
        format="json",
    ).data
    reserva = hacer_reserva(piscina, residente, futuro(21), futuro(22))
    r_ok = admin_client.post(
        BLOQUEOS,
        {
            "amenidad": piscina.pk,
            "mantenimiento": mant["id"],
            "fecha_inicio": iso(futuro(20)),
            "fecha_fin": iso(futuro(24)),
            "motivo": "Mantenimiento bombas",
            "cancelar_reservas": True,
        },
        format="json",
    )
    assert r_ok.status_code == 201, r_ok.data
    assert r_ok.data["reservas_canceladas"] == [reserva.pk]
    assert Bloqueo.objects.get(pk=r_ok.data["id"]).mantenimiento_id == mant["id"]


def test_cancelar_bloqueo_finalizado_falla(admin_client, piscina, futuro, hacer_bloqueo):
    b = hacer_bloqueo(piscina, futuro(-5), futuro(-2))
    r = admin_client.post(f"{BLOQUEOS}{b.pk}/cancelar/")
    assert r.status_code == 400


def test_modificar_mantenimiento_rechaza_cambio_amenidad_con_bloqueos_activos(
    admin_client, piscina, salon, futuro
):
    mant = admin_client.post(
        MANTENIMIENTOS,
        {
            "amenidad": piscina.pk,
            "titulo": "Revisión",
            "fecha_inicio": iso(futuro(5)),
            "fecha_fin": iso(futuro(7)),
            "crear_bloqueo": True,
        },
        format="json",
    ).data
    r = admin_client.patch(f"{MANTENIMIENTOS}{mant['id']}/", {"amenidad": salon.pk}, format="json")
    assert r.status_code == 400 and "amenidad" in r.data
    assert Mantenimiento.objects.get(pk=mant["id"]).amenidad_id == piscina.pk

