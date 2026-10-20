// Ubicación: frontend/lib/services/pqr_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/pqr_model.dart';

/// Centraliza las solicitudes HTTP del flujo PQR y adjunta la sesión vigente.
class PqrService {
  /// Almacén seguro para los tokens de acceso y renovación.
  final _storage = const FlutterSecureStorage();

  /// Construye encabezados JSON con el token de acceso disponible.
  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Reintenta una solicitud una vez si el token venció y pudo renovarse.
  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function() request,
  ) async {
    var response = await request();
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      response = await request();
    }
    return response;
  }

  /// Renueva el token de acceso usando el refresh token persistido.
  Future<bool> _refreshAccessToken() async {
    final refresh = await _storage.read(key: 'refresh_token');
    if (refresh == null) return false;
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.refreshUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'refresh': refresh}),
      );
      if (response.statusCode != 200) return false;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      await _storage.write(key: 'access_token', value: data['access']);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Extrae el primer mensaje útil de error con formato DRF.
  String _extraerError(Map<String, dynamic> data) {
    if (data.containsKey('detail')) return data['detail'].toString();
    for (final key in [
      'asunto',
      'descripcion',
      'tipo_id',
      'inmueble_id',
      'archivo',
      'non_field_errors'
    ]) {
      if (data.containsKey(key)) {
        final val = data[key];
        return val is List ? val.join(' ') : val.toString();
      }
    }
    return 'Ocurrió un error al procesar la solicitud.';
  }

  /// Consulta el catálogo de tipos de PQR activos para el formulario.
  Future<List<TipoPqrModel>> obtenerTiposPqr() async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse(ApiConfig.pqrsTiposUrl),
        headers: await _headers(),
      ),
    );

    if (response.statusCode != 200) {
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      final mensaje = decoded is Map<String, dynamic>
          ? _extraerError(decoded)
          : 'No fue posible cargar los tipos de solicitud.';
      throw Exception(mensaje);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException(
        'El servidor devolvió un catálogo de tipos con formato inválido.',
      );
    }

    return decoded
        .map(
          (item) => TipoPqrModel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// Consulta los inmuebles asociados al residente.
  Future<List<InmuebleOpcionModel>> obtenerMisInmuebles() async {
    try {
      final response = await _authenticatedRequest(
        () async => http.get(Uri.parse(ApiConfig.pqrsMisInmueblesUrl),
            headers: await _headers()),
      );
      if (response.statusCode == 200) {
        final List<dynamic> list = jsonDecode(utf8.decode(response.bodyBytes));
        return list
            .map((item) =>
                InmuebleOpcionModel.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Lista las solicitudes visibles para el usuario autenticado.
  ///
  /// Devuelve una lista vacía cuando la consulta falla para conservar el
  /// comportamiento de carga actual de las pantallas PQR.
  Future<List<Pqr>> obtenerMisPqrs() async {
    try {
      final response = await _authenticatedRequest(
        () async =>
            http.get(Uri.parse(ApiConfig.pqrsUrl), headers: await _headers()),
      );
      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        final List<dynamic> list =
            decoded is Map<String, dynamic> && decoded.containsKey('results')
                ? decoded['results'] as List<dynamic>
                : decoded as List<dynamic>;
        return list
            .map((item) => Pqr.fromJson(item as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  /// Consulta el detalle actual de una PQR visible para el usuario autenticado.
  Future<Pqr> obtenerDetallePqr(int pqrId) async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse('${ApiConfig.pqrsUrl}$pqrId/'),
        headers: await _headers(),
      ),
    );

    if (response.statusCode != 200) {
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      final mensaje = decoded is Map<String, dynamic>
          ? _extraerError(decoded)
          : 'No fue posible consultar la solicitud.';
      throw Exception(mensaje);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException(
        'El servidor devolvió el detalle de la PQR con un formato inválido.',
      );
    }

    return Pqr.fromJson(decoded);
  }

  /// Registra una nueva PQR y obtiene el radicado emitido por el servidor.
  Future<Map<String, dynamic>> radicarPqr({
    required int tipoId,
    required String asunto,
    required String descripcion,
    String prioridad = 'MEDIA',
    int? inmuebleId,
  }) async {
    try {
      final body = {
        'tipo_id': tipoId,
        'asunto': asunto.trim(),
        'descripcion': descripcion.trim(),
        'prioridad': prioridad,
        if (inmuebleId != null) 'inmueble_id': inmuebleId,
      };

      final response = await _authenticatedRequest(
        () async => http.post(
          Uri.parse(ApiConfig.pqrsUrl),
          headers: await _headers(),
          body: jsonEncode(body),
        ),
      );

      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (response.statusCode == 201) {
        final radicado = data['radicado'];
        if (radicado is! String || radicado.trim().isEmpty) {
          return {
            'success': false,
            'message':
                'El servidor registró la solicitud, pero no devolvió su radicado.',
          };
        }

        return {
          'success': true,
          'pqr': Pqr.fromJson(data),
          'radicado': radicado,
        };
      }
      return {'success': false, 'message': _extraerError(data)};
    } catch (_) {
      return {
        'success': false,
        'message': 'Error de conexión con el servidor.'
      };
    }
  }

  /// Sube un archivo usando multipart; el servidor valida contenido y permisos.
  Future<Map<String, dynamic>> subirAdjuntoPqr({
    required int pqrId,
    required PlatformFile archivo,
  }) async {
    if (archivo.bytes == null) {
      return {
        'success': false,
        'message': 'No se pudieron leer los datos del archivo seleccionado.',
      };
    }

    try {
      Future<http.Response> enviar() async {
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${ApiConfig.pqrsUrl}$pqrId/adjuntos/'),
        );
        request.headers.addAll(await _headers());
        request.headers.removeWhere(
          (key, _) => key.toLowerCase() == 'content-type',
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'archivo',
            archivo.bytes!,
            filename: archivo.name,
          ),
        );

        return http.Response.fromStream(await request.send());
      }

      var response = await enviar();
      if (response.statusCode == 401 && await _refreshAccessToken()) {
        response = await enviar();
      }

      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));

      if (response.statusCode == 201 && data is Map<String, dynamic>) {
        return {'success': true, 'adjunto': PqrAdjuntoModel.fromJson(data)};
      }

      final error = data is Map<String, dynamic>
          ? _extraerError(data)
          : 'No fue posible cargar el archivo.';
      return {'success': false, 'message': error};
    } catch (_) {
      return {
        'success': false,
        'message': 'Error de conexión al cargar ${archivo.name}.',
      };
    }
  }

  /// Reemplaza el contenido de un adjunto existente mediante multipart.
  ///
  /// Devuelve sus nuevos metadatos para que la interfaz pueda refrescar
  /// el listado sin depender de rutas de almacenamiento locales.
  Future<Map<String, dynamic>> actualizarAdjuntoPqr({
    required int pqrId,
    required int adjuntoId,
    required PlatformFile archivo,
  }) async {
    if (archivo.bytes == null) {
      return {
        'success': false,
        'message': 'No se pudieron leer los datos del archivo seleccionado.',
      };
    }

    try {
      Future<http.Response> enviar() async {
        final request = http.MultipartRequest(
          'PATCH',
          Uri.parse('${ApiConfig.pqrsUrl}$pqrId/adjuntos/$adjuntoId/'),
        );
        request.headers.addAll(await _headers());
        request.headers.removeWhere(
          (key, _) => key.toLowerCase() == 'content-type',
        );
        request.files.add(
          http.MultipartFile.fromBytes(
            'archivo',
            archivo.bytes!,
            filename: archivo.name,
          ),
        );
        return http.Response.fromStream(await request.send());
      }

      var response = await enviar();
      if (response.statusCode == 401 && await _refreshAccessToken()) {
        response = await enviar();
      }

      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 && data is Map<String, dynamic>) {
        return {'success': true, 'adjunto': PqrAdjuntoModel.fromJson(data)};
      }

      return {
        'success': false,
        'message': data is Map<String, dynamic>
            ? _extraerError(data)
            : 'No fue posible reemplazar el archivo.',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Error de conexión al reemplazar ${archivo.name}.',
      };
    }
  }

  /// Elimina un adjunto y su archivo asociado.
  Future<Map<String, dynamic>> eliminarAdjuntoPqr({
    required int pqrId,
    required int adjuntoId,
  }) async {
    try {
      final response = await _authenticatedRequest(
        () async => http.delete(
          Uri.parse('${ApiConfig.pqrsUrl}$pqrId/adjuntos/$adjuntoId/'),
          headers: await _headers(),
        ),
      );
      if (response.statusCode == 204) {
        return {'success': true};
      }

      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      return {
        'success': false,
        'message': data is Map<String, dynamic>
            ? _extraerError(data)
            : 'No fue posible eliminar el archivo adjunto.',
      };
    } catch (_) {
      return {
        'success': false,
        'message': 'Error de conexión al eliminar el archivo adjunto.',
      };
    }
  }

  /// Recupera los metadatos de los archivos vinculados a una PQR.
  ///
  /// El contenido binario se solicita por separado con [descargarAdjuntoPqr].
  Future<List<PqrAdjuntoModel>> obtenerAdjuntosPqr(int pqrId) async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse('${ApiConfig.pqrsUrl}$pqrId/adjuntos/'),
        headers: await _headers(),
      ),
    );

    if (response.statusCode != 200) {
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      final mensaje = decoded is Map<String, dynamic>
          ? _extraerError(decoded)
          : 'No fue posible cargar los archivos adjuntos.';
      throw Exception(mensaje);
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! List) {
      throw const FormatException(
        'El servidor devolvió una lista de adjuntos con formato inválido.',
      );
    }

    return decoded
        .map(
          (item) => PqrAdjuntoModel.fromJson(item as Map<String, dynamic>),
        )
        .toList();
  }

  /// Descarga el contenido del archivo; la API verifica permisos sobre la PQR.
  Future<Uint8List> descargarAdjuntoPqr({
    required int pqrId,
    required int adjuntoId,
  }) async {
    final response = await _authenticatedRequest(
      () async => http.get(
        Uri.parse(
          '${ApiConfig.pqrsUrl}$pqrId/adjuntos/$adjuntoId/descargar/',
        ),
        headers: await _headers(),
      ),
    );

    if (response.statusCode != 200) {
      final decoded = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes));
      final mensaje = decoded is Map<String, dynamic>
          ? _extraerError(decoded)
          : 'No fue posible descargar el archivo adjunto.';
      throw Exception(mensaje);
    }

    return response.bodyBytes;
  }

  /// Actualiza asunto, descripción o prioridad de una PQR aún editable.
  Future<Map<String, dynamic>> actualizarPqr({
    required int id,
    required int tipoId,
    required String asunto,
    required String descripcion,
    String prioridad = 'MEDIA',
    int? inmuebleId,
  }) async {
    try {
      final body = {
        'tipo_id': tipoId,
        'asunto': asunto.trim(),
        'descripcion': descripcion.trim(),
        'prioridad': prioridad,
        if (inmuebleId != null) 'inmueble_id': inmuebleId,
      };

      final response = await _authenticatedRequest(
        () async => http.patch(
          Uri.parse('${ApiConfig.pqrsUrl}$id/'),
          headers: await _headers(),
          body: jsonEncode(body),
        ),
      );

      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (response.statusCode == 200) {
        return {'success': true};
      }
      return {'success': false, 'message': _extraerError(data)};
    } catch (_) {
      return {'success': false, 'message': 'Error al actualizar la PQR.'};
    }
  }

  /// Elimina una PQR; el servidor decide si el estado permite borrarla.
  Future<Map<String, dynamic>> eliminarPqr(int id) async {
    try {
      final response = await _authenticatedRequest(
        () async => http.delete(
          Uri.parse('${ApiConfig.pqrsUrl}$id/'),
          headers: await _headers(),
        ),
      );

      if (response.statusCode == 204) {
        return {'success': true};
      }
      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      return {'success': false, 'message': _extraerError(data)};
    } catch (_) {
      return {'success': false, 'message': 'Error al eliminar la PQR.'};
    }
  }
}
