import 'package:flutter/material.dart';
import '../config/app_theme.dart';

/// Tipos de PQR disponibles (Petición, Queja, Reclamo) devueltos por el backend.
class TipoPqrModel {
  final int id;
  final String codigo;
  final String nombre;
  final String prefijo;
  final String? descripcion;
  final int? slaDias;

  const TipoPqrModel({
    required this.id,
    required this.codigo,
    required this.nombre,
    required this.prefijo,
    this.descripcion,
    this.slaDias,
  });

  /// Convierte los nombres de propiedades de la API al modelo Dart.
  factory TipoPqrModel.fromJson(Map<String, dynamic> json) => TipoPqrModel(
        id: json['id'] as int,
        codigo: json['codigo'] as String? ?? '',
        nombre: json['nombre'] as String? ?? '',
        prefijo: json['prefijo'] as String? ?? '',
        descripcion: json['descripcion'] as String?,
        slaDias: json['sla_dias'] as int?,
      );
}

/// Inmuebles asociados al residente para vincular en el formulario.
class InmuebleOpcionModel {
  final int id;
  final String codigoInterno;
  final String tipo;
  final String? torreBloque;
  final String numero;

  const InmuebleOpcionModel({
    required this.id,
    required this.codigoInterno,
    required this.tipo,
    this.torreBloque,
    required this.numero,
  });

  /// Construye la opción del selector desde la respuesta del catálogo API.
  factory InmuebleOpcionModel.fromJson(Map<String, dynamic> json) =>
      InmuebleOpcionModel(
        id: json['id'] as int,
        codigoInterno: json['codigo_interno'] as String? ?? '',
        tipo: json['tipo'] as String? ?? '',
        torreBloque: json['torre_bloque'] as String?,
        numero: json['numero'] as String? ?? '',
      );

  /// Presentación compacta para distinguir inmuebles en el formulario.
  String get etiquetaPresentacion {
    if (torreBloque != null && torreBloque!.isNotEmpty) {
      return '$tipo $torreBloque - $numero ($codigoInterno)';
    }
    return '$tipo $numero ($codigoInterno)';
  }
}

/// Metadatos de un archivo adjunto asociado a una PQR.
class PqrAdjuntoModel {
  final int id;
  final String nombreArchivo;
  final String tipoMime;
  final int tamanoBytes;
  final String fechaCreacion;

  const PqrAdjuntoModel({
    required this.id,
    required this.nombreArchivo,
    required this.tipoMime,
    required this.tamanoBytes,
    required this.fechaCreacion,
  });

  /// Lee los metadatos publicados por la API, sin incluir el contenido binario.
  factory PqrAdjuntoModel.fromJson(Map<String, dynamic> json) {
    return PqrAdjuntoModel(
      id: json['id'] as int,
      nombreArchivo: json['nombre_archivo'] as String? ?? '',
      tipoMime: json['tipo_mime'] as String? ?? 'application/octet-stream',
      tamanoBytes: json['tamano_bytes'] as int? ?? 0,
      fechaCreacion: json['created_at'] as String? ?? '',
    );
  }

  /// Convierte el tamaño en bytes a una etiqueta adecuada para la interfaz.
  String get tamanoLegible {
    if (tamanoBytes < 1024) return '$tamanoBytes B';
    if (tamanoBytes < 1024 * 1024) {
      return '${(tamanoBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(tamanoBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Estados de la PQR en el flujo residencial.
enum PqrEstado {
  enviado('Recibida', Icons.inbox_rounded),
  recibido('En revisión', Icons.visibility_outlined),
  visto('En proceso', Icons.pending_actions_rounded),
  respondido('Atendida', Icons.forum_outlined),
  resuelto('Cerrada', Icons.check_circle_outline);

  final String label;
  final IconData icon;
  const PqrEstado(this.label, this.icon);

  /// Color usado en chips e indicadores según el estado del trámite.
  Color get color => this == resuelto
      ? okGreen
      : this == respondido
          ? primaryBlue
          : accentSun;

  /// Traduce el código estable de backend al estado mostrado por la aplicación.
  ///
  /// Un código desconocido se presenta como recibido para evitar dejar el
  /// flujo sin estado visual.
  static PqrEstado fromCodigo(String codigo) {
    switch (codigo.toUpperCase()) {
      case 'RECIBIDA':
        return PqrEstado.enviado;
      case 'EN_REVISION':
        return PqrEstado.recibido;
      case 'EN_PROCESO':
        return PqrEstado.visto;
      case 'ATENDIDA':
        return PqrEstado.respondido;
      case 'CERRADA':
        return PqrEstado.resuelto;
      default:
        return PqrEstado.enviado;
    }
  }
}

/// Representa una PQR radicada en la plataforma.
class Pqr {
  final int? id;
  final String radicado;
  final String tipo;
  final String asunto;
  final String fecha;
  final String descripcion;
  final PqrEstado estado;
  final String prioridad;
  final String? inmuebleCodigo;
  final String? respuesta;
  final List<(PqrEstado, String)> historial;

  const Pqr(
    this.radicado,
    this.tipo,
    this.asunto,
    this.fecha,
    this.estado, {
    this.id,
    this.descripcion = '',
    this.prioridad = 'MEDIA',
    this.inmuebleCodigo,
    this.respuesta,
    this.historial = const [],
  });

  /// Adapta el objeto de detalle/listado entregado por la API al modelo visual.
  factory Pqr.fromJson(Map<String, dynamic> json) {
    final tipoData = json['tipo'];
    final tipoNombre = tipoData is Map<String, dynamic>
        ? (tipoData['nombre'] as String? ?? 'Petición')
        : (tipoData as String? ?? 'Petición');

    final estadoCod = json['estado_codigo'] as String? ?? 'RECIBIDA';

    return Pqr(
      json['radicado'] as String? ?? 'PENDIENTE',
      tipoNombre,
      json['asunto'] as String? ?? '',
      json['fecha_radicacion'] as String? ?? '',
      PqrEstado.fromCodigo(estadoCod),
      id: json['id'] as int?,
      descripcion: json['descripcion'] as String? ?? '',
      prioridad: json['prioridad'] as String? ?? 'MEDIA',
      inmuebleCodigo: json['inmueble_codigo'] as String?,
      respuesta: json['respuesta'] as String?,
    );
  }

  /// Indica si el trámite todavía no se encuentra cerrado.
  bool get abierta => estado != PqrEstado.resuelto;

  /// Agrupa las categorías que se resaltan como reclamo en la interfaz.
  bool get esQueja => tipo == 'Queja' || tipo == 'Reclamo';
}
