"""Lógica de negocio de amenidades, disponibilidad, reservas y bloqueos (fuera de las vistas).

Regla de oro: toda validación se hace aquí para dar mensajes claros (400/409) y, además,
los triggers de PostgreSQL (sql/reservas_v2.sql) actúan como respaldo ante concurrencia.
"""
from __future__ import annotations

import datetime as dt

from contextlib import contextmanager

from django.db import connection, transaction
from django.utils import timezone
from rest_framework import status
from rest_framework.exceptions import APIException, PermissionDenied, ValidationError

from apps.core.models import Copropiedad, Estado
from apps.inmuebles.models import InmuebleUsuario

from . import avisos
from .models import Amenidad, BloqueoAmenidad, ReglaReserva, Reserva
from .tiempo import horas as _horas
from .tiempo import restar_intervalos

ESTADOS_ACTIVOS = ("SOLICITADA", "CONFIRMADA")  # ocupan la amenidad
ESTADOS_CUENTAN_CUPO = ("SOLICITADA", "CONFIRMADA", "FINALIZADA")
ESTADOS_RESERVA = ("SOLICITADA", "CONFIRMADA", "FINALIZADA", "RECHAZADA", "CANCELADA", "EXPIRADA")
MOTIVOS_CONFLICTO = {"RESERVA_SOLAPADA", "BLOQUEADA"}  # → HTTP 409; el resto → HTTP 400

TRANSICIONES = {
    "SOLICITADA": {"CONFIRMADA", "RECHAZADA", "CANCELADA", "EXPIRADA"},  # EXPIRADA solo la aplica el sistema
    "CONFIRMADA": {"CANCELADA", "FINALIZADA"},
}


class ReservaNoPermitida(APIException):
    """Incumple reglas de reserva. 409 si hay conflicto de agenda; 400 si es una regla/política."""

    default_detail = "La reserva no es posible."
    default_code = "reserva_no_permitida"

    def __init__(self, motivos: list[dict]):
        conflicto = any(m["codigo"] in MOTIVOS_CONFLICTO for m in motivos)
        self.status_code = status.HTTP_409_CONFLICT if conflicto else status.HTTP_400_BAD_REQUEST
        super().__init__({"detail": "; ".join(m["detalle"] for m in motivos), "motivos": motivos})


# --- utilidades --------------------------------------------------------------
def inicio_dia(fecha: dt.date) -> dt.datetime:
    """Medianoche local (America/Bogota) de la fecha, con zona horaria."""
    return timezone.make_aware(dt.datetime.combine(fecha, dt.time.min))


def combinar(fecha: dt.date, hora: dt.time) -> dt.datetime:
    return timezone.make_aware(dt.datetime.combine(fecha, hora))


def iso_local(valor: dt.datetime) -> str:
    return timezone.localtime(valor).isoformat()


def _hhmm(valor: dt.datetime) -> str:
    return timezone.localtime(valor).strftime("%H:%M")


def es_gestor(usuario) -> bool:
    return usuario.tiene_permiso("amenidades.gestionar")


def estado_reserva(codigo: str) -> Estado:
    try:
        return Estado.objects.get(proceso="RESERVA", codigo=codigo)
    except Estado.DoesNotExist:  # pragma: no cover - el esquema siembra estos estados
        raise ValidationError({"detail": f"El estado de reserva '{codigo}' no está configurado."})


def obtener_regla(amenidad: Amenidad) -> ReglaReserva:
    """Reglas guardadas o, si faltan, las de por defecto (mismas del esquema SQL)."""
    try:
        return amenidad.reglas
    except ReglaReserva.DoesNotExist:
        return ReglaReserva(amenidad=amenidad)


def copropiedad_por_defecto() -> Copropiedad:
    copropiedades = list(Copropiedad.objects.order_by("id")[:2])
    if not copropiedades:
        raise ValidationError({"copropiedad": "No hay una copropiedad registrada."})
    if len(copropiedades) > 1:
        raise ValidationError({"copropiedad": "Indica a cuál copropiedad pertenece la amenidad."})
    return copropiedades[0]


def estado_actual_amenidad(amenidad_id: int, momento: dt.datetime | None = None) -> str:
    """DISPONIBLE / RESERVADA / BLOQUEADA / EN_MANTENIMIENTO (función SQL fn_estado_amenidad)."""
    with connection.cursor() as cursor:
        cursor.execute("SELECT fn_estado_amenidad(%s::bigint, %s::timestamptz)", [amenidad_id, momento or timezone.now()])
        return cursor.fetchone()[0]


# --- consultas de ocupación ----------------------------------------------------
def reservas_en_rango(amenidad_id, inicio, fin, *, excluir_id=None):
    """Reservas vigentes (no finales) que se solapan con [inicio, fin)."""
    qs = Reserva.objects.filter(
        amenidad_id=amenidad_id, fecha_inicio__lt=fin, fecha_fin__gt=inicio, estado__es_final=False
    )
    return qs.exclude(pk=excluir_id) if excluir_id else qs


def bloqueos_en_rango(amenidad_id, inicio, fin):
    return BloqueoAmenidad.objects.filter(
        amenidad_id=amenidad_id, cancelado=False, fecha_inicio__lt=fin, fecha_fin__gt=inicio
    )


# --- RF5-RF6: verificar disponibilidad -------------------------------------------
def verificar_disponibilidad(
    amenidad: Amenidad,
    inicio: dt.datetime,
    fin: dt.datetime,
    *,
    num_personas: int | None = None,
    inmueble=None,
    excluir_reserva_id: int | None = None,
    ahora: dt.datetime | None = None,
) -> list[dict]:
    """Devuelve la lista de motivos por los que NO se puede reservar (vacía = disponible).

    Comprueba: amenidad activa, fechas, horario de funcionamiento, duración, anticipación,
    aforo, cupo mensual por inmueble, solapamiento con otras reservas y con bloqueos.
    """
    ahora = ahora or timezone.now()
    motivos: list[dict] = []

    def motivo(codigo, detalle):
        motivos.append({"codigo": codigo, "detalle": detalle})

    if not amenidad.activa:
        motivo("AMENIDAD_INACTIVA", f"La amenidad '{amenidad.nombre}' no está disponible para reservas.")
    if fin <= inicio:
        motivo("FECHAS_INVALIDAS", "La hora de fin debe ser posterior a la hora de inicio.")
        return motivos

    regla = obtener_regla(amenidad)
    ini_local, fin_local = timezone.localtime(inicio), timezone.localtime(fin)

    # Horario de funcionamiento (la reserva debe caber en un mismo día y en una franja abierta)
    if ini_local.date() != fin_local.date():
        motivo("FUERA_HORARIO", "La reserva debe empezar y terminar el mismo día.")
    else:
        cabe = amenidad.horarios.filter(
            activo=True,
            dia_semana=ini_local.isoweekday(),
            hora_apertura__lte=ini_local.time(),
            hora_cierre__gte=fin_local.time(),
        ).exists()
        if not cabe:
            motivo("FUERA_HORARIO", "La amenidad no funciona en el horario solicitado.")

    # Duración
    minutos = (fin - inicio).total_seconds() / 60
    if minutos < regla.duracion_min_minutos:
        motivo("DURACION_MIN", f"La duración mínima es de {regla.duracion_min_minutos} minutos.")
    if minutos > regla.duracion_max_minutos:
        motivo("DURACION_MAX", f"La duración máxima es de {regla.duracion_max_minutos} minutos.")

    # Anticipación
    if inicio < ahora + dt.timedelta(hours=regla.anticipacion_min_horas):
        motivo("ANTICIPACION_MIN", f"Debes reservar con al menos {regla.anticipacion_min_horas} hora(s) de anticipación.")
    if inicio > ahora + dt.timedelta(days=regla.anticipacion_max_dias):
        motivo("ANTICIPACION_MAX", f"Solo puedes reservar con máximo {regla.anticipacion_max_dias} día(s) de anticipación.")

    # Aforo
    if amenidad.capacidad and num_personas is not None and num_personas > amenidad.capacidad:
        motivo("AFORO_EXCEDIDO", f"El aforo máximo es de {amenidad.capacidad} personas ({num_personas} solicitadas).")

    # Cupo mensual por inmueble
    if regla.max_reservas_mes_inmueble and inmueble is not None:
        inicio_mes = ini_local.replace(day=1, hour=0, minute=0, second=0, microsecond=0)
        fin_mes = (inicio_mes + dt.timedelta(days=32)).replace(day=1)
        usadas = Reserva.objects.filter(
            amenidad=amenidad,
            inmueble=inmueble,
            estado__codigo__in=ESTADOS_CUENTAN_CUPO,
            fecha_inicio__gte=inicio_mes,
            fecha_inicio__lt=fin_mes,
        )
        if excluir_reserva_id:
            usadas = usadas.exclude(pk=excluir_reserva_id)
        if usadas.count() >= regla.max_reservas_mes_inmueble:
            motivo("CUPO_MENSUAL", f"El inmueble alcanzó el máximo de {regla.max_reservas_mes_inmueble} reserva(s) al mes para esta amenidad.")

    # Solapamientos con reservas y con bloqueos (RF11)
    for r in reservas_en_rango(amenidad.pk, inicio, fin, excluir_id=excluir_reserva_id):
        motivo("RESERVA_SOLAPADA", f"Ya existe una reserva de {_hhmm(r.fecha_inicio)} a {_hhmm(r.fecha_fin)} en ese horario.")
    for b in bloqueos_en_rango(amenidad.pk, inicio, fin):
        motivo("BLOQUEADA", f"La amenidad está bloqueada de {_hhmm(b.fecha_inicio)} a {_hhmm(b.fecha_fin)}: {b.motivo}")
    return motivos


def disponibilidad_dia(amenidad: Amenidad, fecha: dt.date, *, ahora: dt.datetime | None = None) -> dict:
    """Franjas abiertas, ocupadas y libres de una amenidad en un día (RF12: calendario)."""
    ahora = ahora or timezone.now()
    regla = obtener_regla(amenidad)
    horarios = list(amenidad.horarios.filter(activo=True, dia_semana=fecha.isoweekday()).order_by("hora_apertura"))
    ventanas = [(combinar(fecha, h.hora_apertura), combinar(fecha, h.hora_cierre)) for h in horarios]

    dia_ini, dia_fin = inicio_dia(fecha), inicio_dia(fecha + dt.timedelta(days=1))
    ocupados = []
    for r in reservas_en_rango(amenidad.pk, dia_ini, dia_fin).select_related("estado"):
        ocupados.append({"tipo": "RESERVA", "inicio": r.fecha_inicio, "fin": r.fecha_fin,
                         "detalle": r.estado.nombre})
    for b in bloqueos_en_rango(amenidad.pk, dia_ini, dia_fin):
        ocupados.append({"tipo": "BLOQUEO", "inicio": b.fecha_inicio, "fin": b.fecha_fin, "detalle": b.motivo})

    libres = restar_intervalos(ventanas, [(o["inicio"], o["fin"]) for o in ocupados])
    # Solo lo que realmente se puede reservar hoy: respeta la anticipación mínima y máxima
    desde = ahora + dt.timedelta(hours=regla.anticipacion_min_horas)
    hasta = ahora + dt.timedelta(days=regla.anticipacion_max_dias)
    recortados = []
    for ini, fin in libres:
        ini, fin = max(ini, desde), min(fin, hasta)
        if fin > ini and _horas(ini, fin) * 60 >= regla.duracion_min_minutos:
            recortados.append((ini, fin))

    return {
        "amenidad_id": amenidad.pk,
        "amenidad": amenidad.nombre,
        "fecha": fecha.isoformat(),
        "activa": amenidad.activa,
        "abierta": bool(horarios),
        "capacidad": amenidad.capacidad,
        "duracion_min_minutos": regla.duracion_min_minutos,
        "duracion_max_minutos": regla.duracion_max_minutos,
        "horarios": [{"apertura": h.hora_apertura.strftime("%H:%M"), "cierre": h.hora_cierre.strftime("%H:%M")} for h in horarios],
        "ocupados": [{**o, "inicio": iso_local(o["inicio"]), "fin": iso_local(o["fin"])} for o in sorted(ocupados, key=lambda x: x["inicio"])],
        "libres": [{"inicio": iso_local(i), "fin": iso_local(f)} for i, f in recortados] if amenidad.activa else [],
    }


# --- RF12: agenda / calendario ------------------------------------------------------
def eventos_agenda(desde: dt.datetime, hasta: dt.datetime, usuario, *, amenidad_ids=None, estados=None) -> list[dict]:
    """Reservas y bloqueos en [desde, hasta). Quien no administra ve las reservas ajenas como
    'Ocupado' (sin datos personales) y las propias completas."""
    gestor = es_gestor(usuario)
    estados = estados or ("SOLICITADA", "CONFIRMADA", "FINALIZADA")
    reservas = (
        Reserva.objects.filter(fecha_inicio__lt=hasta, fecha_fin__gt=desde, estado__codigo__in=estados)
        .select_related("amenidad", "usuario", "inmueble", "estado")
    )
    bloqueos = BloqueoAmenidad.objects.filter(
        cancelado=False, fecha_inicio__lt=hasta, fecha_fin__gt=desde
    ).select_related("amenidad")
    if amenidad_ids:
        reservas, bloqueos = reservas.filter(amenidad_id__in=amenidad_ids), bloqueos.filter(amenidad_id__in=amenidad_ids)

    eventos = []
    for r in reservas:
        mia = r.usuario_id == usuario.pk
        detalle = gestor or mia
        eventos.append({
            "tipo": "RESERVA", "id": r.pk, "amenidad_id": r.amenidad_id, "amenidad": r.amenidad.nombre,
            "inicio": iso_local(r.fecha_inicio), "fin": iso_local(r.fecha_fin),
            "titulo": f"{r.amenidad.nombre} · {r.usuario.nombre_completo}" if detalle else "Ocupado",
            "estado": r.estado.codigo if detalle else None,
            "estado_nombre": r.estado.nombre if detalle else None,
            "residente": r.usuario.nombre_completo if gestor else None,
            "inmueble": (r.inmueble.codigo_interno if r.inmueble else None) if gestor else None,
            "num_personas": r.num_personas if detalle else None,
            "mia": mia,
        })
    for b in bloqueos:
        eventos.append({
            "tipo": "BLOQUEO", "id": b.pk, "amenidad_id": b.amenidad_id, "amenidad": b.amenidad.nombre,
            "inicio": iso_local(b.fecha_inicio), "fin": iso_local(b.fecha_fin),
            "titulo": f"{b.amenidad.nombre} · Bloqueada", "estado": None, "estado_nombre": None,
            "residente": None, "inmueble": None, "num_personas": None, "mia": False, "motivo": b.motivo,
        })
    return sorted(eventos, key=lambda e: (e["inicio"], e["amenidad_id"]))


# --- inmueble del solicitante ----------------------------------------------------------
def resolver_inmueble(usuario, inmueble, *, gestor: bool):
    """Valida el inmueble indicado o, si hay uno solo vigente, lo asigna automáticamente."""
    vigentes = InmuebleUsuario.objects.filter(usuario=usuario, fecha_fin__isnull=True).select_related("inmueble")
    if inmueble is not None:
        if not gestor and not vigentes.filter(inmueble=inmueble).exists():
            raise ValidationError({"inmueble": "El inmueble no está asociado a tu cuenta."})
        return inmueble
    inmuebles = {v.inmueble_id: v.inmueble for v in vigentes}
    return next(iter(inmuebles.values())) if len(inmuebles) == 1 else None


# --- reservas ------------------------------------------------------------------------------
def crear_reserva(*, amenidad, usuario, inicio, fin, num_personas, inmueble=None, observaciones=None) -> Reserva:
    with transaction.atomic():
        # Serializa solicitudes concurrentes sobre la misma amenidad (además del trigger).
        amenidad = Amenidad.objects.select_for_update().get(pk=amenidad.pk)
        # Una solicitud vencida que el proceso periódico aún no liberó no debe bloquear el horario.
        liberar_no_confirmadas(amenidad_id=amenidad.pk)
        motivos = verificar_disponibilidad(amenidad, inicio, fin, num_personas=num_personas, inmueble=inmueble)
        if motivos:
            raise ReservaNoPermitida(motivos)

        regla = obtener_regla(amenidad)
        confirmada = not regla.requiere_confirmacion
        reserva = Reserva.objects.create(
            amenidad=amenidad, usuario=usuario, inmueble=inmueble,
            fecha_inicio=inicio, fecha_fin=fin, num_personas=num_personas, observaciones=observaciones,
            estado=estado_reserva("CONFIRMADA" if confirmada else "SOLICITADA"),
            confirmada_en=timezone.now() if confirmada else None,
        )
        avisos.solicitud_creada(reserva)
        return reserva


def _transicionar(reserva: Reserva, nuevo: str) -> Estado:
    actual = reserva.estado.codigo
    if nuevo not in TRANSICIONES.get(actual, set()):
        raise ValidationError({"detail": f"No se puede pasar una reserva de {actual} a {nuevo}."})
    return estado_reserva(nuevo)


def limite_cancelacion(reserva: Reserva) -> dt.datetime:
    return reserva.fecha_inicio - dt.timedelta(hours=obtener_regla(reserva.amenidad).horas_limite_cancelacion)


def puede_cancelar(reserva: Reserva, usuario, *, ahora: dt.datetime | None = None) -> bool:
    """Política de cancelación: el residente hasta N horas antes; el administrador mientras siga vigente."""
    if reserva.estado.es_final or reserva.estado.codigo not in TRANSICIONES:
        return False
    if es_gestor(usuario):
        return True
    return reserva.usuario_id == usuario.pk and (ahora or timezone.now()) <= limite_cancelacion(reserva)


def cancelar_reserva(reserva: Reserva, usuario, motivo: str | None = None) -> Reserva:
    gestor = es_gestor(usuario)
    if not gestor and reserva.usuario_id != usuario.pk:
        raise PermissionDenied("Solo puedes cancelar tus propias reservas.")
    nuevo_estado = _transicionar(reserva, "CANCELADA")
    if not puede_cancelar(reserva, usuario):
        horas_limite = obtener_regla(reserva.amenidad).horas_limite_cancelacion
        raise ValidationError({"detail": f"Solo se puede cancelar hasta {horas_limite} hora(s) antes del inicio de la reserva."})

    reserva.estado = nuevo_estado
    reserva.cancelada_por, reserva.cancelada_en = usuario, timezone.now()
    reserva.motivo_cancelacion = motivo or ("Cancelada por la administración" if gestor and reserva.usuario_id != usuario.pk else "Cancelada por el usuario")
    reserva.save(update_fields=["estado", "cancelada_por", "cancelada_en", "motivo_cancelacion", "updated_at"])
    if reserva.usuario_id != usuario.pk:
        avisos.cancelada_por_otro(reserva)
    return reserva


def confirmar_reserva(reserva: Reserva, usuario, *, ahora: dt.datetime | None = None) -> Reserva:
    nuevo_estado = _transicionar(reserva, "CONFIRMADA")
    if (ahora or timezone.now()) > limite_confirmacion(reserva):
        raise ValidationError({"detail": "La solicitud superó su plazo de confirmación y será liberada automáticamente."})
    reserva.estado = nuevo_estado
    reserva.confirmada_por, reserva.confirmada_en = usuario, timezone.now()
    reserva.save(update_fields=["estado", "confirmada_por", "confirmada_en", "updated_at"])
    avisos.confirmada(reserva)
    return reserva


def rechazar_reserva(reserva: Reserva, usuario, motivo: str | None = None) -> Reserva:
    if reserva.estado.codigo != "SOLICITADA":
        raise ValidationError({"detail": "Solo se pueden rechazar reservas en estado SOLICITADA."})
    reserva.estado = _transicionar(reserva, "RECHAZADA")
    reserva.motivo_cancelacion = motivo or "Rechazada por la administración"
    reserva.save(update_fields=["estado", "motivo_cancelacion", "updated_at"])
    avisos.rechazada(reserva)
    return reserva


def finalizar_reserva(reserva: Reserva) -> Reserva:
    reserva.estado = _transicionar(reserva, "FINALIZADA")
    reserva.save(update_fields=["estado", "updated_at"])
    return reserva


def finalizar_vencidas(ahora: dt.datetime | None = None) -> int:
    """Pasa a FINALIZADA las reservas CONFIRMADA cuyo horario ya terminó."""
    ahora = ahora or timezone.now()
    return Reserva.objects.filter(estado__codigo="CONFIRMADA", fecha_fin__lte=ahora).update(
        estado=estado_reserva("FINALIZADA"), updated_at=ahora
    )


# --- liberación automática de solicitudes no confirmadas ----------------------------------------
@contextmanager
def como_sistema():
    """Las escrituras del bloque quedan sin usuario en auditoría/historial (acción del sistema).
    Restablece al usuario previo al salir, para no perder la atribución del resto de la petición."""
    with connection.cursor() as cursor:
        cursor.execute("SELECT current_setting('app.usuario_id', true)")
        previo = cursor.fetchone()[0] or ""
        cursor.execute("SELECT set_config('app.usuario_id', '', true)")
    try:
        yield
    finally:
        with connection.cursor() as cursor:
            cursor.execute("SELECT set_config('app.usuario_id', %s, true)", [previo])


def limite_confirmacion(reserva: Reserva) -> dt.datetime:
    """Hasta cuándo puede confirmarse una solicitud: el plazo de la amenidad o el inicio de la reserva,
    lo que ocurra primero (no tiene sentido confirmar un horario que ya empezó)."""
    plazo = reserva.created_at + dt.timedelta(hours=obtener_regla(reserva.amenidad).horas_limite_confirmacion)
    return min(plazo, reserva.fecha_inicio)


def solicitudes_pendientes():
    return Reserva.objects.filter(estado__codigo="SOLICITADA").select_related(
        "amenidad", "amenidad__reglas", "usuario", "inmueble", "estado"
    )


def liberar_no_confirmadas(ahora: dt.datetime | None = None, *, amenidad_id: int | None = None) -> list[Reserva]:
    """Pasa a EXPIRADA (estado final → libera el horario) las solicitudes cuyo plazo de confirmación venció."""
    ahora = ahora or timezone.now()
    with transaction.atomic():
        pendientes = solicitudes_pendientes().select_for_update(of=("self",))
        if amenidad_id:
            pendientes = pendientes.filter(amenidad_id=amenidad_id)
        vencidas = [r for r in pendientes if limite_confirmacion(r) <= ahora]
        if not vencidas:
            return []
        expirada = estado_reserva("EXPIRADA")
        with como_sistema():
            for r in vencidas:
                r.estado = expirada
                r.cancelada_en = ahora
                r.motivo_cancelacion = "Liberada automáticamente: no fue confirmada dentro del plazo"
                r.save(update_fields=["estado", "cancelada_en", "motivo_cancelacion", "updated_at"])
        for r in vencidas:
            avisos.expirada(r)
    return vencidas


# --- bloqueos ------------------------------------------------------------------------------------
def crear_bloqueo(*, amenidad, inicio, fin, motivo, usuario, cancelar_reservas=False) -> tuple[BloqueoAmenidad, list[Reserva]]:
    """Crea un bloqueo. Si choca con reservas vigentes: 409, salvo que se pida cancelarlas."""
    if fin <= inicio:
        raise ValidationError({"fecha_fin": "Debe ser posterior a la fecha de inicio."})
    with transaction.atomic():
        amenidad = Amenidad.objects.select_for_update().get(pk=amenidad.pk)
        afectadas = list(reservas_en_rango(amenidad.pk, inicio, fin).select_related("estado", "amenidad", "usuario"))
        if afectadas and not cancelar_reservas:
            raise ReservaNoPermitida([{
                "codigo": "RESERVA_SOLAPADA",
                "detalle": f"El bloqueo choca con {len(afectadas)} reserva(s) vigente(s) (ids: {', '.join(str(r.pk) for r in afectadas)}). "
                           "Envía cancelar_reservas=true para cancelarlas.",
            }])
        for r in afectadas:
            r.estado = estado_reserva("CANCELADA")
            r.cancelada_por, r.cancelada_en = usuario, timezone.now()
            r.motivo_cancelacion = f"Cancelada por bloqueo de la amenidad: {motivo}"
            r.save(update_fields=["estado", "cancelada_por", "cancelada_en", "motivo_cancelacion", "updated_at"])
            if r.usuario_id != usuario.pk:
                avisos.cancelada_por_otro(r)
        bloqueo = BloqueoAmenidad.objects.create(
            amenidad=amenidad, fecha_inicio=inicio, fecha_fin=fin, motivo=motivo, creado_por=usuario
        )
    return bloqueo, afectadas


def cancelar_bloqueo(bloqueo: BloqueoAmenidad) -> BloqueoAmenidad:
    if bloqueo.cancelado:
        raise ValidationError({"detail": "El bloqueo ya estaba cancelado."})
    bloqueo.cancelado, bloqueo.cancelado_en = True, timezone.now()
    bloqueo.save(update_fields=["cancelado", "cancelado_en", "updated_at"])
    return bloqueo
