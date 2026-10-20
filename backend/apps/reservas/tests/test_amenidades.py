import pytest

from apps.reservas.models import Amenidad, AmenidadHorario, ReglaReserva
from apps.usuarios.models import Rol, UsuarioRol

pytestmark = pytest.mark.django_db

URL = "/api/v1/amenidades/"


def datos(**cambios):
    base = {
        "nombre": "Piscina", "descripcion": "Piscina climatizada", "capacidad": 25,
        "horarios": [
            {"dia_semana": d, "hora_apertura": "09:00", "hora_cierre": "20:00"} for d in range(1, 8)
        ],
        "reglas": {"duracion_max_minutos": 120, "horas_limite_cancelacion": 6, "requiere_confirmacion": False},
    }
    base.update(cambios)
    return base


def test_admin_registra_amenidad_con_aforo_horarios_y_politicas(admin_client, copropiedad):
    r = admin_client.post(URL, datos(), format="json")
    assert r.status_code == 201, r.data
    assert r.data["capacidad"] == 25
    assert len(r.data["horarios"]) == 7
    assert r.data["reglas"]["horas_limite_cancelacion"] == 6
    assert r.data["reglas"]["requiere_confirmacion"] is False
    assert r.data["reglas"]["duracion_min_minutos"] == 30  # valor por defecto
    assert ReglaReserva.objects.filter(amenidad_id=r.data["id"]).exists()


def test_sin_reglas_se_crean_las_de_por_defecto(admin_client, copropiedad):
    r = admin_client.post(URL, {"nombre": "Gimnasio", "capacidad": 10}, format="json")
    assert r.status_code == 201, r.data
    assert r.data["reglas"]["horas_limite_cancelacion"] == 24


def test_residente_no_puede_registrar(residente_client, copropiedad):
    assert residente_client.post(URL, datos(), format="json").status_code == 403


def test_nombre_duplicado(admin_client, salon):
    r = admin_client.post(URL, datos(nombre="salón social"), format="json")
    assert r.status_code == 400


def test_validaciones_de_aforo_y_horarios(admin_client, copropiedad):
    assert admin_client.post(URL, datos(capacidad=0), format="json").status_code == 400
    solapados = [
        {"dia_semana": 1, "hora_apertura": "08:00", "hora_cierre": "12:00"},
        {"dia_semana": 1, "hora_apertura": "11:00", "hora_cierre": "14:00"},
    ]
    assert admin_client.post(URL, datos(horarios=solapados), format="json").status_code == 400
    invertido = [{"dia_semana": 1, "hora_apertura": "12:00", "hora_cierre": "08:00"}]
    assert admin_client.post(URL, datos(horarios=invertido), format="json").status_code == 400
    reglas = {"duracion_min_minutos": 200, "duracion_max_minutos": 100}
    assert admin_client.post(URL, datos(reglas=reglas), format="json").status_code == 400


def test_editar_aforo_horarios_y_politica(admin_client, salon):
    r = admin_client.patch(
        f"{URL}{salon.pk}/",
        {
            "capacidad": 35,
            "horarios": [{"dia_semana": 6, "hora_apertura": "10:00", "hora_cierre": "23:00"}],
            "reglas": {"horas_limite_cancelacion": 72},
        },
        format="json",
    )
    assert r.status_code == 200, r.data
    assert r.data["capacidad"] == 35
    assert len(r.data["horarios"]) == 1  # el horario se reemplaza completo
    assert r.data["reglas"]["horas_limite_cancelacion"] == 72
    assert r.data["reglas"]["max_reservas_mes_inmueble"] == 2  # PATCH parcial: lo demás se conserva
    assert AmenidadHorario.objects.filter(amenidad=salon).count() == 1


def test_desactivar_oculta_la_amenidad_al_residente(admin_client, residente_client, salon):
    assert len(residente_client.get(URL).data) == 1
    assert admin_client.post(f"{URL}{salon.pk}/desactivar/").status_code == 200
    assert residente_client.get(URL).data == []
    assert len(admin_client.get(URL).data) == 1
    assert admin_client.post(f"{URL}{salon.pk}/activar/").data["activa"] is True


def test_no_hay_delete(admin_client, salon):
    assert admin_client.delete(f"{URL}{salon.pk}/").status_code == 405


def test_permiso_configuracion_gestionar_basta_para_configurar(cliente_de, salon):
    from apps.usuarios.models import Permiso, RolPermiso, Usuario

    rol = Rol.objects.create(codigo="CONFIG", nombre="Configurador")
    RolPermiso.objects.create(rol=rol, permiso=Permiso.objects.get(codigo="configuracion.gestionar"))
    u = Usuario.objects.create_user(
        username="cfg", email="cfg@example.com", password="Clave12345!",
        nombres="Cfg", apellidos="Uno", numero_documento="77",
    )
    UsuarioRol.objects.create(usuario=u, rol=rol)
    c = cliente_de("cfg")
    assert c.patch(f"{URL}{salon.pk}/", {"capacidad": 50}, format="json").status_code == 200
    assert Amenidad.objects.get(pk=salon.pk).capacidad == 50
