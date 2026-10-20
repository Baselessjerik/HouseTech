import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APIClient

from apps.core.models import Estado
from apps.pqrs.models import PQR, PQRAdjunto, TipoPQR
from apps.usuarios.models import Rol, Usuario, UsuarioRol

CLAVE = "Clave12345!"


@pytest.fixture
def residente():
    """Crea un usuario residente con el rol RESIDENTE y permiso pqr.radicar."""
    u = Usuario.objects.create_user(
        username="residente_pqr",
        email="residente_pqr@example.com",
        password=CLAVE,
        nombres="Juan",
        apellidos="Pérez",
        numero_documento="1098765432",
    )
    rol = Rol.objects.get(codigo="RESIDENTE")
    UsuarioRol.objects.create(usuario=u, rol=rol)
    return u


@pytest.fixture
def residente_client(residente):
    """Cliente HTTP autenticado con JWT como el residente."""
    c = APIClient()
    r = c.post("/api/v1/auth/login/", {"username": "residente_pqr", "password": CLAVE}, format="json")
    assert r.status_code == 200, r.data
    c.credentials(HTTP_AUTHORIZATION=f"Bearer {r.data['access']}")
    return c


@pytest.fixture
def responsable_pqr_client():
    """Cliente autenticado con el permiso de gestión asignado al responsable PQR."""
    usuario = Usuario.objects.create_user(
        username="responsable_ciclo_pqr",
        email="responsable_ciclo_pqr@example.com",
        password=CLAVE,
        nombres="Responsable",
        apellidos="PQR",
        numero_documento="3098765432",
    )
    UsuarioRol.objects.create(
        usuario=usuario,
        rol=Rol.objects.get(codigo="RESPONSABLE_PQR"),
    )
    cliente = APIClient()
    cliente.force_authenticate(user=usuario)
    return cliente


@pytest.fixture
def admin_pqr_client():
    """Cliente administrador; su rol también tiene permiso pqr.gestionar."""
    usuario = Usuario.objects.create_user(
        username="admin_ciclo_pqr",
        email="admin_ciclo_pqr@example.com",
        password=CLAVE,
        nombres="Admin",
        apellidos="PQR",
        numero_documento="4098765432",
    )
    UsuarioRol.objects.create(
        usuario=usuario,
        rol=Rol.objects.get(codigo="ADMIN"),
    )
    cliente = APIClient()
    cliente.force_authenticate(user=usuario)
    return cliente


@pytest.fixture
def tipo_peticion():
    """Obtiene el tipo Petición precargado por el esquema de pruebas."""
    return TipoPQR.objects.get(codigo="PETICION")


@pytest.mark.django_db
class TestRegistroPQR:
    """Comprueba el registro, ciclo de estados, permisos y adjuntos de PQR."""

    def _crear_pqr(self, residente_client, tipo_peticion):
        """Crea una PQR válida para usarla en pruebas de adjuntos."""
        respuesta = residente_client.post(
            "/api/v1/pqrs/",
            data={
                "tipo_id": tipo_peticion.id,
                "asunto": "Revisión de filtración",
                "descripcion": "Hay una filtración de agua en el pasillo.",
                "prioridad": "MEDIA",
            },
            format="json",
        )
        assert respuesta.status_code == 201, respuesta.data
        return respuesta.data["id"]

    def test_catalogo_tipos_pqr(self, residente_client):
        """El residente puede obtener los tipos disponibles para el formulario."""
        res = residente_client.get("/api/v1/pqrs/tipos/")
        assert res.status_code == 200
        codigos = [item["codigo"] for item in res.data]
        assert "PETICION" in codigos
        assert "QUEJA" in codigos
        assert "RECLAMO" in codigos

    def test_radicar_pqr_exitoso(self, residente_client, residente, tipo_peticion):
        """Un residente registra una PQR mediante el formulario y obtiene radicado."""
        payload = {
            "tipo_id": tipo_peticion.id,
            "asunto": "Solicitud de copia de reglamento",
            "descripcion": "Requiero una copia digitalizada del reglamento de propiedad horizontal actualizado.",
            "prioridad": "MEDIA",
        }
        res = residente_client.post("/api/v1/pqrs/", data=payload, format="json")

        assert res.status_code == 201
        data = res.data
        assert data["radicado"] is not None
        assert data["radicado"].startswith("PET-")
        assert data["estado_codigo"] == "RECIBIDA"
        assert data["asunto"] == payload["asunto"]

        # Verificar persistencia en base de datos
        pqr_db = PQR.objects.get(id=data["id"])
        assert pqr_db.solicitante == residente
        assert pqr_db.estado.codigo == "RECIBIDA"

    def test_residente_consulta_estado_actual_de_su_pqr(
        self,
        residente_client,
        tipo_peticion,
    ):
        """El detalle devuelve el estado actual de una PQR propia."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = residente_client.get(f"/api/v1/pqrs/{pqr_id}/")

        assert respuesta.status_code == 200
        assert respuesta.data["id"] == pqr_id
        assert respuesta.data["estado_codigo"] == "RECIBIDA"
        assert respuesta.data["estado_nombre"]

    def test_responsable_pqr_avanza_solicitud_por_todo_el_ciclo(
        self,
        residente_client,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """El responsable recorre el flujo y la base registra cierre e historial."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        for codigo_estado in (
            "EN_REVISION",
            "EN_PROCESO",
            "ATENDIDA",
            "CERRADA",
        ):
            respuesta = responsable_pqr_client.patch(
                f"/api/v1/pqrs/{pqr_id}/estado/",
                data={"estado_codigo": codigo_estado},
                format="json",
            )

            assert respuesta.status_code == 200, respuesta.data
            assert respuesta.data["estado_codigo"] == codigo_estado

        pqr = PQR.objects.get(pk=pqr_id)
        assert pqr.fecha_cierre is not None
        assert pqr.historial.count() == 5

    def test_admin_puede_cambiar_estado_de_pqr(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """El rol administrador, que posee pqr.gestionar, puede avanzar el estado."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/estado/",
            data={"estado_codigo": "EN_REVISION"},
            format="json",
        )

        assert respuesta.status_code == 200, respuesta.data
        assert respuesta.data["estado_codigo"] == "EN_REVISION"

    def test_gestor_no_puede_saltar_estados(
        self,
        residente_client,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """Rechaza el salto de RECIBIDA a EN_PROCESO."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = responsable_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/estado/",
            data={"estado_codigo": "EN_PROCESO"},
            format="json",
        )

        assert respuesta.status_code == 400
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    def test_residente_no_puede_cambiar_estado_de_pqr(
        self,
        residente_client,
        tipo_peticion,
    ):
        """El permiso de radicación no permite modificar el estado."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/estado/",
            data={"estado_codigo": "EN_REVISION"},
            format="json",
        )

        assert respuesta.status_code == 403
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    def test_validacion_campos_cortos(self, residente_client, tipo_peticion):
        """Valida que no permita asuntos o descripciones vacías o muy breves."""
        payload = {
            "tipo_id": tipo_peticion.id,
            "asunto": "Hola",  # menor a 5 caracteres
            "descripcion": "Ayuda",  # menor a 10 caracteres
        }
        res = residente_client.post("/api/v1/pqrs/", data=payload, format="json")
        assert res.status_code == 400
        assert "asunto" in res.data
        assert "descripcion" in res.data

    def test_no_autenticado_no_puede_radicar(self):
        """Peticiones sin token JWT deben ser rechazadas con 401 Unauthorized."""
        client = APIClient()
        res = client.post("/api/v1/pqrs/", data={}, format="json")
        assert res.status_code == 401

    @pytest.mark.parametrize(
        ("codigo", "prefijo"),
        [
            ("PETICION", "PET"),
            ("QUEJA", "QUE"),
            ("RECLAMO", "REC"),
        ],
    )
        
    def test_radicado_corresponde_al_tipo(
        self,
        residente_client,
        codigo,
        prefijo,
    ):
        """El radicado generado usa el prefijo de la clasificación elegida."""
        tipo = TipoPQR.objects.get(codigo=codigo)

        payload = {
            "tipo_id": tipo.id,
            "asunto": "Consulta sobre la copropiedad",
            "descripcion": "Solicito revisar esta situación con detalle.",
            "prioridad": "MEDIA",
        }

        respuesta = residente_client.post(
            "/api/v1/pqrs/",
            data=payload,
            format="json",
        )

        assert respuesta.status_code == 201
        assert respuesta.data["tipo"]["codigo"] == codigo
        assert respuesta.data["radicado"].startswith(f"{prefijo}-")

    def test_dos_pqrs_reciben_radicados_distintos(
        self,
        residente_client,
    ):
        """El consecutivo de base de datos no se repite entre solicitudes."""
        tipo_peticion = TipoPQR.objects.get(codigo="PETICION")
        tipo_queja = TipoPQR.objects.get(codigo="QUEJA")

        payload_base = {
            "asunto": "Consulta sobre la copropiedad",
            "descripcion": "Solicito revisar esta situación con detalle.",
            "prioridad": "MEDIA",
        }

        primera = residente_client.post(
            "/api/v1/pqrs/",
            data={**payload_base, "tipo_id": tipo_peticion.id},
            format="json",
        )
        segunda = residente_client.post(
            "/api/v1/pqrs/",
            data={**payload_base, "tipo_id": tipo_queja.id},
            format="json",
        )

        assert primera.status_code == 201
        assert segunda.status_code == 201
        assert primera.data["radicado"] != segunda.data["radicado"]

    def test_no_se_puede_cambiar_tipo_despues_de_radicada(
        self,
        residente_client,
    ):
        """Una edición no debe dejar el tipo y el prefijo inconsistentes."""
        tipo_peticion = TipoPQR.objects.get(codigo="PETICION")
        tipo_queja = TipoPQR.objects.get(codigo="QUEJA")

        creacion = residente_client.post(
            "/api/v1/pqrs/",
            data={
                "tipo_id": tipo_peticion.id,
                "asunto": "Consulta sobre la copropiedad",
                "descripcion": "Solicito revisar esta situación con detalle.",
                "prioridad": "MEDIA",
            },
            format="json",
        )

        assert creacion.status_code == 201

        edicion = residente_client.patch(
            f"/api/v1/pqrs/{creacion.data['id']}/",
            data={"tipo_id": tipo_queja.id},
            format="json",
        )

        assert edicion.status_code == 400

        pqr_guardada = PQR.objects.get(id=creacion.data["id"])
        assert pqr_guardada.tipo.codigo == "PETICION"

    def test_residente_puede_adjuntar_pdf_a_su_pqr(
        self,
        residente_client,
        tipo_peticion,
        tmp_path,
    ):
        """Guarda el archivo y persiste solo sus metadatos asociados a la PQR."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        pdf = SimpleUploadedFile(
            "evidencia.pdf",
            b"%PDF-1.4\ncontenido de prueba",
            content_type="application/pdf",
        )

        with override_settings(MEDIA_ROOT=tmp_path):
            respuesta = residente_client.post(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/",
                data={"archivo": pdf},
                format="multipart",
            )

        assert respuesta.status_code == 201, respuesta.data
        assert respuesta.data["nombre_archivo"] == "evidencia.pdf"
        assert respuesta.data["tipo_mime"] == "application/pdf"
        assert respuesta.data["tamano_bytes"] == len(b"%PDF-1.4\ncontenido de prueba")

        adjunto = PQRAdjunto.objects.get(pk=respuesta.data["id"])
        assert adjunto.pqr_id == pqr_id
        assert adjunto.subido_por_id is not None
        assert (tmp_path / adjunto.ruta).is_file()

    def test_rechaza_adjunto_con_extension_no_permitida(
        self,
        residente_client,
        tipo_peticion,
    ):
        """No acepta extensiones fuera de PDF, JPEG y PNG."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        archivo = SimpleUploadedFile(
            "evidencia.exe",
            b"%PDF-1.4\ncontenido",
            content_type="application/octet-stream",
        )

        respuesta = residente_client.post(
            f"/api/v1/pqrs/{pqr_id}/adjuntos/",
            data={"archivo": archivo},
            format="multipart",
        )

        assert respuesta.status_code == 400
        assert "archivo" in respuesta.data

    def test_rechaza_adjunto_si_la_firma_no_coincide_con_extension(
        self,
        residente_client,
        tipo_peticion,
    ):
        """No confía en que el nombre o MIME declarado prueben el tipo real."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        archivo = SimpleUploadedFile(
            "evidencia.pdf",
            b"esto no es un PDF",
            content_type="application/pdf",
        )

        respuesta = residente_client.post(
            f"/api/v1/pqrs/{pqr_id}/adjuntos/",
            data={"archivo": archivo},
            format="multipart",
        )

        assert respuesta.status_code == 400
        assert "archivo" in respuesta.data
        assert PQRAdjunto.objects.count() == 0

    def test_rechaza_adjunto_mayor_a_10_mib(
        self,
        residente_client,
        tipo_peticion,
    ):
        """Aplica el límite de tamaño individual definido para cada evidencia."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        contenido = b"%PDF-1.4\n" + b"x" * (10 * 1024 * 1024)
        archivo = SimpleUploadedFile(
            "evidencia.pdf",
            contenido,
            content_type="application/pdf",
        )

        respuesta = residente_client.post(
            f"/api/v1/pqrs/{pqr_id}/adjuntos/",
            data={"archivo": archivo},
            format="multipart",
        )

        assert respuesta.status_code == 400
        assert "archivo" in respuesta.data
        assert PQRAdjunto.objects.count() == 0

    def test_lista_y_descarga_adjunto_de_la_pqr(
        self,
        residente_client,
        tipo_peticion,
        tmp_path,
    ):
        """Lista los metadatos y permite descargar el contenido vía endpoint autenticado."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        contenido = b"%PDF-1.4\ncontenido de descarga"

        with override_settings(MEDIA_ROOT=tmp_path):
            carga = residente_client.post(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/",
                data={
                    "archivo": SimpleUploadedFile(
                        "evidencia.pdf",
                        contenido,
                        content_type="application/pdf",
                    )
                },
                format="multipart",
            )
            assert carga.status_code == 201, carga.data

            listado = residente_client.get(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/"
            )
            descarga = residente_client.get(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/"
                f"{carga.data['id']}/descargar/"
            )

        assert listado.status_code == 200
        assert len(listado.data) == 1
        assert listado.data[0]["nombre_archivo"] == "evidencia.pdf"
        assert descarga.status_code == 200
        assert b"".join(descarga.streaming_content) == contenido

    def test_residente_puede_reemplazar_adjunto(
        self,
        residente_client,
        tipo_peticion,
        tmp_path,
    ):
        """Reemplaza el contenido y los metadatos del adjunto existente."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        contenido_anterior = b"%PDF-1.4\ncontenido anterior"
        contenido_nuevo = b"%PDF-1.7\ncontenido actualizado"

        with override_settings(MEDIA_ROOT=tmp_path):
            carga = residente_client.post(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/",
                data={
                    "archivo": SimpleUploadedFile(
                        "anterior.pdf",
                        contenido_anterior,
                        content_type="application/pdf",
                    )
                },
                format="multipart",
            )
            assert carga.status_code == 201, carga.data
            ruta_anterior = PQRAdjunto.objects.get(pk=carga.data["id"]).ruta

            detalle = residente_client.get(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/{carga.data['id']}/"
            )
            reemplazo = residente_client.patch(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/{carga.data['id']}/",
                data={
                    "archivo": SimpleUploadedFile(
                        "actualizado.pdf",
                        contenido_nuevo,
                        content_type="application/pdf",
                    )
                },
                format="multipart",
            )
            descarga = residente_client.get(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/"
                f"{carga.data['id']}/descargar/"
            )

        assert detalle.status_code == 200
        assert detalle.data["nombre_archivo"] == "anterior.pdf"
        assert reemplazo.status_code == 200, reemplazo.data
        assert reemplazo.data["id"] == carga.data["id"]
        assert reemplazo.data["nombre_archivo"] == "actualizado.pdf"
        assert reemplazo.data["tamano_bytes"] == len(contenido_nuevo)
        adjunto = PQRAdjunto.objects.get(pk=carga.data["id"])
        assert adjunto.ruta != ruta_anterior
        assert not (tmp_path / ruta_anterior).exists()
        assert descarga.status_code == 200
        assert b"".join(descarga.streaming_content) == contenido_nuevo

    def test_residente_puede_eliminar_adjunto(
        self,
        residente_client,
        tipo_peticion,
        tmp_path,
    ):
        """Elimina tanto los metadatos como el archivo físico."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        with override_settings(MEDIA_ROOT=tmp_path):
            carga = residente_client.post(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/",
                data={
                    "archivo": SimpleUploadedFile(
                        "evidencia.pdf",
                        b"%PDF-1.4\ncontenido",
                        content_type="application/pdf",
                    )
                },
                format="multipart",
            )
            assert carga.status_code == 201, carga.data
            ruta = PQRAdjunto.objects.get(pk=carga.data["id"]).ruta

            eliminacion = residente_client.delete(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/{carga.data['id']}/"
            )
            listado = residente_client.get(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/"
            )

        assert eliminacion.status_code == 204
        assert not PQRAdjunto.objects.filter(pk=carga.data["id"]).exists()
        assert not (tmp_path / ruta).exists()
        assert listado.status_code == 200
        assert listado.data == []

    def test_residente_no_puede_listar_adjuntos_de_otra_persona(
        self,
        residente_client,
        tipo_peticion,
    ):
        """Un adjunto solo se expone a quien puede acceder a la PQR asociada."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        otro_residente = Usuario.objects.create_user(
            username="otro_residente_pqr",
            email="otro_residente_pqr@example.com",
            password=CLAVE,
            nombres="Otro",
            apellidos="Residente",
            numero_documento="2098765432",
        )
        UsuarioRol.objects.create(
            usuario=otro_residente,
            rol=Rol.objects.get(codigo="RESIDENTE"),
        )
        otro_cliente = APIClient()
        login = otro_cliente.post(
            "/api/v1/auth/login/",
            {"username": "otro_residente_pqr", "password": CLAVE},
            format="json",
        )
        assert login.status_code == 200, login.data
        otro_cliente.credentials(
            HTTP_AUTHORIZATION=f"Bearer {login.data['access']}"
        )

        listado = otro_cliente.get(f"/api/v1/pqrs/{pqr_id}/adjuntos/")

        assert listado.status_code == 404