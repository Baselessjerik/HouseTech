import pytest
from django.core.files.uploadedfile import SimpleUploadedFile

from apps.comunicados import services
from apps.comunicados.models import ComunicadoAdjunto

pytestmark = pytest.mark.django_db

COMUNICADOS = "/api/v1/comunicados/"
AVISOS = "/api/v1/avisos/"


def archivo(nombre="reglamento.pdf", contenido=b"%PDF-1.4 contenido de prueba"):
    return SimpleUploadedFile(nombre, contenido)


def nuevo(admin_client, **extra):
    r = admin_client.post(COMUNICADOS, {"titulo": "Con adjunto", "contenido": "Mira el archivo.", **extra}, format="json")
    assert r.status_code == 201, r.data
    return r.data["id"]


def subir(admin_client, pk, **kw):
    return admin_client.post(f"{COMUNICADOS}{pk}/adjuntos/", {"archivo": archivo(**kw)}, format="multipart")


def test_admin_adjunta_un_archivo_y_aparece_en_el_comunicado(admin_client):
    pk = nuevo(admin_client)
    r = subir(admin_client, pk)
    assert r.status_code == 201, r.data
    assert r.data["nombre_original"] == "reglamento.pdf"
    assert r.data["tipo_contenido"] == "application/pdf"
    assert r.data["tamano_bytes"] == len(b"%PDF-1.4 contenido de prueba")
    detalle = admin_client.get(f"{COMUNICADOS}{pk}/").data
    assert [a["nombre_original"] for a in detalle["adjuntos"]] == ["reglamento.pdf"]
    assert "contenido" not in detalle["adjuntos"][0]  # el binario nunca viaja en el JSON


def test_residente_no_puede_adjuntar(residente_client, admin_client):
    pk = nuevo(admin_client)
    r = residente_client.post(f"{COMUNICADOS}{pk}/adjuntos/", {"archivo": archivo()}, format="multipart")
    assert r.status_code == 403


def test_sin_archivo_devuelve_400(admin_client):
    pk = nuevo(admin_client)
    r = admin_client.post(f"{COMUNICADOS}{pk}/adjuntos/", {}, format="multipart")
    assert r.status_code == 400 and "archivo" in r.data


@pytest.mark.parametrize("nombre", ["virus.exe", "pagina.html", "script.js", "sin_extension", "logo.svg"])
def test_rechaza_tipos_no_permitidos(admin_client, nombre):
    pk = nuevo(admin_client)
    r = subir(admin_client, pk, nombre=nombre)
    assert r.status_code == 400 and "archivo" in r.data
    assert not ComunicadoAdjunto.objects.exists()


def test_rechaza_archivo_vacio(admin_client):
    pk = nuevo(admin_client)
    assert subir(admin_client, pk, contenido=b"").status_code == 400


def test_rechaza_archivo_muy_grande(admin_client, monkeypatch):
    monkeypatch.setattr(services, "MAX_BYTES_ADJUNTO", 10)
    pk = nuevo(admin_client)
    r = subir(admin_client, pk, contenido=b"x" * 11)
    assert r.status_code == 400 and "supera" in str(r.data["archivo"])


def test_maximo_de_archivos_por_comunicado(admin_client, monkeypatch):
    monkeypatch.setattr(services, "MAX_ADJUNTOS", 2)
    pk = nuevo(admin_client)
    assert subir(admin_client, pk, nombre="a.pdf").status_code == 201
    assert subir(admin_client, pk, nombre="b.pdf").status_code == 201
    r = subir(admin_client, pk, nombre="c.pdf")
    assert r.status_code == 400 and "máximo" in str(r.data["archivo"])


def test_el_nombre_se_limpia_de_rutas(admin_client):
    pk = nuevo(admin_client)
    r = subir(admin_client, pk, nombre="../../etc/informe.pdf")
    assert r.status_code == 201
    assert r.data["nombre_original"] == "informe.pdf"


def test_quitar_adjunto(admin_client):
    pk = nuevo(admin_client)
    adj = subir(admin_client, pk).data["id"]
    assert admin_client.delete(f"{COMUNICADOS}{pk}/adjuntos/{adj}/").status_code == 204
    assert admin_client.delete(f"{COMUNICADOS}{pk}/adjuntos/{adj}/").status_code == 404
    assert admin_client.get(f"{COMUNICADOS}{pk}/").data["adjuntos"] == []


def test_no_se_adjunta_ni_quita_en_un_comunicado_archivado(admin_client):
    pk = nuevo(admin_client)
    adj = subir(admin_client, pk).data["id"]
    admin_client.post(f"{COMUNICADOS}{pk}/archivar/")
    assert subir(admin_client, pk, nombre="otro.pdf").status_code == 400
    assert admin_client.delete(f"{COMUNICADOS}{pk}/adjuntos/{adj}/").status_code == 400


# ------------------------------------------------------------------------------ descarga
def test_residente_descarga_el_adjunto_de_un_aviso_publicado(admin_client, residente_client):
    pk = nuevo(admin_client)
    adj = subir(admin_client, pk, contenido=b"contenido real").data["id"]
    admin_client.post(f"{COMUNICADOS}{pk}/publicar/")

    aviso = residente_client.get(f"{AVISOS}{pk}/").data
    assert aviso["adjuntos"][0]["id"] == adj

    enlace = residente_client.post(f"{AVISOS}{pk}/adjuntos/{adj}/enlace/")
    assert enlace.status_code == 200, enlace.data
    assert enlace.data["expira_en_segundos"] == services.SEGUNDOS_ENLACE

    # el enlace no necesita encabezado de sesión (lo abre el navegador)
    from rest_framework.test import APIClient

    r = APIClient().get(enlace.data["url"])
    assert r.status_code == 200
    assert b"".join(r.streaming_content if r.streaming else [r.content]) == b"contenido real"
    assert "attachment" in r["Content-Disposition"] and "reglamento.pdf" in r["Content-Disposition"]
    assert r["X-Content-Type-Options"] == "nosniff"


def test_residente_no_obtiene_enlace_de_un_borrador(admin_client, residente_client):
    pk = nuevo(admin_client)
    adj = subir(admin_client, pk).data["id"]
    assert residente_client.post(f"{AVISOS}{pk}/adjuntos/{adj}/enlace/").status_code == 404


def test_otro_residente_no_obtiene_enlace_si_no_es_destinatario(
    admin_client, residente, residente2_client
):
    pk = nuevo(admin_client, audiencia="USUARIOS", destinatarios=[residente.pk])
    adj = subir(admin_client, pk).data["id"]
    admin_client.post(f"{COMUNICADOS}{pk}/publicar/")
    assert residente2_client.post(f"{AVISOS}{pk}/adjuntos/{adj}/enlace/").status_code == 404


def test_admin_obtiene_enlace_aun_en_borrador(admin_client):
    pk = nuevo(admin_client)
    adj = subir(admin_client, pk).data["id"]
    r = admin_client.post(f"{COMUNICADOS}{pk}/adjuntos/{adj}/enlace/")
    assert r.status_code == 200 and r.data["url"].startswith("http")


def test_enlace_invalido_o_vencido(admin_client, monkeypatch):
    from rest_framework.test import APIClient

    pk = nuevo(admin_client)
    adj = subir(admin_client, pk).data["id"]
    url = admin_client.post(f"{COMUNICADOS}{pk}/adjuntos/{adj}/enlace/").data["url"]
    assert APIClient().get("/api/v1/adjuntos/descargar/token-falso/").status_code == 404
    monkeypatch.setattr(services, "SEGUNDOS_ENLACE", -1)  # ya vencido
    assert APIClient().get(url).status_code == 404


def test_enlace_de_un_adjunto_inexistente(admin_client):
    pk = nuevo(admin_client)
    assert admin_client.post(f"{COMUNICADOS}{pk}/adjuntos/99999/enlace/").status_code == 404
