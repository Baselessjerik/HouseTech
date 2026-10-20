from datetime import timedelta

import pytest
from django.core.management import call_command
from django.utils import timezone

from apps.comunicados.models import Comunicado, ComunicadoHistorial, Notificacion
from apps.core.models import Auditoria
from apps.usuarios.models import Rol

from .conftest import iso

pytestmark = pytest.mark.django_db

COMUNICADOS = "/api/v1/comunicados/"
AVISOS = "/api/v1/avisos/"
CATEGORIAS = "/api/v1/categorias-comunicado/"


def nuevo(admin_client, **extra):
    payload = {"titulo": "Corte de agua", "contenido": "Jueves de 8 a 2.", **extra}
    r = admin_client.post(COMUNICADOS, payload, format="json")
    assert r.status_code == 201, r.data
    return r.data


def publicar(admin_client, pk):
    r = admin_client.post(f"{COMUNICADOS}{pk}/publicar/")
    assert r.status_code == 200, r.data
    return r.data


# ------------------------------------------------------------------ permisos y creación
def test_residente_no_gestiona(residente_client, client_anonimo):
    assert client_anonimo.get(COMUNICADOS).status_code == 401
    assert residente_client.get(COMUNICADOS).status_code == 403
    assert residente_client.post(COMUNICADOS, {"titulo": "x", "contenido": "y"}, format="json").status_code == 403


def test_crear_queda_en_borrador_con_autor(admin_client, admin):
    c = nuevo(admin_client)
    assert c["estado"] == "BORRADOR" and c["audiencia"] == "TODOS" and c["autor"] == admin.pk
    log = Auditoria.objects.filter(tabla="comunicados", operacion="INSERT").first()
    assert log.usuario_id == admin.pk


def test_audiencia_rol_exige_rol(admin_client):
    r = admin_client.post(COMUNICADOS, {"titulo": "a", "contenido": "b", "audiencia": "ROL"}, format="json")
    assert r.status_code == 400 and "rol_destino" in r.data


def test_audiencia_usuarios_exige_destinatarios_validos(admin_client, residente):
    base = {"titulo": "a", "contenido": "b", "audiencia": "USUARIOS"}
    assert admin_client.post(COMUNICADOS, base, format="json").status_code == 400
    assert admin_client.post(COMUNICADOS, {**base, "destinatarios": [999999]}, format="json").status_code == 400
    r = admin_client.post(COMUNICADOS, {**base, "destinatarios": [residente.pk]}, format="json")
    assert r.status_code == 201 and r.data["destinatarios"] == [residente.pk]


def test_expiracion_en_el_pasado_se_rechaza(admin_client):
    pasado = iso(timezone.now() - timedelta(days=1))
    r = admin_client.post(COMUNICADOS, {"titulo": "a", "contenido": "b", "fecha_expiracion": pasado}, format="json")
    assert r.status_code == 400 and "fecha_expiracion" in r.data


# --------------------------------------------------------------------- publicar (RF11, RF16)
def test_publicar_notifica_y_aparece_en_avisos(admin_client, residente_client, residente, sin_rol):
    c = nuevo(admin_client)
    assert residente_client.get(AVISOS).data["count"] == 0  # borrador: invisible
    out = publicar(admin_client, c["id"])
    assert out["estado"] == "PUBLICADO" and out["fecha_publicacion"]
    avisos = residente_client.get(AVISOS).data
    assert avisos["count"] == 1 and avisos["results"][0]["titulo"] == "Corte de agua"
    n = Notificacion.objects.get(usuario=residente, tipo="COMUNICADO")
    assert n.referencia_tipo == "comunicado" and n.referencia_id == c["id"]
    assert not Notificacion.objects.filter(usuario=sin_rol).exists()


def test_no_se_publica_dos_veces(admin_client):
    c = nuevo(admin_client)
    publicar(admin_client, c["id"])
    assert admin_client.post(f"{COMUNICADOS}{c['id']}/publicar/").status_code == 400


def test_sin_permiso_ver_no_accede_a_avisos(sin_rol_client):
    assert sin_rol_client.get(AVISOS).status_code == 403


# --------------------------------------------------------------- visibilidad por audiencia
def test_audiencia_rol(admin_client, residente_client):
    rol_admin = Rol.objects.get(codigo="ADMIN")
    c = nuevo(admin_client, audiencia="ROL", rol_destino=rol_admin.pk)
    publicar(admin_client, c["id"])
    assert residente_client.get(AVISOS).data["count"] == 0
    rol_res = Rol.objects.get(codigo="RESIDENTE")
    c2 = nuevo(admin_client, titulo="Para residentes", audiencia="ROL", rol_destino=rol_res.pk)
    publicar(admin_client, c2["id"])
    assert [a["titulo"] for a in residente_client.get(AVISOS).data["results"]] == ["Para residentes"]


def test_audiencia_usuarios(admin_client, residente, residente_client, residente2_client, residente2):
    c = nuevo(admin_client, audiencia="USUARIOS", destinatarios=[residente.pk])
    publicar(admin_client, c["id"])
    assert residente_client.get(AVISOS).data["count"] == 1
    assert residente2_client.get(AVISOS).data["count"] == 0
    assert Notificacion.objects.filter(tipo="COMUNICADO", usuario=residente).count() == 1
    assert not Notificacion.objects.filter(tipo="COMUNICADO", usuario=residente2).exists()
    assert residente2_client.get(f"{AVISOS}{c['id']}/").status_code == 404


def test_comunicado_expirado_no_se_muestra(admin_client, residente_client):
    c = nuevo(admin_client)
    publicar(admin_client, c["id"])
    Comunicado.objects.filter(pk=c["id"]).update(fecha_expiracion=timezone.now() - timedelta(minutes=1))
    assert residente_client.get(AVISOS).data["count"] == 0
    assert admin_client.get(f"{COMUNICADOS}{c['id']}/").status_code == 200  # el admin sí lo ve


def test_archivado_no_se_muestra_ni_edita(admin_client, residente_client):
    c = nuevo(admin_client)
    publicar(admin_client, c["id"])
    assert admin_client.post(f"{COMUNICADOS}{c['id']}/archivar/").data["estado"] == "ARCHIVADO"
    assert residente_client.get(AVISOS).data["count"] == 0
    assert admin_client.patch(f"{COMUNICADOS}{c['id']}/", {"titulo": "z"}, format="json").status_code == 400


# ----------------------------------------------------------------- edición e historial (RF10, RF15)
def test_editar_publicado_guarda_historial(admin_client, admin):
    c = nuevo(admin_client)
    publicar(admin_client, c["id"])
    r = admin_client.patch(f"{COMUNICADOS}{c['id']}/", {"titulo": "Título corregido"}, format="json")
    assert r.status_code == 200 and r.data["titulo"] == "Título corregido"
    hist = admin_client.get(f"{COMUNICADOS}{c['id']}/historial/").data
    assert len(hist) == 2  # cambio de estado + cambio de título
    assert hist[0]["titulo_anterior"] == "Corte de agua" and hist[0]["usuario"] == admin.pk
    assert ComunicadoHistorial.objects.filter(comunicado_id=c["id"]).count() == 2


def test_cambiar_audiencia_limpia_el_rol(admin_client):
    rol = Rol.objects.get(codigo="RESIDENTE")
    c = nuevo(admin_client, audiencia="ROL", rol_destino=rol.pk)
    r = admin_client.patch(f"{COMUNICADOS}{c['id']}/", {"audiencia": "TODOS"}, format="json")
    assert r.status_code == 200 and r.data["rol_destino"] is None


# ---------------------------------------------------------------- programar (RF13)
def test_programar_exige_fecha_futura(admin_client):
    c = nuevo(admin_client)
    pasado = iso(timezone.now() - timedelta(hours=1))
    assert admin_client.post(f"{COMUNICADOS}{c['id']}/programar/", {"fecha_programada": pasado}, format="json").status_code == 400
    futuro = iso(timezone.now() + timedelta(hours=3))
    r = admin_client.post(f"{COMUNICADOS}{c['id']}/programar/", {"fecha_programada": futuro}, format="json")
    assert r.status_code == 200 and r.data["estado"] == "PROGRAMADO"


def test_comando_publica_los_programados_vencidos(admin_client, residente, residente_client):
    c = nuevo(admin_client)
    admin_client.post(
        f"{COMUNICADOS}{c['id']}/programar/",
        {"fecha_programada": iso(timezone.now() + timedelta(hours=3))}, format="json",
    )
    call_command("publicar_comunicados_programados")  # aún no es la hora
    assert Comunicado.objects.get(pk=c["id"]).estado == "PROGRAMADO"

    Comunicado.objects.filter(pk=c["id"]).update(fecha_programada=timezone.now() - timedelta(minutes=1))
    call_command("publicar_comunicados_programados")
    call_command("publicar_comunicados_programados")  # idempotente
    assert Comunicado.objects.get(pk=c["id"]).estado == "PUBLICADO"
    assert Notificacion.objects.filter(usuario=residente, tipo="COMUNICADO").count() == 1
    assert residente_client.get(AVISOS).data["count"] == 1


def test_publicacion_perezosa_al_consultar_avisos(admin_client, residente_client):
    c = nuevo(admin_client)
    admin_client.post(
        f"{COMUNICADOS}{c['id']}/programar/",
        {"fecha_programada": iso(timezone.now() + timedelta(hours=3))}, format="json",
    )
    Comunicado.objects.filter(pk=c["id"]).update(fecha_programada=timezone.now() - timedelta(minutes=1))
    assert residente_client.get(AVISOS).data["count"] == 1


# ----------------------------------------------------------------------- consulta (RF14)
def test_busqueda_y_filtro_por_categoria(admin_client, residente_client):
    cat = admin_client.post(CATEGORIAS, {"nombre": "Piscina", "color": "#00AAFF"}, format="json").data
    a = nuevo(admin_client, titulo="Horario de piscina", categoria=cat["id"])
    b = nuevo(admin_client, titulo="Otro aviso")
    publicar(admin_client, a["id"])
    publicar(admin_client, b["id"])
    assert residente_client.get(AVISOS, {"search": "piscina"}).data["count"] == 1
    r = residente_client.get(AVISOS, {"categoria": cat["id"]}).data
    assert r["count"] == 1 and r["results"][0]["categoria_color"] == "#00AAFF"


def test_filtro_por_estado_en_gestion(admin_client):
    a = nuevo(admin_client)
    nuevo(admin_client, titulo="Otro")
    publicar(admin_client, a["id"])
    assert admin_client.get(COMUNICADOS, {"estado": "PUBLICADO"}).data["count"] == 1
    assert admin_client.get(COMUNICADOS).data["count"] == 2


def test_no_existe_delete(admin_client):
    c = nuevo(admin_client)
    assert admin_client.delete(f"{COMUNICADOS}{c['id']}/").status_code == 405


# ------------------------------------------------------------------------- categorías (RF12)
def test_crud_categorias(admin_client, residente_client):
    r = admin_client.post(CATEGORIAS, {"nombre": "Deportes", "color": "#112233"}, format="json")
    assert r.status_code == 201, r.data
    pk = r.data["id"]
    assert admin_client.post(CATEGORIAS, {"nombre": "deportes"}, format="json").status_code == 400  # duplicado
    assert admin_client.post(CATEGORIAS, {"nombre": "X", "color": "rojo"}, format="json").status_code == 400
    assert admin_client.patch(f"{CATEGORIAS}{pk}/", {"activa": False}, format="json").status_code == 200
    # un residente puede leer solo las activas y no puede escribir
    nombres = [c["nombre"] for c in residente_client.get(CATEGORIAS).data]
    assert "Deportes" not in nombres and "General" in nombres
    assert residente_client.post(CATEGORIAS, {"nombre": "Z"}, format="json").status_code == 403
    assert admin_client.delete(f"{CATEGORIAS}{pk}/").status_code == 204


def test_no_se_asigna_categoria_inactiva(admin_client):
    cat = admin_client.post(CATEGORIAS, {"nombre": "Vieja", "activa": False}, format="json").data
    r = admin_client.post(COMUNICADOS, {"titulo": "a", "contenido": "b", "categoria": cat["id"]}, format="json")
    assert r.status_code == 400 and "categoria" in r.data


# --------------------------------------------------- opciones y semillas (integridad)
def test_opciones_roles_y_busqueda_usuarios(admin_client, residente_client, residente, residente2):
    assert residente_client.get("/api/v1/comunicados-opciones/roles/").status_code == 403
    assert residente_client.get("/api/v1/comunicados-opciones/usuarios/").status_code == 403

    r_roles = admin_client.get("/api/v1/comunicados-opciones/roles/")
    assert r_roles.status_code == 200
    codigos = {x["codigo"] for x in r_roles.data}
    assert {"ADMIN", "RESIDENTE", "RESPONSABLE_PQR"} <= codigos

    r_users = admin_client.get("/api/v1/comunicados-opciones/usuarios/", {"search": "rosa"})
    assert r_users.status_code == 200
    assert [u["username"] for u in r_users.data] == ["rosa"]

    r_ids = admin_client.get("/api/v1/comunicados-opciones/usuarios/", {"ids": f"{residente.pk},{residente2.pk}"})
    assert r_ids.status_code == 200
    assert {u["id"] for u in r_ids.data} == {residente.pk, residente2.pk}


def test_seed_demo_y_seed_modulo2_idempotentes_e_integridad(db, settings):
    settings.DEBUG = True
    call_command("seed_demo")
    call_command("seed_modulo2")
    call_command("seed_modulo2")  # idempotente: no duplica registros

    assert Comunicado.objects.filter(titulo="Corte de agua programado", estado="PUBLICADO").count() == 1
    assert Comunicado.objects.filter(titulo="Jornada de fumigación", estado="PROGRAMADO").count() == 1
    assert Auditoria.objects.filter(tabla="comunicados").exists()
    assert Auditoria.objects.filter(tabla="mantenimientos").exists()
    assert Auditoria.objects.filter(tabla="bloqueos_amenidad").exists()
