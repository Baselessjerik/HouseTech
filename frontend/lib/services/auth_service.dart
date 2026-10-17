import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';

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
    if (data['detail'] is String) return data['detail'] as String;
    for (final value in data.values) {
      if (value is List && value.isNotEmpty) return value.first.toString();
      if (value is String) return value;
    }
    return 'La solicitud no pudo completarse.';
  }
}
