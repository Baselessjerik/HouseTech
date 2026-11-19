"""Pruebas de regresión del Paquete B para reservas, amenidades y reportes."""
import csv
import datetime as dt
import io

import pytest
from django.utils import timezone

from apps.inmuebles.models import Inmueble, InmuebleUsuario
from apps.reservas import services
from apps.reservas.models import Reserva
from apps.usuarios.models import Permiso, Rol, RolPermiso, Usuario, UsuarioRol

from .conftest import CLAVE, cuerpo, en_dias

pytestmark = pytest.mark.django_db

RESERVAS = "/api/v1/reservas/"
AMENIDADES = "/api/v1/amenidades/"
AGENDA = "/api/v1/agenda/"
HISTORICO = "/api/v1/reportes/reservas/"


def test_residente_con_dos_inmuebles_debe_seleccionar_uno(residente_client, residente, copropiedad, salon):
    inm2 = Inmueble.objects.create(copropiedad=copropiedad, numero="102", codigo_interno="T1-102")
    InmuebleUsuario.objects.create(inmueble=inm2, usuario=residente, tipo_relacion="PROPIETARIO")

    # Sin enviar inmueble -> 400 para evitar evadir cupo mensual por inmueble
    r = residente_client.post(RESERVAS, cuerpo(salon), format="json")
    assert r.status_code == 400 and "inmueble" in r.data

    # Enviando explícitamente su segundo inmueble -> 201
    r_ok = residente_client.post(RESERVAS, cuerpo(salon, inmueble=inm2.pk), format="json")
    assert r_ok.status_code == 201, r_ok.data
    assert r_ok.data["inmueble_codigo"] == "T1-102"


def test_residente_no_puede_reservar_sobre_inmueble_inactivo(residente_client, residente, salon):
    inm = InmuebleUsuario.objects.filter(usuario=residente, fecha_fin__isnull=True).first().inmueble
    inm.activo = False
    inm.save(update_fields=["activo"])

    r = residente_client.post(RESERVAS, cuerpo(salon, inmueble=inm.pk), format="json")
    assert r.status_code == 400 and "inmueble" in r.data


def test_amenidad_serializer_rechaza_copropiedad_no_numerica_con_400(admin_client):
    r = admin_client.post(
        AMENIDADES,
        {"copropiedad": "no-es-numero", "nombre": "Gimnasio", "capacidad": 10},
        format="json",
    )
    assert r.status_code == 400


def test_verificar_no_permite_consultar_inmueble_ajeno(residente_client, otro_residente, salon):
    inm_ajeno = InmuebleUsuario.objects.filter(usuario=otro_residente, fecha_fin__isnull=True).first().inmueble
    r = residente_client.get(
        f"{AMENIDADES}{salon.pk}/verificar/",
        {
            "inicio": en_dias(5, 10).isoformat(),
            "fin": en_dias(5, 12).isoformat(),
            "inmueble": inm_ajeno.pk,
        },
    )
    assert r.status_code == 400 and "inmueble" in r.data


def test_agenda_no_filtra_estados_privados_ajenos(residente_client, otro_client, admin_client, salon):
    # Otro residente solicita y el admin la rechaza
    rid = otro_client.post(RESERVAS, cuerpo(salon, dias=5, desde=10, hasta=12), format="json").data["id"]
    assert admin_client.post(f"{RESERVAS}{rid}/rechazar/", {"motivo": "No disponible"}, format="json").status_code == 200

    hoy = timezone.localdate()
    r = residente_client.get(
        AGENDA,
        {
            "desde": hoy.isoformat(),
            "hasta": (hoy + dt.timedelta(days=20)).isoformat(),
            "estado": "RECHAZADA",
        },
    )
    assert r.status_code == 200
    assert r.data["eventos"] == []


def test_historico_csv_neutraliza_formulas(admin_client, residente, salon):
    Reserva.objects.create(
        amenidad=salon,
        usuario=residente,
        num_personas=5,
        estado=services.estado_reserva("CANCELADA"),
        fecha_inicio=en_dias(-2, 10),
        fecha_fin=en_dias(-2, 12),
        motivo_cancelacion="=CMD|' /C calc'!A0",
    )
    r = admin_client.get(HISTORICO, {"formato": "csv"})
    assert r.status_code == 200
    filas = list(csv.reader(io.StringIO(r.content.decode("utf-8-sig"))))
    assert filas[1][-1].startswith("'=CMD")


def test_rol_personalizado_amenidades_gestionar_puede_crear_reserva(cliente_de, salon):
    rol = Rol.objects.create(codigo="GESTOR_ZONAS", nombre="Gestor Zonas")
    RolPermiso.objects.create(rol=rol, permiso=Permiso.objects.get(codigo="amenidades.gestionar"))
    u = Usuario.objects.create_user(
        username="gestor_zonas",
        email="gestor_zonas@example.com",
        password=CLAVE,
        nombres="Gestor",
        apellidos="Zonas",
        numero_documento="778899",
    )
    UsuarioRol.objects.create(usuario=u, rol=rol)
    client = cliente_de("gestor_zonas")

    r = client.post(RESERVAS, cuerpo(salon), format="json")
    assert r.status_code == 201, r.data

