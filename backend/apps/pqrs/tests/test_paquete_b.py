"""Pruebas de regresión del Paquete B para el módulo PQRS."""
import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APIClient

from apps.pqrs.models import PQR, TipoPQR
from apps.usuarios.models import Permiso, Rol, RolPermiso, Usuario, UsuarioRol

pytestmark = pytest.mark.django_db

CLAVE = "Clave12345!"


def _usuario_con_rol(username, doc, rol_codigo):
    u = Usuario.objects.create_user(
        username=username,
        email=f"{username}@example.com",
        password=CLAVE,
        nombres=username.capitalize(),
        apellidos="Prueba",
        numero_documento=doc,
    )
    UsuarioRol.objects.create(usuario=u, rol=Rol.objects.get(codigo=rol_codigo))
    return u


def _cliente_de(usuario):
    c = APIClient()
    c.force_authenticate(user=usuario)
    return c


@pytest.fixture
def tipo_peticion():
    return TipoPQR.objects.get(codigo="PETICION")


@pytest.fixture
def residente():
    return _usuario_con_rol("res_pqr_pb", "9101", "RESIDENTE")


@pytest.fixture
def residente_client(residente):
    return _cliente_de(residente)


@pytest.fixture
def responsable_pqr():
    return _usuario_con_rol("resp_pqr_pb", "9102", "RESPONSABLE_PQR")


@pytest.fixture
def responsable_pqr_client(responsable_pqr):
    return _cliente_de(responsable_pqr)


@pytest.fixture
def admin_pqr_client():
    return _cliente_de(_usuario_con_rol("adm_pqr_pb", "9103", "ADMIN"))


def _crear_pqr(cliente, tipo_peticion):
    r = cliente.post(
        "/api/v1/pqrs/",
        data={
            "tipo_id": tipo_peticion.id,
            "asunto": "Revisión de luminaria",
            "descripcion": "La luminaria del piso 3 parpadea desde ayer.",
        },
        format="json",
    )
    assert r.status_code == 201, r.data
    return r.data["id"]


def test_pqr_cerrada_y_anulada_bloquean_responsable_y_adjuntos(
    residente_client, admin_pqr_client, responsable_pqr, tipo_peticion, tmp_path
):
    pqr_id = _crear_pqr(residente_client, tipo_peticion)
    with override_settings(MEDIA_ROOT=tmp_path):
        subida = residente_client.post(
            f"/api/v1/pqrs/{pqr_id}/adjuntos/",
            data={"archivo": SimpleUploadedFile("evidencia.pdf", b"%PDF-1.4\nabc", content_type="application/pdf")},
            format="multipart",
        )
        assert subida.status_code == 201, subida.data
        adj_id = subida.data["id"]

        # Cerramos la PQR
        for estado in ("EN_REVISION", "EN_PROCESO", "ATENDIDA", "CERRADA"):
            assert admin_pqr_client.patch(
                f"/api/v1/pqrs/{pqr_id}/estado/", {"estado_codigo": estado}, format="json"
            ).status_code == 200

        # No admite asignar responsable ni crear/reemplazar/eliminar adjuntos
        assert admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/responsable/", {"responsable_id": responsable_pqr.pk}, format="json"
        ).status_code == 400
        assert admin_pqr_client.post(
            f"/api/v1/pqrs/{pqr_id}/adjuntos/",
            data={"archivo": SimpleUploadedFile("otro.pdf", b"%PDF-1.4\nxyz", content_type="application/pdf")},
            format="multipart",
        ).status_code == 400
        assert admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/adjuntos/{adj_id}/",
            data={"archivo": SimpleUploadedFile("nuevo.pdf", b"%PDF-1.4\nxyz", content_type="application/pdf")},
            format="multipart",
        ).status_code == 400
        assert admin_pqr_client.delete(f"/api/v1/pqrs/{pqr_id}/adjuntos/{adj_id}/").status_code == 400


def test_anulacion_rechaza_motivo_no_cadena(residente_client, tipo_peticion):
    pqr_id = _crear_pqr(residente_client, tipo_peticion)
    for invalido in (123456, ["motivo largo"], {"texto": "motivo"}):
        r = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/estado/",
            {"estado_codigo": "ANULADA", "motivo": invalido},
            format="json",
        )
        assert r.status_code == 400
    assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"


def test_responsable_pqr_no_auto_escala_prioridad_ni_edita_su_pqr_sin_asignacion(
    responsable_pqr_client, admin_pqr_client, tipo_peticion
):
    pqr_id = _crear_pqr(responsable_pqr_client, tipo_peticion)
    # Mientras está RECIBIDA y sin asignar, no puede auto-escalar prioridad a ALTA
    r_prio = responsable_pqr_client.patch(
        f"/api/v1/pqrs/{pqr_id}/", {"prioridad": "ALTA"}, format="json"
    )
    assert r_prio.status_code == 200
    assert PQR.objects.get(pk=pqr_id).prioridad == "MEDIA"

    # Cuando el admin la pasa a EN_REVISION (sin asignársela), tampoco puede editarla
    assert admin_pqr_client.patch(
        f"/api/v1/pqrs/{pqr_id}/estado/", {"estado_codigo": "EN_REVISION"}, format="json"
    ).status_code == 200
    r_edit = responsable_pqr_client.patch(
        f"/api/v1/pqrs/{pqr_id}/", {"asunto": "Intento tardío"}, format="json"
    )
    assert r_edit.status_code == 403


def test_rol_personalizado_con_pqr_radicar_ve_sus_propias_pqrs(tipo_peticion):
    rol = Rol.objects.create(codigo="INQUILINO_VIP", nombre="Inquilino VIP")
    RolPermiso.objects.create(rol=rol, permiso=Permiso.objects.get(codigo="pqr.radicar"))
    u = Usuario.objects.create_user(
        username="vip_pqr",
        email="vip_pqr@example.com",
        password=CLAVE,
        nombres="Inquilino",
        apellidos="VIP",
        numero_documento="889900",
    )
    UsuarioRol.objects.create(usuario=u, rol=rol)
    client = APIClient()
    client.force_authenticate(user=u)

    pqr_id = _crear_pqr(client, tipo_peticion)
    listado = client.get("/api/v1/pqrs/")
    assert listado.status_code == 200
    items = listado.data["results"] if isinstance(listado.data, dict) else listado.data
    assert [x["id"] for x in items] == [pqr_id]
