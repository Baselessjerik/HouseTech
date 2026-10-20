import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../config/api_config.dart';

/// Endpoints del Módulo 2. Reutiliza [ApiConfig.baseUrl] (no se edita api_config.dart).
class ComunicadosApi {
  static const mantenimientos = '${ApiConfig.baseUrl}/mantenimientos/';
  static const bloqueos = '${ApiConfig.baseUrl}/bloqueos/';
  static const disponibilidad = '${ApiConfig.baseUrl}/amenidades/disponibilidad/';
  static const categorias = '${ApiConfig.baseUrl}/categorias-comunicado/';
  static const comunicados = '${ApiConfig.baseUrl}/comunicados/';
  static const avisos = '${ApiConfig.baseUrl}/avisos/';
  static const notificaciones = '${ApiConfig.baseUrl}/notificaciones/';
  static const opcionesRoles = '${ApiConfig.baseUrl}/comunicados-opciones/roles/';
  static const opcionesUsuarios = '${ApiConfig.baseUrl}/comunicados-opciones/usuarios/';
}

/// Error de la API con el mensaje ya listo para mostrar al usuario.
class ApiException implements Exception {
  ApiException(this.mensaje, {this.status = 0, this.datos = const {}});

  final String mensaje;
  final int status;
  final Map<String, dynamic> datos;

  String? get codigo => datos['codigo'] as String?;
  bool get esConflictoReservas => status == 409 && codigo == 'reservas_en_conflicto';

  List<Map<String, dynamic>> get reservas {
    final lista = datos['reservas'];
    if (lista is! List) return const [];
    return lista.whereType<Map<String, dynamic>>().toList();
  }

  @override
  String toString() => mensaje;
}

/// Cliente HTTP con el mismo manejo de sesión que AuthService (tokens en
/// flutter_secure_storage y renovación automática ante un 401).
class ApiClient {
  ApiClient({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  Future<dynamic> get(String url, {Map<String, String>? query}) => _enviar('GET', url, query: query);

  Future<dynamic> post(String url, {Map<String, dynamic>? body, Map<String, String>? query}) =>
      _enviar('POST', url, body: body, query: query);

  Future<dynamic> patch(String url, {Map<String, dynamic>? body, Map<String, String>? query}) =>
      _enviar('PATCH', url, body: body, query: query);

  Future<dynamic> delete(String url) => _enviar('DELETE', url);

  Future<dynamic> _enviar(String metodo, String url,
      {Map<String, dynamic>? body, Map<String, String>? query}) async {
    try {
      var respuesta = await _una(metodo, url, body, query);
      if (respuesta.statusCode == 401 && await _renovarToken()) {
        respuesta = await _una(metodo, url, body, query);
      }
      return _procesar(respuesta);
    } on ApiException {
      rethrow;
    } catch (_) {
      throw ApiException('Error de conexión con el servidor.');
    }
  }

  Future<http.Response> _una(
      String metodo, String url, Map<String, dynamic>? body, Map<String, String>? query) async {
    var uri = Uri.parse(url);
    if (query != null && query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }
    final headers = await _headers();
    final cuerpo = body == null ? null : jsonEncode(body);
    switch (metodo) {
      case 'POST':
        return http.post(uri, headers: headers, body: cuerpo ?? '{}');
      case 'PATCH':
        return http.patch(uri, headers: headers, body: cuerpo ?? '{}');
      case 'DELETE':
        return http.delete(uri, headers: headers);
      default:
        return http.get(uri, headers: headers);
    }
  }

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<bool> _renovarToken() async {
    final refresh = await _storage.read(key: 'refresh_token');
    if (refresh == null) return false;
    try {
      final r = await http.post(
        Uri.parse(ApiConfig.refreshUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );
      if (r.statusCode != 200) return false;
      final datos = jsonDecode(r.body) as Map<String, dynamic>;
      await _storage.write(key: 'access_token', value: datos['access'] as String?);
      return true;
    } catch (_) {
      return false;
    }
  }

  dynamic _procesar(http.Response r) {
    final texto = utf8.decode(r.bodyBytes);
    dynamic datos;
    if (texto.isNotEmpty) {
      try {
        datos = jsonDecode(texto);
      } catch (_) {
        datos = null;
      }
    }
    if (r.statusCode >= 200 && r.statusCode < 300) return datos;
    final mapa = datos is Map<String, dynamic> ? datos : <String, dynamic>{};
    throw ApiException(_mensaje(mapa, r.statusCode), status: r.statusCode, datos: mapa);
  }

  static const _etiquetas = {
    'fecha_inicio': 'Inicio',
    'fecha_fin': 'Fin',
    'fecha_programada': 'Fecha de publicación',
    'fecha_expiracion': 'Expiración',
    'motivo': 'Motivo',
    'titulo': 'Título',
    'contenido': 'Contenido',
    'amenidad': 'Amenidad',
    'categoria': 'Categoría',
    'rol_destino': 'Rol',
    'destinatarios': 'Destinatarios',
    'nombre': 'Nombre',
    'color': 'Color',
    'crear_bloqueo': 'Bloqueo',
    'estado': 'Estado',
  };

  String _mensaje(Map<String, dynamic> datos, int status) {
    if (status == 401) return 'La sesión expiró. Inicia sesión nuevamente.';
    if (status == 403) return 'No tienes permiso para realizar esta acción.';
    if (status >= 500) return 'El servidor tuvo un problema. Inténtalo de nuevo.';
    final detalle = datos['detail'];
    if (detalle is String) return detalle;
    for (final entrada in datos.entries) {
      final valor = entrada.value;
      String? texto;
      if (valor is List && valor.isNotEmpty) texto = valor.first.toString();
      if (valor is String) texto = valor;
      if (texto != null) {
        final etiqueta = _etiquetas[entrada.key];
        return etiqueta == null || entrada.key == 'non_field_errors' ? texto : '$etiqueta: $texto';
      }
    }
    return 'La solicitud no pudo completarse.';
  }
}
