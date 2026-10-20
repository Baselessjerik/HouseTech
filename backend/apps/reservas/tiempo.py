"""Utilidades de intervalos de tiempo sin dependencias de Django (fáciles de probar)."""
from __future__ import annotations

import datetime as dt
from typing import Iterable

Intervalo = tuple[dt.datetime, dt.datetime]


def solapan(a_ini, a_fin, b_ini, b_fin) -> bool:
    """Rangos semiabiertos [ini, fin): igual que tstzrange(..., '[)') en la base de datos."""
    return a_ini < b_fin and b_ini < a_fin


def fusionar(intervalos: Iterable[Intervalo]) -> list[Intervalo]:
    """Une intervalos que se tocan o se solapan."""
    resultado: list[list[dt.datetime]] = []
    for ini, fin in sorted(intervalos):
        if resultado and ini <= resultado[-1][1]:
            resultado[-1][1] = max(resultado[-1][1], fin)
        else:
            resultado.append([ini, fin])
    return [(i, f) for i, f in resultado]


def restar_intervalos(ventanas: Iterable[Intervalo], ocupados: Iterable[Intervalo]) -> list[Intervalo]:
    """Devuelve las partes de `ventanas` que NO están cubiertas por `ocupados`."""
    ocupados = fusionar(ocupados)
    libres: list[Intervalo] = []
    for v_ini, v_fin in ventanas:
        cursor = v_ini
        for o_ini, o_fin in ocupados:
            if o_fin <= cursor or o_ini >= v_fin:
                continue
            if o_ini > cursor:
                libres.append((cursor, o_ini))
            cursor = max(cursor, o_fin)
            if cursor >= v_fin:
                break
        if cursor < v_fin:
            libres.append((cursor, v_fin))
    return libres


def recortar(ini, fin, limite_ini, limite_fin) -> Intervalo | None:
    """Intersección de [ini, fin) con [limite_ini, limite_fin); None si no hay."""
    nuevo_ini, nuevo_fin = max(ini, limite_ini), min(fin, limite_fin)
    return (nuevo_ini, nuevo_fin) if nuevo_ini < nuevo_fin else None


def horas(ini, fin) -> float:
    return (fin - ini).total_seconds() / 3600


def inicio_semana(fecha: dt.date) -> dt.date:
    return fecha - dt.timedelta(days=fecha.weekday())
