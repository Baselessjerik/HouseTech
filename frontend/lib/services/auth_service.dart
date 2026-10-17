import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/user_model.dart';

class AuthService {
  final _storage = const FlutterSecureStorage();

  Future<Map<String, dynamic>> login(String username, String password) async {
    return _post(
        ApiConfig.loginUrl,
        {
          'username': username,
          'password': password,
        },
        saveTokens: true);
  }

  Future<Map<String, dynamic>> registrarUsuario({
    required String nombres,
    required String apellidos,
    required String username,
    required String tipoDocumento,
    required String numeroDocumento,
    required String email,
    required String telefono,
    required String password,
  }) {
    return _post(ApiConfig.registroUrl, {
      'nombres': nombres,
      'apellidos': apellidos,
      'username': username,
      'tipo_documento': tipoDocumento,
      'numero_documento': numeroDocumento,
      'email': email,
      'telefono': telefono,
      'password': password,
    });
  }

  Future<Map<String, dynamic>> solicitarRecuperacion(String email) {
    return _post(ApiConfig.recuperarPasswordUrl, {'identificador': email});
  }

  Future<Map<String, dynamic>> restablecerPassword({
    required String email,
    required String codigo,
    required String passwordNueva,
  }) {
    return _post(ApiConfig.restablecerPasswordUrl, {
      'identificador': email,
      'codigo': codigo,
      'password_nueva': passwordNueva,
    });
  }

  Future<Map<String, dynamic>> validarCodigoRecuperacion({
    required String email,
    required String codigo,
  }) {
    return _post(ApiConfig.validarCodigoPasswordUrl, {
      'identificador': email,
      'codigo': codigo,
    });
  }

  Future<UserModel?> obtenerPerfil() async {
    final response = await _authenticatedRequest(
      () async =>
          http.get(Uri.parse(ApiConfig.perfilUrl), headers: await _headers()),
    );
    if (response.statusCode != 200) return null;
    return UserModel.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>);
  }

  Future<Map<String, dynamic>> cerrarSesion() async {
    final refresh = await _storage.read(key: 'refresh_token');
    final access = await _storage.read(key: 'access_token');
    if (refresh != null && access != null) {
      await http.post(
        Uri.parse(ApiConfig.logoutUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $access'
        },
        body: jsonEncode({'refresh': refresh}),
      );
    }
    await _clearTokens();
    return {'success': true};
  }

  Future<Map<String, dynamic>> cambiarPassword({
    required String actual,
    required String nueva,
  }) {
    return _authenticatedPost(ApiConfig.cambiarPasswordUrl, {
      'password_actual': actual,
      'password_nueva': nueva,
    });
  }

  Future<Map<String, String>> _headers() async {
    final token = await _storage.read(key: 'access_token');
    return {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function() request,
  ) async {
    var response = await request();
    if (response.statusCode == 401 && await _refreshAccessToken()) {
      response = await request();
    }
    return response;
  }

  Future<Map<String, dynamic>> _authenticatedPost(
    String url,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _authenticatedRequest(
        () async => http.post(
          Uri.parse(url),
          headers: await _headers(),
          body: jsonEncode(body),
        ),
      );
      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 || response.statusCode == 204
          ? {'success': true, 'data': data}
          : {'success': false, 'message': _message(data)};
    } catch (_) {
      return {
        'success': false,
        'message': 'Error de conexión con el servidor.'
      };
    }
  }

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

  Future<void> _clearTokens() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }

  Future<Map<String, dynamic>> _post(
    String url,
    Map<String, dynamic> body, {
    bool saveTokens = false,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
      final data = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(response.body) as Map<String, dynamic>;
      if (response.statusCode == 200 ||
          response.statusCode == 201 ||
          response.statusCode == 204) {
        if (saveTokens) {
          await _storage.write(key: 'access_token', value: data['access']);
          await _storage.write(key: 'refresh_token', value: data['refresh']);
        }
        return {'success': true, 'data': data};
      }
      return {'success': false, 'message': _message(data)};
    } catch (_) {
      return {
        'success': false,
        'message': 'Error de conexión con el servidor.',
      };
    }
  }

  String _message(Map<String, dynamic> data) {
    if (data['detail'] is String) {
      return _translateMessage(data['detail'] as String);
    }
    for (final value in data.values) {
      if (value is List && value.isNotEmpty) {
        return _translateMessage(value.first.toString());
      }
      if (value is String) return _translateMessage(value);
    }
    return 'La solicitud no pudo completarse.';
  }

  String _translateMessage(String message) {
    const translations = {
      'No active account found with the given credentials':
          'El usuario, correo o contraseña no son correctos.',
      'Given token not valid for any token type':
          'La sesión no es válida. Inicia sesión nuevamente.',
      'Token is invalid or expired':
          'La sesión expiró. Inicia sesión nuevamente.',
      'JSON parse error': 'La solicitud enviada no tiene un formato válido.',
    };
    for (final entry in translations.entries) {
      if (message.startsWith(entry.key)) return entry.value;
    }
    return message;
  }
}
