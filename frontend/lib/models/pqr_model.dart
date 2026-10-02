import 'package:flutter/material.dart';
import '../config/app_theme.dart';

enum PqrEstado {
  enviado('Enviado', Icons.send_rounded),
  recibido('Recibido', Icons.inbox_rounded),
  visto('Visto', Icons.visibility_outlined),
  respondido('Respondido', Icons.forum_outlined),
  resuelto('Resuelto', Icons.check_circle_outline);

  final String label;
  final IconData icon;
  const PqrEstado(this.label, this.icon);

  Color get color => this == resuelto
      ? okGreen
      : this == respondido
          ? primaryBlue
          : accentSun;
}

class Pqr {
  final String radicado, tipo, asunto, fecha, descripcion;
  final PqrEstado estado;
  final String? respuesta;
  final List<(PqrEstado, String)> historial;

  const Pqr(
    this.radicado,
    this.tipo,
    this.asunto,
    this.fecha,
    this.estado, {
    this.respuesta,
    this.descripcion = '',
    this.historial = const [],
  });

  bool get abierta => estado != PqrEstado.resuelto;
  bool get esQueja => tipo == 'Queja' || tipo == 'Reclamo';
}