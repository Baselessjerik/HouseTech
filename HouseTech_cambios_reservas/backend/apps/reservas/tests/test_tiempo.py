"""Pruebas de la aritmética de intervalos (no necesitan base de datos)."""
import datetime as dt

from apps.reservas.tiempo import fusionar, recortar, restar_intervalos, solapan

D = dt.datetime


def h(hora, minuto=0):
    return D(2026, 11, 2, hora, minuto)


def test_solapan_es_semiabierto():
    assert solapan(h(10), h(12), h(11), h(13))
    assert not solapan(h(10), h(12), h(12), h(14))  # se tocan: NO se solapan
    assert solapan(h(10), h(14), h(11), h(12))      # uno contiene al otro


def test_fusionar():
    assert fusionar([(h(10), h(12)), (h(11), h(13)), (h(15), h(16))]) == [(h(10), h(13)), (h(15), h(16))]
    assert fusionar([(h(10), h(12)), (h(12), h(13))]) == [(h(10), h(13))]


def test_restar_intervalos():
    ventana = [(h(8), h(20))]
    ocupados = [(h(10), h(12)), (h(11), h(13)), (h(18), h(22))]
    assert restar_intervalos(ventana, ocupados) == [(h(8), h(10)), (h(13), h(18))]


def test_restar_sin_ocupados_y_todo_ocupado():
    assert restar_intervalos([(h(8), h(20))], []) == [(h(8), h(20))]
    assert restar_intervalos([(h(8), h(20))], [(h(7), h(21))]) == []


def test_restar_varias_ventanas():
    ventanas = [(h(8), h(12)), (h(14), h(18))]
    assert restar_intervalos(ventanas, [(h(11), h(15))]) == [(h(8), h(11)), (h(15), h(18))]


def test_recortar():
    assert recortar(h(9), h(11), h(10), h(12)) == (h(10), h(11))
    assert recortar(h(9), h(10), h(10), h(12)) is None
