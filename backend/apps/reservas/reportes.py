"""Reportes de ocupación e históricos de reservas, con filtros."""
from __future__ import annotations

import csv
import datetime as dt
from collections import defaultdict

from django.http import HttpResponse
from django.utils import timezone

from .models import Amenidad, BloqueoAmenidad, Reserva
from .services import ESTADOS_RESERVA, inicio_dia
from .tiempo import horas, inicio_semana, recortar

ESTADOS_OCUPACION = ("CONFIRMADA", "FINALIZADA")  # lo que cuenta como "amenidad usada" por defecto


def _clave_periodo(fecha: dt.date, agrupar: str) -> str:
    if agrupar == "mes":
        return fecha.strftime("%Y-%m")
    if agrupar == "semana":
        return inicio_semana(fecha).isoformat()
    return fecha.isoformat()


def _horas_disponibles(amenidad: Amenidad, desde: dt.date, hasta: dt.date) -> float:
    """Horas de funcionamiento de la amenidad entre dos fechas (inclusive) según sus horarios."""
    por_dia: dict[int, float] = defaultdict(float)
    for h in amenidad.horarios.all():
        if h.activo:
            apertura = dt.datetime.combine(dt.date.min, h.hora_apertura)
            cierre = dt.datetime.combine(dt.date.min, h.hora_cierre)
            por_dia[h.dia_semana] += horas(apertura, cierre)
    total, dia = 0.0, desde
    while dia <= hasta:
        total += por_dia.get(dia.isoweekday(), 0.0)
        dia += dt.timedelta(days=1)
    return total


def reporte_ocupacion(f: dict) -> dict:
    """`f` es el resultado validado de ReporteFiltrosSerializer."""
    ini, fin = inicio_dia(f["desde"]), inicio_dia(f["hasta"] + dt.timedelta(days=1))
    estados_ocupacion = f.get("estados") or ESTADOS_OCUPACION

    amenidades = Amenidad.objects.prefetch_related("horarios").order_by("nombre")
    if not f.get("incluir_inactivas"):
        amenidades = amenidades.filter(activa=True)
    if f.get("amenidades"):
        amenidades = amenidades.filter(pk__in=f["amenidades"])
    amenidades = list(amenidades)
    ids = [a.pk for a in amenidades]

    reservas = Reserva.objects.filter(
        amenidad_id__in=ids, fecha_inicio__lt=fin, fecha_fin__gt=ini
    ).select_related("estado")
    if f.get("inmueble"):
        reservas = reservas.filter(inmueble_id=f["inmueble"])
    if f.get("usuario"):
        reservas = reservas.filter(usuario_id=f["usuario"])
    por_amenidad: dict[int, list[Reserva]] = defaultdict(list)
    for r in reservas:
        por_amenidad[r.amenidad_id].append(r)

    bloqueadas: dict[int, float] = defaultdict(float)
    for b in BloqueoAmenidad.objects.filter(amenidad_id__in=ids, cancelado=False, fecha_inicio__lt=fin, fecha_fin__gt=ini):
        tramo = recortar(b.fecha_inicio, b.fecha_fin, ini, fin)
        if tramo:
            bloqueadas[b.amenidad_id] += horas(*tramo)

    filas, serie = [], defaultdict(lambda: {"reservas": 0, "horas_reservadas": 0.0})
    tot = {"horas_disponibles": 0.0, "horas_reservadas": 0.0, "reservas": 0, "reservas_todas": 0, "canceladas": 0}

    for a in amenidades:
        todas = por_amenidad.get(a.pk, [])
        usadas = [r for r in todas if r.estado.codigo in estados_ocupacion]
        por_estado = {codigo: 0 for codigo in ESTADOS_RESERVA}
        for r in todas:
            por_estado[r.estado.codigo] = por_estado.get(r.estado.codigo, 0) + 1

        horas_res, personas, uso_aforo, hist_hora = 0.0, [], [], defaultdict(float)
        for r in usadas:
            tramo = recortar(r.fecha_inicio, r.fecha_fin, ini, fin)
            if not tramo:
                continue
            h = horas(*tramo)
            horas_res += h
            clave = _clave_periodo(timezone.localtime(r.fecha_inicio).date(), f["agrupar"])
            serie[clave]["reservas"] += 1
            serie[clave]["horas_reservadas"] += h
            # reparte las horas por hora del día para detectar la hora pico
            cursor = timezone.localtime(tramo[0])
            fin_tramo = timezone.localtime(tramo[1])
            while cursor < fin_tramo:
                sig = min(cursor.replace(minute=0, second=0, microsecond=0) + dt.timedelta(hours=1), fin_tramo)
                hist_hora[cursor.hour] += horas(cursor, sig)
                cursor = sig
            if r.num_personas:
                personas.append(r.num_personas)
                if a.capacidad:
                    uso_aforo.append(r.num_personas / a.capacidad * 100)

        disponibles = _horas_disponibles(a, f["desde"], f["hasta"])
        pico = max(hist_hora, key=hist_hora.get) if hist_hora else None
        filas.append({
            "amenidad_id": a.pk,
            "amenidad": a.nombre,
            "activa": a.activa,
            "capacidad": a.capacidad,
            "horas_disponibles": round(disponibles, 2),
            "horas_reservadas": round(horas_res, 2),
            "ocupacion_pct": round(horas_res / disponibles * 100, 2) if disponibles else None,
            "horas_bloqueadas": round(bloqueadas.get(a.pk, 0.0), 2),
            "reservas": len(usadas),
            "reservas_por_estado": por_estado,
            "tasa_cancelacion_pct": round(por_estado["CANCELADA"] / len(todas) * 100, 2) if todas else 0.0,
            "personas_promedio": round(sum(personas) / len(personas), 2) if personas else None,
            "uso_aforo_promedio_pct": round(sum(uso_aforo) / len(uso_aforo), 2) if uso_aforo else None,
            "hora_pico": f"{pico:02d}:00" if pico is not None else None,
        })
        tot["horas_disponibles"] += disponibles
        tot["horas_reservadas"] += horas_res
        tot["reservas"] += len(usadas)
        tot["reservas_todas"] += len(todas)
        tot["canceladas"] += por_estado["CANCELADA"]

    return {
        "filtros": {
            "desde": f["desde"].isoformat(), "hasta": f["hasta"].isoformat(),
            "estados_ocupacion": list(estados_ocupacion), "agrupar": f["agrupar"],
            "amenidades": f.get("amenidades") or [], "inmueble": f.get("inmueble"), "usuario": f.get("usuario"),
        },
        "resumen": {
            "horas_disponibles": round(tot["horas_disponibles"], 2),
            "horas_reservadas": round(tot["horas_reservadas"], 2),
            "ocupacion_pct": round(tot["horas_reservadas"] / tot["horas_disponibles"] * 100, 2) if tot["horas_disponibles"] else None,
            "reservas": tot["reservas"],
            "tasa_cancelacion_pct": round(tot["canceladas"] / tot["reservas_todas"] * 100, 2) if tot["reservas_todas"] else 0.0,
        },
        "amenidades": filas,
        "serie": [{"periodo": k, "reservas": v["reservas"], "horas_reservadas": round(v["horas_reservadas"], 2)} for k, v in sorted(serie.items())],
    }


def ocupacion_a_csv(datos: dict) -> HttpResponse:
    respuesta = HttpResponse(content_type="text/csv; charset=utf-8")
    respuesta["Content-Disposition"] = 'attachment; filename="ocupacion_amenidades.csv"'
    respuesta.write("\ufeff")  # BOM: Excel abre bien las tildes
    escritor = csv.writer(respuesta)
    escritor.writerow(["Amenidad", "Capacidad", "Horas disponibles", "Horas reservadas", "Ocupación %",
                       "Horas bloqueadas", "Reservas", "Canceladas", "Expiradas", "Tasa cancelación %", "Personas promedio",
                       "Uso de aforo %", "Hora pico"])
    for a in datos["amenidades"]:
        escritor.writerow([a["amenidad"], a["capacidad"], a["horas_disponibles"], a["horas_reservadas"],
                           a["ocupacion_pct"], a["horas_bloqueadas"], a["reservas"],
                           a["reservas_por_estado"]["CANCELADA"], a["reservas_por_estado"]["EXPIRADA"],
                           a["tasa_cancelacion_pct"],
                           a["personas_promedio"], a["uso_aforo_promedio_pct"], a["hora_pico"]])
    return respuesta


def historico_a_csv(reservas) -> HttpResponse:
    respuesta = HttpResponse(content_type="text/csv; charset=utf-8")
    respuesta["Content-Disposition"] = 'attachment; filename="historico_reservas.csv"'
    respuesta.write("\ufeff")
    escritor = csv.writer(respuesta)
    escritor.writerow(["ID", "Amenidad", "Residente", "Inmueble", "Inicio", "Fin", "Personas", "Estado",
                       "Creada", "Confirmada", "Cancelada", "Motivo"])
    local = lambda v: timezone.localtime(v).strftime("%Y-%m-%d %H:%M") if v else ""  # noqa: E731
    for r in reservas.iterator():
        escritor.writerow([r.pk, r.amenidad.nombre, r.usuario.nombre_completo,
                           r.inmueble.codigo_interno if r.inmueble else "", local(r.fecha_inicio), local(r.fecha_fin),
                           r.num_personas or "", r.estado.nombre, local(r.created_at), local(r.confirmada_en),
                           local(r.cancelada_en), r.motivo_cancelacion or ""])
    return respuesta
