import pytest
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import override_settings
from rest_framework.test import APIClient

from apps.pqrs.models import (
    PQR,
    PQRAdjunto,
    PQRHistorial,
    PQRRespuesta,
    TipoPQR,
)
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
def otro_residente_client():
    """Cliente de un segundo residente, sin relación con las PQR del primero."""
    usuario = Usuario.objects.create_user(
        username="otro_residente_pqr",
        email="otro_residente_pqr@example.com",
        password=CLAVE,
        nombres="Otro",
        apellidos="Residente",
        numero_documento="2098765432",
    )
    UsuarioRol.objects.create(
        usuario=usuario,
        rol=Rol.objects.get(codigo="RESIDENTE"),
    )
    cliente = APIClient()
    cliente.force_authenticate(user=usuario)
    return cliente


@pytest.fixture
def responsable_pqr():
    """Usuario con el rol RESPONSABLE_PQR (permisos pqr.radicar y pqr.gestionar)."""
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
    return usuario


@pytest.fixture
def responsable_pqr_client(responsable_pqr):
    """Cliente autenticado como el responsable PQR."""
    cliente = APIClient()
    cliente.force_authenticate(user=responsable_pqr)
    return cliente


@pytest.fixture
def admin_pqr_client():
    """Cliente administrador: tiene todos los permisos, incluido usuarios.gestionar."""
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
    """Comprueba radicación, visibilidad, ciclo de estados, respuestas y adjuntos."""

    # ------------------------------------------------------------------
    # Utilidades
    # ------------------------------------------------------------------

    def _crear_pqr(self, cliente, tipo_peticion):
        """Crea una PQR válida con el cliente indicado y devuelve su id."""
        respuesta = cliente.post(
            "/api/v1/pqrs/",
            data={
                "tipo_id": tipo_peticion.id,
                "asunto": "Revisión de filtración",
                "descripcion": "Hay una filtración de agua en el pasillo.",
            },
            format="json",
        )
        assert respuesta.status_code == 201, respuesta.data
        return respuesta.data["id"]

    def _cambiar_estado(self, cliente, pqr_id, codigo, **extra):
        """Solicita una transición de estado y devuelve la respuesta HTTP."""
        return cliente.patch(
            f"/api/v1/pqrs/{pqr_id}/estado/",
            data={"estado_codigo": codigo, **extra},
            format="json",
        )

    def _avanzar(self, cliente, pqr_id, *codigos):
        """Aplica varias transiciones seguidas y exige que todas se acepten."""
        for codigo in codigos:
            respuesta = self._cambiar_estado(cliente, pqr_id, codigo)
            assert respuesta.status_code == 200, respuesta.data
            assert respuesta.data["estado_codigo"] == codigo

    def _asignar(self, admin_client, pqr_id, usuario):
        """Asigna un responsable con el administrador y devuelve la respuesta."""
        respuesta = admin_client.patch(
            f"/api/v1/pqrs/{pqr_id}/responsable/",
            data={"responsable_id": usuario.pk},
            format="json",
        )
        assert respuesta.status_code == 200, respuesta.data
        return respuesta

    @staticmethod
    def _ids(data):
        """Extrae los ids de un listado, con o sin paginación."""
        items = data["results"] if isinstance(data, dict) else data
        return [item["id"] for item in items]

    # ------------------------------------------------------------------
    # Catálogo y radicación
    # ------------------------------------------------------------------

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
        }
        res = residente_client.post("/api/v1/pqrs/", data=payload, format="json")

        assert res.status_code == 201
        data = res.data
        assert data["radicado"] is not None
        assert data["radicado"].startswith("PET-")
        assert data["estado_codigo"] == "RECIBIDA"
        assert data["asunto"] == payload["asunto"]

        pqr_db = PQR.objects.get(id=data["id"])
        assert pqr_db.solicitante == residente
        assert pqr_db.estado.codigo == "RECIBIDA"
        assert PQRHistorial.objects.filter(
            pqr=pqr_db,
            comentario="PQR radicada",
        ).exists()

    def test_residente_no_puede_definir_prioridad_al_radicar(
        self,
        residente_client,
        tipo_peticion,
    ):
        """La prioridad enviada por un residente se ignora y queda MEDIA."""
        respuesta = residente_client.post(
            "/api/v1/pqrs/",
            data={
                "tipo_id": tipo_peticion.id,
                "asunto": "Solicitud de atención urgente",
                "descripcion": "Solicito atención de esta situación general.",
                "prioridad": "ALTA",
            },
            format="json",
        )

        assert respuesta.status_code == 201
        assert PQR.objects.get(id=respuesta.data["id"]).prioridad == "MEDIA"

    def test_gestor_puede_definir_prioridad_al_radicar(
        self,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Quien tiene pqr.gestionar sí puede fijar la prioridad al radicar."""
        respuesta = admin_pqr_client.post(
            "/api/v1/pqrs/",
            data={
                "tipo_id": tipo_peticion.id,
                "asunto": "Revisión programada de ascensores",
                "descripcion": "Solicitud interna de la administración.",
                "prioridad": "ALTA",
            },
            format="json",
        )

        assert respuesta.status_code == 201, respuesta.data
        assert PQR.objects.get(id=respuesta.data["id"]).prioridad == "ALTA"

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

        respuesta = residente_client.post(
            "/api/v1/pqrs/",
            data={
                "tipo_id": tipo.id,
                "asunto": "Consulta sobre la copropiedad",
                "descripcion": "Solicito revisar esta situación con detalle.",
            },
            format="json",
        )

        assert respuesta.status_code == 201
        assert respuesta.data["tipo"]["codigo"] == codigo
        assert respuesta.data["radicado"].startswith(f"{prefijo}-")

    def test_dos_pqrs_reciben_radicados_distintos(self, residente_client):
        """El consecutivo de base de datos no se repite entre solicitudes."""
        tipo_peticion = TipoPQR.objects.get(codigo="PETICION")
        tipo_queja = TipoPQR.objects.get(codigo="QUEJA")

        payload_base = {
            "asunto": "Consulta sobre la copropiedad",
            "descripcion": "Solicito revisar esta situación con detalle.",
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
        tipo_peticion,
    ):
        """Una edición no debe dejar el tipo y el prefijo inconsistentes."""
        tipo_queja = TipoPQR.objects.get(codigo="QUEJA")
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        edicion = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={"tipo_id": tipo_queja.id},
            format="json",
        )

        assert edicion.status_code == 400
        assert PQR.objects.get(id=pqr_id).tipo.codigo == "PETICION"

    # ------------------------------------------------------------------
    # Consulta, visibilidad e historial
    # ------------------------------------------------------------------

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

    def test_visibilidad_del_listado_segun_rol(
        self,
        residente_client,
        otro_residente_client,
        admin_pqr_client,
        responsable_pqr,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """Cada rol ve solo las PQR que le corresponden."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        propias = residente_client.get("/api/v1/pqrs/")
        ajenas = otro_residente_client.get("/api/v1/pqrs/")
        sin_asignar = responsable_pqr_client.get("/api/v1/pqrs/")
        assert pqr_id in self._ids(propias.data)
        assert pqr_id not in self._ids(ajenas.data)
        assert pqr_id not in self._ids(sin_asignar.data)

        self._asignar(admin_pqr_client, pqr_id, responsable_pqr)

        asignada = responsable_pqr_client.get("/api/v1/pqrs/")
        todas = admin_pqr_client.get("/api/v1/pqrs/")
        assert pqr_id in self._ids(asignada.data)
        assert pqr_id in self._ids(todas.data)

    def test_consulta_historial_pqr_propias(self, residente_client, tipo_peticion):
        """La PQR expone la radicación inicial en el historial accesible."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = residente_client.get(f"/api/v1/pqrs/{pqr_id}/historial/")

        assert respuesta.status_code == 200
        assert len(respuesta.data) == 1
        assert respuesta.data[0]["comentario"] == "PQR radicada"
        assert respuesta.data[0]["estado_nuevo_codigo"] == "RECIBIDA"
        assert respuesta.data[0]["usuario_nombre"] == "Juan Pérez"

    def test_residente_no_consulta_historial_de_otra_persona(
        self,
        residente_client,
        otro_residente_client,
        tipo_peticion,
    ):
        """El endpoint del historial conserva el aislamiento entre residentes."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = otro_residente_client.get(f"/api/v1/pqrs/{pqr_id}/historial/")

        assert respuesta.status_code == 404

    # ------------------------------------------------------------------
    # Edición y eliminación
    # ------------------------------------------------------------------

    def test_edicion_pqr_se_registra_en_historial(
        self,
        residente_client,
        tipo_peticion,
    ):
        """Registra los nombres de campos que cambian sin duplicar triggers."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={"asunto": "Revisión prioritaria de filtración"},
            format="json",
        )

        assert respuesta.status_code == 200, respuesta.data
        eventos = PQRHistorial.objects.filter(pqr_id=pqr_id).order_by("id")
        assert eventos.count() == 2
        assert "asunto" in eventos.last().comentario

    def test_residente_no_puede_modificar_prioridad(
        self,
        residente_client,
        tipo_peticion,
    ):
        """Las ediciones conservan la prioridad y no la listan como modificada."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        pqr = PQR.objects.get(id=pqr_id)
        pqr.prioridad = "BAJA"
        pqr.save(update_fields=["prioridad"])

        respuesta = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={
                "asunto": "Asunto actualizado por el residente",
                "prioridad": "ALTA",
            },
            format="json",
        )

        assert respuesta.status_code == 200
        pqr.refresh_from_db()
        assert pqr.prioridad == "BAJA"
        ultimo = PQRHistorial.objects.filter(pqr_id=pqr_id).order_by("id").last()
        assert "asunto" in ultimo.comentario
        assert "prioridad" not in ultimo.comentario

    def test_gestor_puede_modificar_prioridad(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Quien tiene pqr.gestionar puede cambiar la prioridad de una PQR."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={"prioridad": "ALTA"},
            format="json",
        )

        assert respuesta.status_code == 200, respuesta.data
        assert PQR.objects.get(id=pqr_id).prioridad == "ALTA"

    def test_residente_no_puede_editar_pqr_ya_revisada(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Fuera del estado RECIBIDA, el residente ya no puede editar."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._avanzar(admin_pqr_client, pqr_id, "EN_REVISION")

        respuesta = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={"asunto": "Intento de edición tardía"},
            format="json",
        )

        assert respuesta.status_code == 403

    def test_no_se_puede_editar_pqr_cerrada(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Una PQR cerrada es de solo lectura incluso para el administrador."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._avanzar(
            admin_pqr_client,
            pqr_id,
            "EN_REVISION",
            "EN_PROCESO",
            "ATENDIDA",
            "CERRADA",
        )

        respuesta = admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={"asunto": "Cambio posterior al cierre"},
            format="json",
        )

        assert respuesta.status_code == 400

    def test_no_se_puede_editar_pqr_anulada(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Una PQR anulada tampoco admite modificaciones."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        anulacion = self._cambiar_estado(
            residente_client,
            pqr_id,
            "ANULADA",
            motivo="Solicitud duplicada.",
        )
        assert anulacion.status_code == 200, anulacion.data

        respuesta = admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/",
            data={"asunto": "Cambio posterior a la anulación"},
            format="json",
        )

        assert respuesta.status_code == 400

    def test_las_pqr_no_se_pueden_eliminar(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Ningún rol puede borrar una PQR: el endpoint no admite DELETE."""        
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        por_residente = residente_client.delete(f"/api/v1/pqrs/{pqr_id}/")
        por_administrador = admin_pqr_client.delete(f"/api/v1/pqrs/{pqr_id}/")

        assert por_residente.status_code == 405
        assert por_administrador.status_code == 405
        assert PQR.objects.filter(pk=pqr_id).exists()
        assert PQRHistorial.objects.filter(pqr_id=pqr_id).count() == 1

    # ------------------------------------------------------------------
    # Ciclo de estados
    # ------------------------------------------------------------------

    def test_admin_avanza_solicitud_por_todo_el_ciclo(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """El administrador recorre el flujo y la base registra cierre e historial."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        self._avanzar(
            admin_pqr_client,
            pqr_id,
            "EN_REVISION",
            "EN_PROCESO",
            "ATENDIDA",
            "CERRADA",
        )

        pqr = PQR.objects.get(pk=pqr_id)
        assert pqr.fecha_cierre is not None
        assert pqr.historial.count() == 5

    def test_responsable_asignado_avanza_solicitud(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """El responsable asignado puede continuar el flujo desde EN_PROCESO."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._asignar(admin_pqr_client, pqr_id, responsable_pqr)

        self._avanzar(responsable_pqr_client, pqr_id, "ATENDIDA", "CERRADA")

        pqr = PQR.objects.get(pk=pqr_id)
        assert pqr.estado.codigo == "CERRADA"
        assert pqr.fecha_cierre is not None

    def test_gestor_no_puede_saltar_estados(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Rechaza el salto de RECIBIDA a EN_PROCESO."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = self._cambiar_estado(admin_pqr_client, pqr_id, "EN_PROCESO")

        assert respuesta.status_code == 400
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    def test_residente_no_puede_cambiar_estado_de_pqr(
        self,
        residente_client,
        tipo_peticion,
    ):
        """El permiso de radicación no permite avanzar el estado."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = self._cambiar_estado(residente_client, pqr_id, "EN_REVISION")

        assert respuesta.status_code == 403
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    def test_responsable_no_asignado_no_ve_ni_cambia_estado(
        self,
        residente_client,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """Una PQR ajena y sin asignar es invisible para el responsable."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        detalle = responsable_pqr_client.get(f"/api/v1/pqrs/{pqr_id}/")
        cambio = self._cambiar_estado(responsable_pqr_client, pqr_id, "EN_REVISION")

        assert detalle.status_code == 404
        assert cambio.status_code == 404
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    # ------------------------------------------------------------------
    # Anulación
    # ------------------------------------------------------------------

    def test_residente_anula_su_pqr_recibida_con_motivo(
        self,
        residente_client,
        tipo_peticion,
    ):
        """El solicitante puede anular en las etapas iniciales indicando motivo."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = self._cambiar_estado(
            residente_client,
            pqr_id,
            "ANULADA",
            motivo="Solicitud duplicada.",
        )

        assert respuesta.status_code == 200, respuesta.data
        assert respuesta.data["estado_codigo"] == "ANULADA"
        pqr = PQR.objects.get(pk=pqr_id)
        assert pqr.fecha_cierre is not None
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario="PQR anulada. Motivo: Solicitud duplicada.",
        ).exists()

    def test_anulacion_exige_motivo(self, residente_client, tipo_peticion):
        """Sin motivo de al menos 5 caracteres no se anula la solicitud."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        sin_motivo = self._cambiar_estado(residente_client, pqr_id, "ANULADA")
        motivo_corto = self._cambiar_estado(
            residente_client,
            pqr_id,
            "ANULADA",
            motivo="no",
        )

        assert sin_motivo.status_code == 400
        assert motivo_corto.status_code == 400
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    def test_residente_no_puede_anular_pqr_en_proceso(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr,
        tipo_peticion,
    ):
        """Pasadas las etapas iniciales, solo el administrador puede anular."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._asignar(admin_pqr_client, pqr_id, responsable_pqr)

        respuesta = self._cambiar_estado(
            residente_client,
            pqr_id,
            "ANULADA",
            motivo="Ya no es necesaria.",
        )

        assert respuesta.status_code == 403
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "EN_PROCESO"

    def test_admin_puede_anular_pqr_en_proceso(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr,
        tipo_peticion,
    ):
        """El administrador puede anular en cualquier etapa no finalizada."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._asignar(admin_pqr_client, pqr_id, responsable_pqr)

        respuesta = self._cambiar_estado(
            admin_pqr_client,
            pqr_id,
            "ANULADA",
            motivo="Radicada por error.",
        )

        assert respuesta.status_code == 200, respuesta.data
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "ANULADA"

    def test_pqr_anulada_no_admite_mas_transiciones(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """ANULADA es un estado final: no tiene destinos permitidos."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        anulacion = self._cambiar_estado(
            residente_client,
            pqr_id,
            "ANULADA",
            motivo="Solicitud duplicada.",
        )
        assert anulacion.status_code == 200, anulacion.data

        respuesta = self._cambiar_estado(admin_pqr_client, pqr_id, "EN_REVISION")

        assert respuesta.status_code == 400
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "ANULADA"

    def test_otro_residente_no_puede_anular_pqr_ajena(
        self,
        residente_client,
        otro_residente_client,
        tipo_peticion,
    ):
        """Quien no radicó la PQR ni la gestiona no puede ni verla."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = self._cambiar_estado(
            otro_residente_client,
            pqr_id,
            "ANULADA",
            motivo="Intento ajeno.",
        )

        assert respuesta.status_code == 404
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"

    # ------------------------------------------------------------------
    # Asignación de responsable
    # ------------------------------------------------------------------

    def test_admin_asigna_responsable_a_una_pqr(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr,
        tipo_peticion,
    ):
        """El administrador asigna la PQR, que pasa a EN_PROCESO con historial."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = self._asignar(admin_pqr_client, pqr_id, responsable_pqr)

        assert respuesta.data["responsable_id"] == responsable_pqr.id
        assert respuesta.data["responsable_nombre"] == responsable_pqr.nombre_completo
        assert respuesta.data["estado_codigo"] == "EN_PROCESO"

        pqr = PQR.objects.get(pk=pqr_id)
        assert pqr.responsable_id == responsable_pqr.id
        ultimo_evento = pqr.historial.order_by("-id").first()
        assert ultimo_evento.responsable_id == responsable_pqr.id
        assert ultimo_evento.comentario == "Cambio de responsable"

        detalle = residente_client.get(f"/api/v1/pqrs/{pqr_id}/")
        assert detalle.status_code == 200
        assert detalle.data["responsable_id"] == responsable_pqr.id
        assert detalle.data["responsable_nombre"] == responsable_pqr.nombre_completo

    def test_residente_no_puede_asignar_responsable(
        self,
        residente_client,
        responsable_pqr,
        tipo_peticion,
    ):
        """El residente no puede asignar responsables aunque conozca su ID."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = residente_client.patch(
            f"/api/v1/pqrs/{pqr_id}/responsable/",
            data={"responsable_id": responsable_pqr.id},
            format="json",
        )

        assert respuesta.status_code == 403
        assert PQR.objects.get(pk=pqr_id).responsable_id is None

    def test_responsable_pqr_no_puede_asignar_otro_responsable(
        self,
        residente_client,
        responsable_pqr,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """El permiso pqr.gestionar no sustituye al permiso administrativo."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = responsable_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/responsable/",
            data={"responsable_id": responsable_pqr.id},
            format="json",
        )

        assert respuesta.status_code == 403
        assert PQR.objects.get(pk=pqr_id).responsable_id is None

    def test_admin_no_puede_asignar_usuario_sin_rol_responsable(
        self,
        residente_client,
        residente,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Solo admite cuentas que sean responsables PQR activas."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = admin_pqr_client.patch(
            f"/api/v1/pqrs/{pqr_id}/responsable/",
            data={"responsable_id": residente.pk},
            format="json",
        )

        assert respuesta.status_code == 400
        assert PQR.objects.get(pk=pqr_id).responsable_id is None

    # ------------------------------------------------------------------
    # Respuestas
    # ------------------------------------------------------------------

    def test_responsable_asignado_registra_solucion_y_cierra_pqr(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """La solución del asignado cierra la PQR y queda en el historial."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._asignar(admin_pqr_client, pqr_id, responsable_pqr)
        texto = "Se programó la reparación de la filtración."

        respuesta = responsable_pqr_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": texto, "es_solucion": True},
            format="json",
        )

        assert respuesta.status_code == 201, respuesta.data
        assert respuesta.data["respuesta"] == texto
        assert respuesta.data["es_solucion"] is True
        assert respuesta.data["responsable_nombre"] == responsable_pqr.nombre_completo
        assert (
            PQRRespuesta.objects.get(pk=respuesta.data["id"]).responsable_id
            == responsable_pqr.id
        )
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "CERRADA"

        consulta = residente_client.get(f"/api/v1/pqrs/{pqr_id}/respuestas/")
        assert consulta.status_code == 200
        assert len(consulta.data) == 1
        assert consulta.data[0]["respuesta"] == texto
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario=(
                f"PQR cerrada por {responsable_pqr.nombre_completo}. "
                f"Solución final: {texto}"
            ),
        ).exists()

    def test_responsable_asignado_responde_sin_solucion_y_pasa_a_atendida(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """Una respuesta que no es solución deja la PQR en ATENDIDA."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._asignar(admin_pqr_client, pqr_id, responsable_pqr)

        respuesta = responsable_pqr_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": "Estamos programando la visita técnica."},
            format="json",
        )

        assert respuesta.status_code == 201, respuesta.data
        assert respuesta.data["es_solucion"] is False
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "ATENDIDA"
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario="Respuesta registrada.",
        ).exists()

    def test_admin_registra_respuesta_sin_asignacion(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """El administrador puede responder aunque no esté asignado a la PQR."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = admin_pqr_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": "La administración recibió la solicitud."},
            format="json",
        )

        assert respuesta.status_code == 201, respuesta.data
        assert respuesta.data["es_solucion"] is False
        administrador = Usuario.objects.get(username="admin_ciclo_pqr")
        assert (
            PQRRespuesta.objects.get(pk=respuesta.data["id"]).responsable_id
            == administrador.pk
        )

    def test_responsable_no_asignado_no_puede_registrar_respuesta(
        self,
        residente_client,
        admin_pqr_client,
        responsable_pqr_client,
        tipo_peticion,
    ):
        """El permiso de gestión no permite responder una PQR no asignada."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        otro = Usuario.objects.create_user(
            username="otro_responsable_pqr",
            email="otro_responsable_pqr@example.com",
            password=CLAVE,
            nombres="Otro",
            apellidos="Responsable",
            numero_documento="5098765432",
        )
        UsuarioRol.objects.create(
            usuario=otro,
            rol=Rol.objects.get(codigo="RESPONSABLE_PQR"),
        )
        self._asignar(admin_pqr_client, pqr_id, otro)

        respuesta = responsable_pqr_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": "No debe ser aceptada."},
            format="json",
        )

        assert respuesta.status_code == 403
        assert not PQRRespuesta.objects.filter(pqr_id=pqr_id).exists()

    def test_solicitante_envia_mensaje_de_seguimiento_sin_cambiar_estado(
        self,
        residente_client,
        tipo_peticion,
    ):
        """Quien radicó puede escribir, pero no marcar solución ni cambiar el estado."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = residente_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": "¿Hay novedades sobre mi solicitud?", "es_solucion": True},
            format="json",
        )

        assert respuesta.status_code == 201, respuesta.data
        assert respuesta.data["es_solucion"] is False
        assert PQR.objects.get(pk=pqr_id).estado.codigo == "RECIBIDA"
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario="Respuesta del solicitante registrada.",
        ).exists()

    def test_otro_residente_no_puede_registrar_respuesta(
        self,
        residente_client,
        otro_residente_client,
        tipo_peticion,
    ):
        """Quien no es solicitante ni gestor no puede escribir en la PQR."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = otro_residente_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": "Mensaje ajeno."},
            format="json",
        )

        assert respuesta.status_code == 404
        assert not PQRRespuesta.objects.filter(pqr_id=pqr_id).exists()

    def test_no_se_registran_respuestas_en_pqr_cerrada_o_anulada(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Las solicitudes finalizadas no admiten nuevas respuestas."""
        cerrada_id = self._crear_pqr(residente_client, tipo_peticion)
        self._avanzar(
            admin_pqr_client,
            cerrada_id,
            "EN_REVISION",
            "EN_PROCESO",
            "ATENDIDA",
            "CERRADA",
        )
        anulada_id = self._crear_pqr(residente_client, tipo_peticion)
        anulacion = self._cambiar_estado(
            residente_client,
            anulada_id,
            "ANULADA",
            motivo="Solicitud duplicada.",
        )
        assert anulacion.status_code == 200, anulacion.data

        for pqr_id in (cerrada_id, anulada_id):
            respuesta = admin_pqr_client.post(
                f"/api/v1/pqrs/{pqr_id}/respuestas/",
                data={"respuesta": "Respuesta tardía."},
                format="json",
            )
            assert respuesta.status_code == 400, respuesta.data
            assert not PQRRespuesta.objects.filter(pqr_id=pqr_id).exists()

    def test_residente_no_puede_consultar_respuestas_de_otra_persona(
        self,
        residente_client,
        otro_residente_client,
        tipo_peticion,
    ):
        """El listado de respuestas conserva el aislamiento entre residentes."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = otro_residente_client.get(f"/api/v1/pqrs/{pqr_id}/respuestas/")

        assert respuesta.status_code == 404

    def test_rechaza_respuesta_vacia(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """No se persiste una respuesta que esté vacía o tenga solo espacios."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        respuesta = admin_pqr_client.post(
            f"/api/v1/pqrs/{pqr_id}/respuestas/",
            data={"respuesta": "   "},
            format="json",
        )

        assert respuesta.status_code == 400
        assert "respuesta" in respuesta.data
        assert not PQRRespuesta.objects.filter(pqr_id=pqr_id).exists()

    # ------------------------------------------------------------------
    # Adjuntos
    # ------------------------------------------------------------------

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
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario="Adjunto cargado: evidencia.pdf.",
        ).exists()

    def test_residente_no_puede_adjuntar_si_la_pqr_ya_fue_revisada(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
    ):
        """Fuera del estado RECIBIDA, el residente ya no puede agregar archivos."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._avanzar(admin_pqr_client, pqr_id, "EN_REVISION")

        respuesta = residente_client.post(
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

        assert respuesta.status_code == 403
        assert PQRAdjunto.objects.count() == 0

    def test_gestor_puede_adjuntar_en_cualquier_estado(
        self,
        residente_client,
        admin_pqr_client,
        tipo_peticion,
        tmp_path,
    ):
        """El administrador puede cargar evidencias aunque la PQR ya esté en revisión."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)
        self._avanzar(admin_pqr_client, pqr_id, "EN_REVISION")

        with override_settings(MEDIA_ROOT=tmp_path):
            respuesta = admin_pqr_client.post(
                f"/api/v1/pqrs/{pqr_id}/adjuntos/",
                data={
                    "archivo": SimpleUploadedFile(
                        "informe.pdf",
                        b"%PDF-1.4\ninforme",
                        content_type="application/pdf",
                    )
                },
                format="multipart",
            )

        assert respuesta.status_code == 201, respuesta.data
        assert PQRAdjunto.objects.filter(pqr_id=pqr_id).count() == 1

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

            listado = residente_client.get(f"/api/v1/pqrs/{pqr_id}/adjuntos/")
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
        django_capture_on_commit_callbacks,
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
            with django_capture_on_commit_callbacks(execute=True):
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
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario="Adjunto reemplazado: actualizado.pdf.",
        ).exists()
        assert descarga.status_code == 200
        assert b"".join(descarga.streaming_content) == contenido_nuevo

    def test_residente_puede_eliminar_adjunto(
        self,
        residente_client,
        tipo_peticion,
        tmp_path,
        django_capture_on_commit_callbacks,
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

            with django_capture_on_commit_callbacks(execute=True):
                eliminacion = residente_client.delete(
                    f"/api/v1/pqrs/{pqr_id}/adjuntos/{carga.data['id']}/"
                )
            listado = residente_client.get(f"/api/v1/pqrs/{pqr_id}/adjuntos/")

        assert eliminacion.status_code == 204
        assert not PQRAdjunto.objects.filter(pk=carga.data["id"]).exists()
        assert not (tmp_path / ruta).exists()
        assert PQRHistorial.objects.filter(
            pqr_id=pqr_id,
            comentario="Adjunto eliminado: evidencia.pdf.",
        ).exists()
        assert listado.status_code == 200
        assert listado.data == []

    def test_residente_no_puede_listar_adjuntos_de_otra_persona(
        self,
        residente_client,
        otro_residente_client,
        tipo_peticion,
    ):
        """Un adjunto solo se expone a quien puede acceder a la PQR asociada."""
        pqr_id = self._crear_pqr(residente_client, tipo_peticion)

        listado = otro_residente_client.get(f"/api/v1/pqrs/{pqr_id}/adjuntos/")

        assert listado.status_code == 404