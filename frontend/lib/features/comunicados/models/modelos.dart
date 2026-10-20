import 'package:flutter/material.dart';

DateTime? _fecha(dynamic v) => v is String ? DateTime.tryParse(v)?.toLocal() : null;
int? _entero(dynamic v) => v is num ? v.toInt() : null;
String _texto(dynamic v, [String defecto = '']) => v is String ? v : defecto;

/// Convierte "#RRGGBB" (o "#RRGGBBAA") a [Color]; si no es válido usa [defecto].
Color colorDesdeHex(String? hex, Color defecto) {
  if (hex == null) return defecto;
  var limpio = hex.replaceAll('#', '');
  if (limpio.length == 8) limpio = limpio.substring(6) + limpio.substring(0, 6); // AA al final -> al inicio
  if (limpio.length == 6) limpio = 'FF$limpio';
  final valor = int.tryParse(limpio, radix: 16);
  return valor == null ? defecto : Color(valor);
}

/// Página de resultados de la API (DRF PageNumberPagination).
class PaginaApi<T> {
  const PaginaApi({required this.resultados, required this.total, required this.hayMas});

  final List<T> resultados;
  final int total;
  final bool hayMas;

  factory PaginaApi.desde(dynamic json, T Function(Map<String, dynamic>) parser) {
    if (json is List) {
      final lista = json.whereType<Map<String, dynamic>>().map(parser).toList();
      return PaginaApi(resultados: lista, total: lista.length, hayMas: false);
    }
    final mapa = json as Map<String, dynamic>;
    final lista = (mapa['results'] as List? ?? const []).whereType<Map<String, dynamic>>().map(parser).toList();
    return PaginaApi(resultados: lista, total: _entero(mapa['count']) ?? lista.length, hayMas: mapa['next'] != null);
  }
}

class CategoriaComunicado {
  const CategoriaComunicado({
    required this.id,
    required this.nombre,
    this.descripcion,
    this.color,
    this.activa = true,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final String? color;
  final bool activa;

  Color get colorUi => colorDesdeHex(color, const Color(0xFF1E40AF));

  factory CategoriaComunicado.fromJson(Map<String, dynamic> j) => CategoriaComunicado(
        id: _entero(j['id']) ?? 0,
        nombre: _texto(j['nombre']),
        descripcion: j['descripcion'] as String?,
        color: j['color'] as String?,
        activa: j['activa'] as bool? ?? true,
      );
}

/// Sirve tanto para un aviso (vista del residente) como para un comunicado (gestión).
class Comunicado {
  const Comunicado({
    required this.id,
    required this.titulo,
    required this.contenido,
    this.categoriaId,
    this.categoriaNombre,
    this.categoriaColor,
    this.autorNombre,
    this.estado = 'PUBLICADO',
    this.audiencia = 'TODOS',
    this.rolDestinoId,
    this.rolDestinoCodigo,
    this.destinatarios = const [],
    this.fechaProgramada,
    this.fechaPublicacion,
    this.fechaExpiracion,
    this.createdAt,
  });

  final int id;
  final String titulo;
  final String contenido;
  final int? categoriaId;
  final String? categoriaNombre;
  final String? categoriaColor;
  final String? autorNombre;
  final String estado;
  final String audiencia;
  final int? rolDestinoId;
  final String? rolDestinoCodigo;
  final List<int> destinatarios;
  final DateTime? fechaProgramada;
  final DateTime? fechaPublicacion;
  final DateTime? fechaExpiracion;
  final DateTime? createdAt;

  Color get colorCategoria => colorDesdeHex(categoriaColor, const Color(0xFF1E40AF));

  factory Comunicado.fromJson(Map<String, dynamic> j) => Comunicado(
        id: _entero(j['id']) ?? 0,
        titulo: _texto(j['titulo']),
        contenido: _texto(j['contenido']),
        categoriaId: _entero(j['categoria']),
        categoriaNombre: j['categoria_nombre'] as String?,
        categoriaColor: j['categoria_color'] as String?,
        autorNombre: j['autor_nombre'] as String?,
        estado: _texto(j['estado'], 'PUBLICADO'),
        audiencia: _texto(j['audiencia'], 'TODOS'),
        rolDestinoId: _entero(j['rol_destino']),
        rolDestinoCodigo: j['rol_destino_codigo'] as String?,
        destinatarios: (j['destinatarios'] as List? ?? const []).whereType<num>().map((e) => e.toInt()).toList(),
        fechaProgramada: _fecha(j['fecha_programada']),
        fechaPublicacion: _fecha(j['fecha_publicacion']),
        fechaExpiracion: _fecha(j['fecha_expiracion']),
        createdAt: _fecha(j['created_at']),
      );
}

class VersionComunicado {
  const VersionComunicado({
    required this.id,
    this.usuarioNombre,
    this.estadoAnterior,
    this.tituloAnterior,
    this.contenidoAnterior,
    this.fecha,
  });

  final int id;
  final String? usuarioNombre;
  final String? estadoAnterior;
  final String? tituloAnterior;
  final String? contenidoAnterior;
  final DateTime? fecha;

  factory VersionComunicado.fromJson(Map<String, dynamic> j) => VersionComunicado(
        id: _entero(j['id']) ?? 0,
        usuarioNombre: j['usuario_nombre'] as String?,
        estadoAnterior: j['estado_anterior'] as String?,
        tituloAnterior: j['titulo_anterior'] as String?,
        contenidoAnterior: j['contenido_anterior'] as String?,
        fecha: _fecha(j['fecha']),
      );
}

class Mantenimiento {
  const Mantenimiento({
    required this.id,
    required this.titulo,
    required this.fechaInicio,
    required this.fechaFin,
    required this.estado,
    this.amenidadId,
    this.amenidadNombre,
    this.descripcion,
    this.estadoNombre,
    this.responsable,
    this.bloqueosActivos = 0,
  });

  final int id;
  final int? amenidadId;
  final String? amenidadNombre;
  final String titulo;
  final String? descripcion;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String estado;
  final String? estadoNombre;
  final String? responsable;
  final int bloqueosActivos;

  bool get editable => estado == 'PROGRAMADO' || estado == 'EN_CURSO';

  factory Mantenimiento.fromJson(Map<String, dynamic> j) => Mantenimiento(
        id: _entero(j['id']) ?? 0,
        amenidadId: _entero(j['amenidad']),
        amenidadNombre: j['amenidad_nombre'] as String?,
        titulo: _texto(j['titulo']),
        descripcion: j['descripcion'] as String?,
        fechaInicio: _fecha(j['fecha_inicio']) ?? DateTime.now(),
        fechaFin: _fecha(j['fecha_fin']) ?? DateTime.now(),
        estado: _texto(j['estado']),
        estadoNombre: j['estado_nombre'] as String?,
        responsable: j['responsable'] as String?,
        bloqueosActivos: _entero(j['bloqueos_activos']) ?? 0,
      );
}

class Bloqueo {
  const Bloqueo({
    required this.id,
    required this.amenidadId,
    required this.amenidadNombre,
    required this.fechaInicio,
    required this.fechaFin,
    required this.motivo,
    required this.estado,
    this.mantenimientoId,
    this.mantenimientoTitulo,
  });

  final int id;
  final int amenidadId;
  final String amenidadNombre;
  final int? mantenimientoId;
  final String? mantenimientoTitulo;
  final DateTime fechaInicio;
  final DateTime fechaFin;
  final String motivo;

  /// PROGRAMADO, ACTIVO, FINALIZADO o CANCELADO.
  final String estado;

  bool get editable => estado == 'PROGRAMADO' || estado == 'ACTIVO';

  factory Bloqueo.fromJson(Map<String, dynamic> j) => Bloqueo(
        id: _entero(j['id']) ?? 0,
        amenidadId: _entero(j['amenidad']) ?? 0,
        amenidadNombre: _texto(j['amenidad_nombre']),
        mantenimientoId: _entero(j['mantenimiento']),
        mantenimientoTitulo: j['mantenimiento_titulo'] as String?,
        fechaInicio: _fecha(j['fecha_inicio']) ?? DateTime.now(),
        fechaFin: _fecha(j['fecha_fin']) ?? DateTime.now(),
        motivo: _texto(j['motivo']),
        estado: _texto(j['estado']),
      );
}

class NotificacionApp {
  const NotificacionApp({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    this.referenciaTipo,
    this.referenciaId,
    this.createdAt,
  });

  final int id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final bool leida;
  final String? referenciaTipo;
  final int? referenciaId;
  final DateTime? createdAt;

  NotificacionApp comoLeida() => NotificacionApp(
        id: id,
        tipo: tipo,
        titulo: titulo,
        mensaje: mensaje,
        leida: true,
        referenciaTipo: referenciaTipo,
        referenciaId: referenciaId,
        createdAt: createdAt,
      );

  factory NotificacionApp.fromJson(Map<String, dynamic> j) => NotificacionApp(
        id: _entero(j['id']) ?? 0,
        tipo: _texto(j['tipo'], 'SISTEMA'),
        titulo: _texto(j['titulo']),
        mensaje: _texto(j['mensaje']),
        leida: j['leida'] as bool? ?? false,
        referenciaTipo: j['referencia_tipo'] as String?,
        referenciaId: _entero(j['referencia_id']),
        createdAt: _fecha(j['created_at']),
      );
}

class RangoInfo {
  const RangoInfo({required this.inicio, required this.fin, this.motivo});

  final DateTime inicio;
  final DateTime fin;
  final String? motivo;

  static RangoInfo? desde(dynamic j) {
    if (j is! Map<String, dynamic>) return null;
    final inicio = _fecha(j['fecha_inicio']);
    final fin = _fecha(j['fecha_fin']);
    if (inicio == null || fin == null) return null;
    return RangoInfo(inicio: inicio, fin: fin, motivo: j['motivo'] as String?);
  }
}

class DisponibilidadAmenidad {
  const DisponibilidadAmenidad({
    required this.id,
    required this.nombre,
    required this.estado,
    this.descripcion,
    this.capacidad,
    this.motivo,
    this.desde,
    this.hasta,
    this.proximoBloqueo,
    this.proximoMantenimiento,
  });

  final int id;
  final String nombre;
  final String? descripcion;
  final int? capacidad;

  /// DISPONIBLE, RESERVADA, BLOQUEADA o EN_MANTENIMIENTO.
  final String estado;
  final String? motivo;
  final DateTime? desde;
  final DateTime? hasta;
  final RangoInfo? proximoBloqueo;
  final RangoInfo? proximoMantenimiento;

  factory DisponibilidadAmenidad.fromJson(Map<String, dynamic> j) => DisponibilidadAmenidad(
        id: _entero(j['id']) ?? 0,
        nombre: _texto(j['nombre']),
        descripcion: j['descripcion'] as String?,
        capacidad: _entero(j['capacidad']),
        estado: _texto(j['estado'], 'DISPONIBLE'),
        motivo: j['motivo'] as String?,
        desde: _fecha(j['desde']),
        hasta: _fecha(j['hasta']),
        proximoBloqueo: RangoInfo.desde(j['proximo_bloqueo']),
        proximoMantenimiento: RangoInfo.desde(j['proximo_mantenimiento']),
      );
}

class OpcionRol {
  const OpcionRol({required this.id, required this.codigo, required this.nombre});

  final int id;
  final String codigo;
  final String nombre;

  factory OpcionRol.fromJson(Map<String, dynamic> j) =>
      OpcionRol(id: _entero(j['id']) ?? 0, codigo: _texto(j['codigo']), nombre: _texto(j['nombre']));
}

class OpcionUsuario {
  const OpcionUsuario({required this.id, required this.nombre, required this.username});

  final int id;
  final String nombre;
  final String username;

  factory OpcionUsuario.fromJson(Map<String, dynamic> j) =>
      OpcionUsuario(id: _entero(j['id']) ?? 0, nombre: _texto(j['nombre']), username: _texto(j['username']));
}
