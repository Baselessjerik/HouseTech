"""Lógica de negocio del Módulo 2: mantenimientos, bloqueos, comunicados y notificaciones.

Las vistas solo validan entrada y llaman a estas funciones. Todas escriben dentro de la
transacción de la petición (ATOMIC_REQUESTS) y, fuera de una petición (comandos), dentro
de su propio `transaction.atomic()`.
"""
import os
from datetime import timedelta

from django.core.mail import send_mail
from django.db import connection, transaction
from django.db.models import Exists, OuterRef, Q
from django.utils import timezone
from rest_framework.exceptions import APIException, ValidationError

from apps.core.models import Estado
from apps.usuarios.models import Rol, Usuario

from .models import (
    AmenidadRef,
    Bloqueo,
    Comunicado,
    ComunicadoDestinatario,
    Mantenimiento,
    Notificacion,
    ReservaRef,
)

BORRADOR, PROGRAMADO, PUBLICADO, ARCHIVADO = "BORRADOR", "PROGRAMADO", "PUBLICADO", "ARCHIVADO"
TODOS, ROL, USUARIOS = "TODOS", "ROL", "USUARIOS"

PERMISO_VER = "comunicados.ver"
PERMISO_GESTIONAR = "comunicados.gestionar"
TOLERANCIA_PASADO = timedelta(minutes=5)  # permite "bloquear desde ahora"

TRANSICIONES_MANTENIMIENTO = {
    "PROGRAMADO": {"EN_CURSO", "CANCELADO"},
    "EN_CURSO": {"FINALIZADO", "CANCELADO"},
}


class Conflicto(APIException):
    """HTTP 409 con un cuerpo propio (el dict no se normaliza a texto)."""

    status_code = 409
    default_code = "conflicto"

    def __init__(self, payload):
        self.detail = payload


# --------------------------------------------------------------------------- utilidades
def _ahora():
    return timezone.now()


def _estado_mantenimiento(codigo):
    return Estado.objects.get(proceso="MANTENIMIENTO", codigo=codigo)


def _correos_habilitados():
    return os.environ.get("COMUNICADOS_NOTIFICAR_EMAIL", "false").strip().lower() in ("1", "true", "si", "sí", "yes")


def usuarios_con_permiso(codigo):
    """Usuarios activos que tienen el permiso a través de alguno de sus roles activos."""
    return Usuario.objects.filter(
        activo=True,
        usuario_roles__rol__activo=True,
        usuario_roles__rol__rol_permisos__permiso__codigo=codigo,
    ).distinct()


def crear_notificaciones(usuarios, *, tipo, titulo, mensaje, referencia_tipo=None, referencia_id=None):
    """Inserta una notificación (canal APP) por usuario. Acepta ids u objetos Usuario."""
    ids = sorted({getattr(u, "pk", u) for u in usuarios})
    if not ids:
        return 0
    ahora = _ahora()
    Notificacion.objects.bulk_create(
        [
            Notificacion(
                usuario_id=uid,
                tipo=tipo,
                titulo=titulo[:200],
                mensaje=mensaje,
                referencia_tipo=referencia_tipo,
                referencia_id=referencia_id,
                canal="APP",
                enviada_en=ahora,
            )
            for uid in ids
        ],
        batch_size=500,
    )
    return len(ids)


def _enviar_correos(ids, asunto, cuerpo):
    """Correo opcional (COMUNICADOS_NOTIFICAR_EMAIL=true). Nunca rompe la operación."""
    if not _correos_habilitados() or not ids:
        return
    destinos = list(Usuario.objects.filter(pk__in=ids, activo=True).values_list("email", flat=True))
    for correo in destinos:
        try:
            send_mail(asunto, cuerpo, None, [correo], fail_silently=True)
        except Exception:  # noqa: BLE001
            continue


def _resumen(texto, largo=180):
    texto = " ".join((texto or "").split())
    return texto if len(texto) <= largo else texto[: largo - 1] + "…"


# -------------------------------------------------------------- reservas y cruces (RF3, RF5)
def reservas_en_conflicto(amenidad_id, inicio, fin):
    return list(
        ReservaRef.objects.filter(
            amenidad_id=amenidad_id,
            estado__es_final=False,
            fecha_inicio__lt=fin,
            fecha_fin__gt=inicio,
        ).select_related("usuario", "estado")
    )


def _datos_reserva(r):
    return {
        "id": r.pk,
        "usuario_id": r.usuario_id,
        "usuario": r.usuario.nombre_completo,
        "fecha_inicio": r.fecha_inicio.isoformat(),
        "fecha_fin": r.fecha_fin.isoformat(),
        "estado": r.estado.codigo,
    }


def _verificar_bloqueo(amenidad_id, inicio, fin, *, excluir_id=None, confirmar=False):
    """Lanza 409 si el rango choca con otro bloqueo o con reservas (salvo confirmar)."""
    cruzados = Bloqueo.objects.filter(
        amenidad_id=amenidad_id, cancelado=False, fecha_inicio__lt=fin, fecha_fin__gt=inicio
    )
    if excluir_id:
        cruzados = cruzados.exclude(pk=excluir_id)
    cruzados = list(cruzados[:10])
    if cruzados:
        raise Conflicto(
            {
                "detail": "La amenidad ya tiene un bloqueo activo que se cruza con ese horario.",
                "codigo": "bloqueo_cruzado",
                "bloqueos": [
                    {"id": b.pk, "fecha_inicio": b.fecha_inicio.isoformat(), "fecha_fin": b.fecha_fin.isoformat(),
                     "motivo": b.motivo}
                    for b in cruzados
                ],
            }
        )
    reservas = reservas_en_conflicto(amenidad_id, inicio, fin)
    if reservas and not confirmar:
        raise Conflicto(
            {
                "detail": f"Hay {len(reservas)} reserva(s) en ese horario. Confirma para continuar y avisar a sus dueños.",
                "codigo": "reservas_en_conflicto",
                "reservas": [_datos_reserva(r) for r in reservas],
            }
        )
    return reservas


def _validar_rango_nuevo(inicio, fin):
    if fin <= inicio:
        raise ValidationError({"fecha_fin": "La fecha de fin debe ser posterior a la de inicio."})
    if inicio < _ahora() - TOLERANCIA_PASADO:
        raise ValidationError({"fecha_inicio": "La fecha de inicio no puede estar en el pasado."})


def _notificar_reservas_afectadas(reservas, titulo, mensaje, referencia_id):
    if not reservas:
        return
    crear_notificaciones(
        {r.usuario_id for r in reservas},
        tipo="RESERVA",
        titulo=titulo,
        mensaje=mensaje,
        referencia_tipo="bloqueo",
        referencia_id=referencia_id,
    )


def _fmt(dt):
    return timezone.localtime(dt).strftime("%d/%m/%Y %H:%M")


# ------------------------------------------------------------------ bloqueos (RF2-RF5, RF7)
def _notificar_bloqueo(b, accion):
    zona = b.amenidad.nombre
    verbos = {"creado": "programado", "modificado": "modificado", "cancelado": "cancelado"}
    titulo = f"Bloqueo {verbos[accion]}: {zona}"
    if accion == "cancelado":
        mensaje = f"Se canceló el bloqueo de {zona} previsto del {_fmt(b.fecha_inicio)} al {_fmt(b.fecha_fin)}."
    else:
        mensaje = (
            f"{zona} no estará disponible del {_fmt(b.fecha_inicio)} al {_fmt(b.fecha_fin)}. "
            f"Motivo: {_resumen(b.motivo, 120)}"
        )
    destinatarios = list(usuarios_con_permiso(PERMISO_VER).values_list("pk", flat=True))
    crear_notificaciones(
        destinatarios, tipo="BLOQUEO", titulo=titulo, mensaje=mensaje,
        referencia_tipo="bloqueo", referencia_id=b.pk,
    )
    _enviar_correos(destinatarios, titulo, mensaje)


@transaction.atomic
def crear_bloqueo(datos, usuario, *, confirmar=False):
    amenidad = datos["amenidad"]
    inicio, fin = datos["fecha_inicio"], datos["fecha_fin"]
    _validar_rango_nuevo(inicio, fin)
    reservas = _verificar_bloqueo(amenidad.pk, inicio, fin, confirmar=confirmar)
    b = Bloqueo.objects.create(
        amenidad=amenidad,
        mantenimiento=datos.get("mantenimiento"),
        fecha_inicio=inicio,
        fecha_fin=fin,
        motivo=datos["motivo"],
        creado_por=usuario,
    )
    _notificar_reservas_afectadas(
        reservas,
        f"Tu reserva en {amenidad.nombre} coincide con un bloqueo",
        f"La administración bloqueó {amenidad.nombre} del {_fmt(inicio)} al {_fmt(fin)}. "
        "Comunícate con la administración para reprogramar tu reserva.",
        b.pk,
    )
    _notificar_bloqueo(b, "creado")
    return b


def _bloqueo_editable(b):
    if b.cancelado:
        raise ValidationError({"detail": "No se puede modificar un bloqueo cancelado."})
    if b.fecha_fin <= _ahora():
        raise ValidationError({"detail": "No se puede modificar un bloqueo que ya finalizó."})


@transaction.atomic
def modificar_bloqueo(b, datos, usuario, *, confirmar=False):
    _bloqueo_editable(b)
    inicio = datos.get("fecha_inicio", b.fecha_inicio)
    fin = datos.get("fecha_fin", b.fecha_fin)
    cambia_rango = (inicio, fin) != (b.fecha_inicio, b.fecha_fin)
    if fin <= inicio:
        raise ValidationError({"fecha_fin": "La fecha de fin debe ser posterior a la de inicio."})
    reservas = []
    if cambia_rango:
        if fin <= _ahora():
            raise ValidationError({"fecha_fin": "La nueva fecha de fin no puede estar en el pasado."})
        reservas = _verificar_bloqueo(b.amenidad_id, inicio, fin, excluir_id=b.pk, confirmar=confirmar)
    b.fecha_inicio, b.fecha_fin = inicio, fin
    if "motivo" in datos:
        b.motivo = datos["motivo"]
    b.save(update_fields=["fecha_inicio", "fecha_fin", "motivo", "updated_at"])
    if cambia_rango:
        _notificar_reservas_afectadas(
            reservas,
            f"Tu reserva en {b.amenidad.nombre} coincide con un bloqueo",
            f"{b.amenidad.nombre} quedó bloqueada del {_fmt(inicio)} al {_fmt(fin)}. "
            "Comunícate con la administración para reprogramar tu reserva.",
            b.pk,
        )
    _notificar_bloqueo(b, "modificado")
    return b


@transaction.atomic
def cancelar_bloqueo(b, usuario):
    if b.cancelado:
        raise ValidationError({"detail": "El bloqueo ya está cancelado."})
    b.cancelado = True
    b.cancelado_en = _ahora()
    b.save(update_fields=["cancelado", "cancelado_en", "updated_at"])
    _notificar_bloqueo(b, "cancelado")
    return b


def estado_bloqueo(b, ahora=None):
    ahora = ahora or _ahora()
    if b.cancelado:
        return "CANCELADO"
    if b.fecha_fin <= ahora:
        return "FINALIZADO"
    if b.fecha_inicio > ahora:
        return "PROGRAMADO"
    return "ACTIVO"


# -------------------------------------------------------------- mantenimientos (RF1, RF8)
def _notificar_mantenimiento(m, accion):
    verbos = {
        "creado": "programado",
        "modificado": "modificado",
        "iniciado": "en curso",
        "finalizado": "finalizado",
        "cancelado": "cancelado",
    }
    lugar = m.amenidad.nombre if m.amenidad_id else "zonas comunes"
    titulo = f"Mantenimiento {verbos[accion]}: {m.titulo}"
    mensaje = f"{lugar}: del {_fmt(m.fecha_inicio)} al {_fmt(m.fecha_fin)}."
    if m.descripcion:
        mensaje += f" {_resumen(m.descripcion, 120)}"
    destinatarios = list(usuarios_con_permiso(PERMISO_VER).values_list("pk", flat=True))
    crear_notificaciones(
        destinatarios, tipo="MANTENIMIENTO", titulo=titulo, mensaje=mensaje,
        referencia_tipo="mantenimiento", referencia_id=m.pk,
    )
    _enviar_correos(destinatarios, titulo, mensaje)


@transaction.atomic
def crear_mantenimiento(datos, usuario, *, crear_bloqueo_asociado=False, confirmar=False):
    amenidad = datos.get("amenidad")
    inicio, fin = datos["fecha_inicio"], datos["fecha_fin"]
    if fin <= inicio:
        raise ValidationError({"fecha_fin": "La fecha de fin debe ser posterior a la de inicio."})
    if fin <= _ahora():
        raise ValidationError({"fecha_fin": "El mantenimiento debe terminar en el futuro."})
    if crear_bloqueo_asociado and amenidad is None:
        raise ValidationError({"crear_bloqueo": "Selecciona una amenidad para crear el bloqueo."})
    reservas = []
    if crear_bloqueo_asociado:
        reservas = _verificar_bloqueo(amenidad.pk, inicio, fin, confirmar=confirmar)

    m = Mantenimiento.objects.create(
        amenidad=amenidad,
        titulo=datos["titulo"],
        descripcion=datos.get("descripcion") or None,
        fecha_inicio=inicio,
        fecha_fin=fin,
        estado=_estado_mantenimiento("PROGRAMADO"),
        responsable=datos.get("responsable") or None,
        creado_por=usuario,
    )
    if crear_bloqueo_asociado:
        b = Bloqueo.objects.create(
            amenidad=amenidad, mantenimiento=m, fecha_inicio=inicio, fecha_fin=fin,
            motivo=f"Mantenimiento: {m.titulo}", creado_por=usuario,
        )
        _notificar_reservas_afectadas(
            reservas,
            f"Tu reserva en {amenidad.nombre} coincide con un mantenimiento",
            f"{amenidad.nombre} tendrá mantenimiento del {_fmt(inicio)} al {_fmt(fin)}. "
            "Comunícate con la administración para reprogramar tu reserva.",
            b.pk,
        )
    _notificar_mantenimiento(m, "creado")
    return m


def _mantenimiento_editable(m):
    if m.estado.codigo not in TRANSICIONES_MANTENIMIENTO:
        raise ValidationError({"detail": "Solo se pueden modificar mantenimientos programados o en curso."})


@transaction.atomic
def modificar_mantenimiento(m, datos, usuario, *, confirmar=False):
    _mantenimiento_editable(m)
    inicio = datos.get("fecha_inicio", m.fecha_inicio)
    fin = datos.get("fecha_fin", m.fecha_fin)
    if fin <= inicio:
        raise ValidationError({"fecha_fin": "La fecha de fin debe ser posterior a la de inicio."})
    cambia_rango = (inicio, fin) != (m.fecha_inicio, m.fecha_fin)
    if cambia_rango and fin <= _ahora():
        raise ValidationError({"fecha_fin": "La nueva fecha de fin no puede estar en el pasado."})

    bloqueos_asociados = list(m.bloqueos.filter(cancelado=False, fecha_fin__gt=_ahora()))
    reservas = []
    if cambia_rango:
        for b in bloqueos_asociados:
            reservas += _verificar_bloqueo(b.amenidad_id, inicio, fin, excluir_id=b.pk, confirmar=confirmar)

    if "titulo" in datos:
        m.titulo = datos["titulo"]
    for campo in ("descripcion", "responsable"):
        if campo in datos:
            setattr(m, campo, datos[campo] or None)
    if "amenidad" in datos and not bloqueos_asociados:
        m.amenidad = datos["amenidad"]
    m.fecha_inicio, m.fecha_fin = inicio, fin
    m.save()

    if cambia_rango:
        for b in bloqueos_asociados:
            b.fecha_inicio, b.fecha_fin = inicio, fin
            b.save(update_fields=["fecha_inicio", "fecha_fin", "updated_at"])
        _notificar_reservas_afectadas(
            reservas,
            "Tu reserva coincide con un mantenimiento",
            f"El mantenimiento «{m.titulo}» quedó del {_fmt(inicio)} al {_fmt(fin)}. "
            "Comunícate con la administración para reprogramar tu reserva.",
            m.pk,
        )
    _notificar_mantenimiento(m, "modificado")
    return m


@transaction.atomic
def cambiar_estado_mantenimiento(m, nuevo_codigo, usuario):
    actual = m.estado.codigo
    if nuevo_codigo not in TRANSICIONES_MANTENIMIENTO.get(actual, set()):
        raise ValidationError({"estado": f"No se puede pasar un mantenimiento de {actual} a {nuevo_codigo}."})
    m.estado = _estado_mantenimiento(nuevo_codigo)
    m.save(update_fields=["estado", "updated_at"])
    if nuevo_codigo in ("FINALIZADO", "CANCELADO"):
        # libera la amenidad: cancela los bloqueos asociados que aún estén vigentes o por venir
        ahora = _ahora()
        m.bloqueos.filter(cancelado=False, fecha_fin__gt=ahora).update(cancelado=True, cancelado_en=ahora)
    accion = {"EN_CURSO": "iniciado", "FINALIZADO": "finalizado", "CANCELADO": "cancelado"}[nuevo_codigo]
    _notificar_mantenimiento(m, accion)
    return m


# -------------------------------------------------------------- disponibilidad (RF6)
def disponibilidad(momento=None, amenidad_id=None):
    """Estado de las amenidades activas en un momento, usando fn_estado_amenidad de la BD."""
    momento = momento or _ahora()
    sql = "SELECT a.id, fn_estado_amenidad(a.id, %s::timestamptz) FROM amenidades a WHERE a.activa"
    params = [momento]
    if amenidad_id is not None:
        sql += " AND a.id = %s"
        params.append(amenidad_id)
    with connection.cursor() as cursor:
        cursor.execute(sql, params)
        estados = dict(cursor.fetchall())
    if not estados:
        return []

    amenidades = list(AmenidadRef.objects.filter(pk__in=estados).order_by("nombre"))
    bloqueos, mantenimientos, reservas = {}, {}, {}
    for b in Bloqueo.objects.filter(amenidad_id__in=estados, cancelado=False, fecha_fin__gt=momento).order_by(
        "fecha_inicio"
    ):
        bloqueos.setdefault(b.amenidad_id, []).append(b)
    for m in Mantenimiento.objects.filter(
        amenidad_id__in=estados, estado__es_final=False, fecha_fin__gt=momento
    ).order_by("fecha_inicio"):
        mantenimientos.setdefault(m.amenidad_id, []).append(m)
    for r in ReservaRef.objects.filter(
        amenidad_id__in=estados, estado__es_final=False, fecha_inicio__lte=momento, fecha_fin__gt=momento
    ):
        reservas[r.amenidad_id] = r

    def _bloque(obj, titulo):
        return {
            "id": obj.pk,
            "fecha_inicio": obj.fecha_inicio,
            "fecha_fin": obj.fecha_fin,
            "motivo": titulo,
        }

    resultado = []
    for a in amenidades:
        estado = estados[a.pk]
        bl = bloqueos.get(a.pk, [])
        mt = mantenimientos.get(a.pk, [])
        actual_b = next((b for b in bl if b.fecha_inicio <= momento), None)
        actual_m = next((m for m in mt if m.fecha_inicio <= momento), None)
        proximo_b = next((b for b in bl if b.fecha_inicio > momento), None)
        proximo_m = next((m for m in mt if m.fecha_inicio > momento), None)

        motivo = desde = hasta = None
        if estado == "EN_MANTENIMIENTO" and actual_m:
            motivo, desde, hasta = actual_m.titulo, actual_m.fecha_inicio, actual_m.fecha_fin
        elif estado == "BLOQUEADA" and actual_b:
            motivo, desde, hasta = actual_b.motivo, actual_b.fecha_inicio, actual_b.fecha_fin
        elif estado == "RESERVADA" and a.pk in reservas:
            desde, hasta = reservas[a.pk].fecha_inicio, reservas[a.pk].fecha_fin

        resultado.append(
            {
                "id": a.pk,
                "nombre": a.nombre,
                "descripcion": a.descripcion,
                "capacidad": a.capacidad,
                "estado": estado,
                "motivo": motivo,
                "desde": desde,
                "hasta": hasta,
                "proximo_bloqueo": _bloque(proximo_b, proximo_b.motivo) if proximo_b else None,
                "proximo_mantenimiento": _bloque(proximo_m, proximo_m.titulo) if proximo_m else None,
            }
        )
    return resultado


# ------------------------------------------------------------------ comunicados (RF9-RF16)
def destinatarios_de(c):
    """Usuarios activos a los que va dirigido el comunicado."""
    if c.audiencia == TODOS:
        return usuarios_con_permiso(PERMISO_VER)
    if c.audiencia == ROL:
        return Usuario.objects.filter(
            activo=True, usuario_roles__rol_id=c.rol_destino_id, usuario_roles__rol__activo=True
        ).distinct()
    ids = ComunicadoDestinatario.objects.filter(comunicado_id=c.pk).values_list("usuario_id", flat=True)
    return Usuario.objects.filter(activo=True, pk__in=list(ids))


def ids_destinatarios(c):
    return list(ComunicadoDestinatario.objects.filter(comunicado_id=c.pk).values_list("usuario_id", flat=True))


def _reemplazar_destinatarios(c, ids):
    with connection.cursor() as cursor:
        cursor.execute("DELETE FROM comunicado_destinatarios WHERE comunicado_id = %s", [c.pk])
        if ids:
            cursor.executemany(
                "INSERT INTO comunicado_destinatarios (comunicado_id, usuario_id) VALUES (%s, %s)",
                [(c.pk, uid) for uid in sorted(set(ids))],
            )


@transaction.atomic
def crear_comunicado(datos, usuario):
    datos = dict(datos)
    destinatarios = datos.pop("destinatarios", [])
    c = Comunicado.objects.create(autor=usuario, estado=BORRADOR, **datos)
    if c.audiencia == USUARIOS:
        _reemplazar_destinatarios(c, destinatarios)
    return c


@transaction.atomic
def modificar_comunicado(c, datos, usuario):
    if c.estado == ARCHIVADO:
        raise ValidationError({"detail": "Un comunicado archivado no se puede modificar."})
    datos = dict(datos)
    destinatarios = datos.pop("destinatarios", None)
    for campo, valor in datos.items():
        setattr(c, campo, valor)
    if c.audiencia != ROL:
        c.rol_destino = None
    c.save()
    if c.audiencia == USUARIOS:
        if destinatarios is not None:
            _reemplazar_destinatarios(c, destinatarios)
    else:
        _reemplazar_destinatarios(c, [])
    return c


def notificar_comunicado(c):
    """RF16: avisa a la audiencia que se publicó un comunicado nuevo."""
    ids = list(destinatarios_de(c).values_list("pk", flat=True))
    titulo = f"Nuevo comunicado: {c.titulo}"
    mensaje = _resumen(c.contenido)
    crear_notificaciones(
        ids, tipo="COMUNICADO", titulo=titulo, mensaje=mensaje,
        referencia_tipo="comunicado", referencia_id=c.pk,
    )
    _enviar_correos(ids, titulo, c.contenido)
    return len(ids)


@transaction.atomic
def publicar_comunicado(c, usuario=None):
    if c.estado not in (BORRADOR, PROGRAMADO):
        raise ValidationError({"estado": f"No se puede publicar un comunicado en estado {c.estado}."})
    ahora = _ahora()
    if c.fecha_expiracion and c.fecha_expiracion <= ahora:
        raise ValidationError({"fecha_expiracion": "La fecha de expiración ya pasó; edítala antes de publicar."})
    c.estado = PUBLICADO
    c.fecha_publicacion = ahora
    c.save(update_fields=["estado", "fecha_publicacion", "updated_at"])
    notificar_comunicado(c)
    return c


@transaction.atomic
def programar_comunicado(c, fecha):
    if c.estado not in (BORRADOR, PROGRAMADO):
        raise ValidationError({"estado": f"No se puede programar un comunicado en estado {c.estado}."})
    if fecha <= _ahora():
        raise ValidationError({"fecha_programada": "La fecha de publicación debe ser futura."})
    if c.fecha_expiracion and c.fecha_expiracion <= fecha:
        raise ValidationError({"fecha_programada": "La publicación debe ser anterior a la fecha de expiración."})
    c.estado = PROGRAMADO
    c.fecha_programada = fecha
    c.save(update_fields=["estado", "fecha_programada", "updated_at"])
    return c


@transaction.atomic
def archivar_comunicado(c, usuario=None):
    if c.estado == ARCHIVADO:
        raise ValidationError({"estado": "El comunicado ya está archivado."})
    c.estado = ARCHIVADO
    c.save(update_fields=["estado", "updated_at"])
    return c


def publicar_programados_vencidos():
    """RF13: publica los comunicados PROGRAMADOS cuya fecha ya llegó. Es idempotente.

    Se invoca desde el comando `publicar_comunicados_programados` (cron) y de forma
    perezosa al consultar avisos, para que un residente nunca vea un aviso vencido sin publicar.
    """
    ahora = _ahora()
    ids = list(
        Comunicado.objects.filter(estado=PROGRAMADO, fecha_programada__lte=ahora)
        .values_list("pk", flat=True)
    )
    publicados = 0
    for pk in ids:
        with transaction.atomic():
            c = (
                Comunicado.objects.select_for_update(skip_locked=True)
                .filter(pk=pk, estado=PROGRAMADO)
                .first()
            )
            if c is None:
                continue
            if c.fecha_expiracion and c.fecha_expiracion <= ahora:
                c.estado = ARCHIVADO  # venció antes de poder publicarse
                c.save(update_fields=["estado", "updated_at"])
                continue
            publicar_comunicado(c)
            publicados += 1
    return publicados


def comunicados_visibles(usuario, ahora=None):
    """Comunicados PUBLICADOS y vigentes que `usuario` puede ver (RF14)."""
    ahora = ahora or _ahora()
    qs = Comunicado.objects.filter(estado=PUBLICADO).filter(
        Q(fecha_expiracion__isnull=True) | Q(fecha_expiracion__gt=ahora)
    )
    if usuario.tiene_permiso(PERMISO_GESTIONAR):
        return qs
    roles = list(
        Rol.objects.filter(activo=True, rol_usuarios__usuario_id=usuario.pk).values_list("pk", flat=True)
    )
    es_destinatario = Exists(
        ComunicadoDestinatario.objects.filter(comunicado_id=OuterRef("pk"), usuario_id=usuario.pk)
    )
    return qs.annotate(_es_destinatario=es_destinatario).filter(
        Q(audiencia=TODOS)
        | Q(audiencia=ROL, rol_destino_id__in=roles)
        | Q(audiencia=USUARIOS, _es_destinatario=True)
    )
