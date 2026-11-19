from datetime import timedelta

import pytest
from django.utils import timezone

from apps.core.models import Copropiedad
from apps.inmuebles.models import Inmueble, InmuebleUsuario
from apps.usuarios.models import RecuperacionPassword, Rol, Usuario, UsuarioRol

pytestmark = pytest.mark.django_db

INMUEBLES = "/api/v1/inmuebles/"
COPROPIEDADES = "/api/v1/copropiedades/"
AUDITORIA = "/api/v1/auditoria/"
USUARIOS = "/api/v1/usuarios/"


def test_inmueble_ubicacion_duplicada_devuelve_400(admin_client):
    r1 = admin_client.post(
        INMUEBLES,
        {"tipo": "APARTAMENTO", "torre_bloque": "A", "piso": 3, "numero": "301"},
        format="json",
    )
    assert r1.status_code == 201

    r2 = admin_client.post(
        INMUEBLES,
        {"tipo": "APARTAMENTO", "torre_bloque": "A", "piso": 3, "numero": "301"},
        format="json",
    )
    assert r2.status_code == 400
    assert "numero" in r2.data


def test_inmueble_rechaza_area_no_positiva_y_piso_fuera_de_rango(admin_client):
    r_area = admin_client.post(
        INMUEBLES,
        {"tipo": "CASA", "numero": "10", "area_m2": 0},
        format="json",
    )
    assert r_area.status_code == 400
    assert "area_m2" in r_area.data

    r_piso = admin_client.post(
        INMUEBLES,
        {"tipo": "APARTAMENTO", "numero": "11", "piso": 500},
        format="json",
    )
    assert r_piso.status_code == 400
    assert "piso" in r_piso.data


def test_editar_ubicacion_regenera_codigo_interno(admin_client):
    creado = admin_client.post(
        INMUEBLES,
        {"tipo": "CASA", "numero": "101"},
        format="json",
    )
    assert creado.status_code == 201
    assert creado.data["codigo_interno"] == "CAS-101"

    editado = admin_client.patch(
        f"{INMUEBLES}{creado.data['id']}/",
        {"tipo": "APARTAMENTO", "torre_bloque": "B", "numero": "405", "piso": 4},
        format="json",
    )
    assert editado.status_code == 200
    assert editado.data["codigo_interno"] == "APA-B-405"


def test_inmuebles_no_permiten_delete_fisico(admin_client):
    creado = admin_client.post(INMUEBLES, {"tipo": "PARQUEADERO", "numero": "P-01"}, format="json")
    assert creado.status_code == 201
    inm_id = creado.data["id"]

    assert admin_client.delete(f"{INMUEBLES}{inm_id}/").status_code == 405
    r_des = admin_client.post(f"{INMUEBLES}{inm_id}/desactivar/")
    assert r_des.status_code == 200
    assert r_des.data["activo"] is False
    assert Inmueble.objects.filter(pk=inm_id).exists()


def test_vincular_validaciones_inactivo_duplicado_y_contradictorio(admin_client, usuario, cliente_de):
    UsuarioRol.objects.create(usuario=usuario, rol=Rol.objects.get(codigo="RESIDENTE"))
    creado = admin_client.post(INMUEBLES, {"tipo": "APARTAMENTO", "torre_bloque": "T1", "numero": "102"}, format="json")
    inm_id = creado.data["id"]

    # Vincular como PROPIETARIO ok
    r_ok = admin_client.post(
        f"{INMUEBLES}{inm_id}/vincular/",
        {"usuario_id": usuario.pk, "tipo_relacion": "PROPIETARIO"},
        format="json",
    )
    assert r_ok.status_code == 200
    assert len(r_ok.data["vinculos"]) == 1
    vinculo_id = r_ok.data["vinculos"][0]["id"]

    # Mismo vínculo duplicado -> 400
    r_dup = admin_client.post(
        f"{INMUEBLES}{inm_id}/vincular/",
        {"usuario_id": usuario.pk, "tipo_relacion": "PROPIETARIO"},
        format="json",
    )
    assert r_dup.status_code == 400

    # Relación contradictoria PROPIETARIO + ARRENDATARIO -> 400
    r_contra = admin_client.post(
        f"{INMUEBLES}{inm_id}/vincular/",
        {"usuario_id": usuario.pk, "tipo_relacion": "ARRENDATARIO"},
        format="json",
    )
    assert r_contra.status_code == 400

    # Desactivar inmueble oculta el inmueble al residente y bloquea nuevos vínculos
    admin_client.post(f"{INMUEBLES}{inm_id}/desactivar/")
    res_client = cliente_de("ana")
    assert res_client.get(f"{INMUEBLES}?mios=true").data["count"] == 0

    r_inactivo = admin_client.post(
        f"{INMUEBLES}{inm_id}/vincular/",
        {"usuario_id": usuario.pk, "tipo_relacion": "RESIDENTE"},
        format="json",
    )
    assert r_inactivo.status_code == 400

    # Desvincular: valida vinculo_id inválido (400) y soporta fecha_inicio futura sin 500 ni borrado físico
    assert admin_client.post(f"{INMUEBLES}{inm_id}/desvincular/", {"vinculo_id": "abc"}, format="json").status_code == 400

    InmuebleUsuario.objects.filter(pk=vinculo_id).update(fecha_inicio=timezone.localdate() + timedelta(days=1))
    r_desv = admin_client.post(f"{INMUEBLES}{inm_id}/desvincular/", {"vinculo_id": vinculo_id}, format="json")
    assert r_desv.status_code == 200
    assert r_desv.data["vinculos"] == []
    # El registro histórico permanece en BD con fecha_fin diligenciada (sin DELETE físico)
    v = InmuebleUsuario.objects.get(pk=vinculo_id)
    assert v.fecha_fin is not None and v.fecha_fin >= v.fecha_inicio


def test_crear_usuario_rechaza_roles_vacios(admin_client):
    r = admin_client.post(
        USUARIOS,
        {
            "tipo_documento": "CC",
            "numero_documento": "888999000",
            "nombres": "Sin",
            "apellidos": "Rol",
            "username": "sinrol",
            "email": "sinrol@example.com",
            "password": "Segura12345!",
            "roles": [],
        },
        format="json",
    )
    assert r.status_code == 400
    assert "roles" in r.data


def test_copropiedad_valida_nit_unico_y_email_y_sin_delete(admin_client):
    r1 = admin_client.post(
        COPROPIEDADES,
        {"nombre": "Conjunto A", "nit": "901234567-8", "email": "admin@conjuntoa.co"},
        format="json",
    )
    assert r1.status_code == 201
    assert admin_client.delete(f"{COPROPIEDADES}{r1.data['id']}/").status_code == 405

    r_dup = admin_client.post(
        COPROPIEDADES,
        {"nombre": "Conjunto B", "nit": "901234567-8"},
        format="json",
    )
    assert r_dup.status_code == 400
    assert "nit" in r_dup.data

    r_mail = admin_client.post(
        COPROPIEDADES,
        {"nombre": "Conjunto C", "email": "correo-malo"},
        format="json",
    )
    assert r_mail.status_code == 400
    assert "email" in r_mail.data


def test_recuperacion_no_borra_registros_historicos(client, usuario, mailoutbox):
    client.post("/api/v1/auth/recuperar/", {"identificador": "ana"}, format="json")
    client.post("/api/v1/auth/recuperar/", {"identificador": "ana"}, format="json")
    assert RecuperacionPassword.objects.filter(usuario=usuario).count() == 2
    assert RecuperacionPassword.objects.filter(usuario=usuario, usado_en__isnull=True).count() == 1


def test_auditoria_filtra_por_tabla_real_y_fecha(admin_client):
    admin_client.post(INMUEBLES, {"tipo": "OTRO", "numero": "DEP-1"}, format="json")
    hoy = timezone.localdate().isoformat()
    r = admin_client.get(f"{AUDITORIA}?tabla=inmuebles&fecha={hoy}")
    assert r.status_code == 200
    assert r.data["count"] >= 1


def test_gestor_inmuebles_puede_listar_usuarios_para_vincular(admin_client, usuario, cliente_de):
    from apps.usuarios.models import Permiso, RolPermiso

    rol = Rol.objects.create(codigo="GESTOR_INM", nombre="Gestor de Inmuebles")
    RolPermiso.objects.create(rol=rol, permiso=Permiso.objects.get(codigo="inmuebles.gestionar"))
    UsuarioRol.objects.create(usuario=usuario, rol=rol)

    gestor = cliente_de("ana")
    assert gestor.get(f"{USUARIOS}?activo=true").status_code == 200
    # Pero sigue sin poder crear o desactivar usuarios sin usuarios.gestionar
    assert gestor.post(f"{USUARIOS}{usuario.pk}/desactivar/").status_code == 403


def test_foto_perfil_rechaza_archivo_corrupto_disfrazado_de_png(auth_client):
    import base64

    falso_png = "data:image/png;base64," + base64.b64encode(b"esto no es un png").decode()
    r = auth_client.patch("/api/v1/auth/me/", {"foto_perfil": falso_png}, format="json")
    assert r.status_code == 400
    assert "foto_perfil" in r.data

