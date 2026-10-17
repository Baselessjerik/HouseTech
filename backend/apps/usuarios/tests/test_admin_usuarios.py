import pytest

from apps.core.models import Auditoria
from apps.usuarios.models import Permiso, Rol, RolPermiso, Usuario, UsuarioRol

pytestmark = pytest.mark.django_db

USUARIOS = "/api/v1/usuarios/"
ROLES = "/api/v1/roles/"
PERMISOS = "/api/v1/permisos/"
CLAVE = "Clave12345!"


def nuevo(username, doc, **extra):
    return Usuario.objects.create_user(
        username=username, email=f"{username}@example.com", password=CLAVE,
        nombres=username.capitalize(), apellidos="Prueba", numero_documento=doc, **extra,
    )


def datos(**cambios):
    base = {
        "tipo_documento": "CC", "numero_documento": "777888999", "nombres": "Nuevo",
        "apellidos": "Usuario", "username": "nuevo", "email": "nuevo@example.com",
        "password": "Segura12345!",
    }
    base.update(cambios)
    return base


# --- acceso ----------------------------------------------------------------
def test_sin_token_401_y_sin_permiso_403(client, auth_client):
    from rest_framework.test import APIClient

    assert APIClient().get(USUARIOS).status_code == 401
    assert auth_client.get(USUARIOS).status_code == 403  # ana no tiene roles


def test_residente_no_puede_gestionar(usuario, cliente_de):
    UsuarioRol.objects.create(usuario=usuario, rol=Rol.objects.get(codigo="RESIDENTE"))
    c = cliente_de("ana")
    assert c.get(USUARIOS).status_code == 403
    assert c.post(USUARIOS, datos(), format="json").status_code == 403
    assert c.get(ROLES).status_code == 403


def test_permisos_dinamicos_usuarios_sin_roles(admin_client, cliente_de):
    """Un rol con solo 'usuarios.gestionar' lista usuarios pero no asigna roles."""
    rol = Rol.objects.create(codigo="SOLO_USUARIOS", nombre="Solo usuarios")
    RolPermiso.objects.create(rol=rol, permiso=Permiso.objects.get(codigo="usuarios.gestionar"))
    jefe = nuevo("jefe", "50")
    UsuarioRol.objects.create(usuario=jefe, rol=rol)
    otro = nuevo("otro", "51")

    c = cliente_de("jefe")
    assert c.get(USUARIOS).status_code == 200
    assert c.put(f"{USUARIOS}{otro.pk}/roles/", {"roles": ["ADMIN"]}, format="json").status_code == 403


# --- listar / filtrar / buscar (RF7) ----------------------------------------
def test_listar_filtrar_y_buscar(admin_client, usuario):
    inactivo = nuevo("beto", "2", activo=False)
    inactivo.apellidos = "Ruiz"
    inactivo.save()
    carla = nuevo("carla", "3")
    UsuarioRol.objects.create(usuario=carla, rol=Rol.objects.get(codigo="RESPONSABLE_PQR"))

    def usernames(query=""):
        r = admin_client.get(USUARIOS + query)
        assert r.status_code == 200
        return {u["username"] for u in r.data["results"]}

    assert {"root", "ana", "beto", "carla"} <= usernames()
    assert usernames("?activo=false") == {"beto"}
    assert usernames("?rol=RESPONSABLE_PQR") == {"carla"}
    assert usernames("?search=ruiz") == {"beto"}


def test_detalle_incluye_roles_y_permisos(admin_client, admin):
    r = admin_client.get(f"{USUARIOS}{admin.pk}/")
    assert r.status_code == 200
    assert r.data["roles"] == ["ADMIN"]
    assert "usuarios.gestionar" in r.data["permisos"]


# --- crear / editar (RF1) ------------------------------------------------------
def test_crear_usuario_por_defecto_es_residente(admin_client):
    r = admin_client.post(USUARIOS, datos(), format="json")
    assert r.status_code == 201
    assert r.data["roles"] == ["RESIDENTE"]
    assert "password" not in r.data


def test_crear_usuario_con_roles_explicitos(admin_client):
    r = admin_client.post(USUARIOS, datos(roles=["RESPONSABLE_PQR", "RESIDENTE"]), format="json")
    assert r.status_code == 201
    assert r.data["roles"] == ["RESIDENTE", "RESPONSABLE_PQR"]


def test_crear_usuario_con_rol_inexistente(admin_client):
    r = admin_client.post(USUARIOS, datos(roles=["SUPERMAN"]), format="json")
    assert r.status_code == 400
    assert "roles" in r.data


def test_editar_usuario_ignora_campos_protegidos(admin_client, usuario):
    r = admin_client.patch(
        f"{USUARIOS}{usuario.pk}/", {"nombres": "Anita", "username": "hack", "activo": False}, format="json"
    )
    assert r.status_code == 200
    usuario.refresh_from_db()
    assert (usuario.nombres, usuario.username, usuario.activo) == ("Anita", "ana", True)


def test_no_hay_put_ni_delete_sobre_usuarios(admin_client, usuario):
    assert admin_client.delete(f"{USUARIOS}{usuario.pk}/").status_code == 405
    assert admin_client.put(f"{USUARIOS}{usuario.pk}/", {}, format="json").status_code == 405


# --- activar / desactivar (RF8) -----------------------------------------------
def test_desactivar_corta_el_acceso_y_activar_lo_restaura(admin_client, usuario, cliente_de):
    sesion_ana = cliente_de("ana")  # token emitido antes de desactivarla
    assert admin_client.post(f"{USUARIOS}{usuario.pk}/desactivar/").data["activo"] is False

    assert sesion_ana.get("/api/v1/auth/me/").status_code == 401  # su token deja de servir
    login = sesion_ana.post(
        "/api/v1/auth/login/", {"username": "ana", "password": CLAVE}, format="json"
    )
    assert login.status_code == 401
    assert Usuario.objects.filter(pk=usuario.pk).exists()  # no se borra (conserva historial)

    assert admin_client.post(f"{USUARIOS}{usuario.pk}/activar/").data["activo"] is True
    assert cliente_de("ana").get("/api/v1/auth/me/").status_code == 200


def test_no_puede_desactivarse_a_si_mismo(admin_client, admin):
    assert admin_client.post(f"{USUARIOS}{admin.pk}/desactivar/").status_code == 400


# --- roles de un usuario (RF9) --------------------------------------------------
def test_asignar_y_reemplazar_roles_queda_auditado(admin_client, admin, usuario):
    r = admin_client.put(f"{USUARIOS}{usuario.pk}/roles/", {"roles": ["ADMIN", "RESIDENTE"]}, format="json")
    assert r.status_code == 200
    assert r.data["roles"] == ["ADMIN", "RESIDENTE"]

    r = admin_client.put(f"{USUARIOS}{usuario.pk}/roles/", {"roles": ["RESIDENTE"]}, format="json")
    assert r.data["roles"] == ["RESIDENTE"]

    assert Auditoria.objects.filter(tabla="usuarios_roles", usuario_id=admin.pk).exists()


def test_admin_no_puede_quitarse_su_propio_rol(admin_client, admin):
    r = admin_client.put(f"{USUARIOS}{admin.pk}/roles/", {"roles": ["RESIDENTE"]}, format="json")
    assert r.status_code == 400
    assert "roles" in r.data


def test_roles_vacios_no_se_aceptan(admin_client, usuario):
    assert admin_client.put(f"{USUARIOS}{usuario.pk}/roles/", {"roles": []}, format="json").status_code == 400


# --- roles y permisos (RF9) ---------------------------------------------------
def test_listar_roles_y_permisos(admin_client):
    roles = {r["codigo"]: r for r in admin_client.get(ROLES).data}
    assert {"ADMIN", "RESIDENTE", "RESPONSABLE_PQR"} <= set(roles)
    assert "usuarios.gestionar" in roles["ADMIN"]["permisos"]
    assert "pqr.radicar" in roles["RESIDENTE"]["permisos"]
    assert len(admin_client.get(PERMISOS).data) >= 14


def test_editar_permisos_de_un_rol(admin_client):
    residente = Rol.objects.get(codigo="RESIDENTE")
    r = admin_client.put(f"{ROLES}{residente.pk}/permisos/", {"permisos": ["pqr.radicar"]}, format="json")
    assert r.status_code == 200
    assert r.data["permisos"] == ["pqr.radicar"]


def test_permiso_inexistente_se_rechaza(admin_client):
    residente = Rol.objects.get(codigo="RESIDENTE")
    r = admin_client.put(f"{ROLES}{residente.pk}/permisos/", {"permisos": ["no.existe"]}, format="json")
    assert r.status_code == 400


def test_rol_admin_no_se_puede_modificar(admin_client):
    admin_rol = Rol.objects.get(codigo="ADMIN")
    r = admin_client.put(f"{ROLES}{admin_rol.pk}/permisos/", {"permisos": []}, format="json")
    assert r.status_code == 400
