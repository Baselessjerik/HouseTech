import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';
import '../../../models/user_model.dart';
import '../../comunicados/comunicados_api.dart';

class Modulo1Service {
  Modulo1Service({ApiClient? client, FlutterSecureStorage? storage})
      : _client = client ?? ApiClient(storage: storage),
        _storage = storage ?? const FlutterSecureStorage();

  final ApiClient _client;
  final FlutterSecureStorage _storage;

  static const _usuarios = '${ApiConfig.baseUrl}/usuarios/';
  static const _roles = '${ApiConfig.baseUrl}/roles/';
  static const _permisos = '${ApiConfig.baseUrl}/permisos/';
  static const _inmuebles = '${ApiConfig.baseUrl}/inmuebles/';
  static const _copropiedades = '${ApiConfig.baseUrl}/copropiedades/';
  static const _estadosConfig = '${ApiConfig.baseUrl}/estados-config/';
  static const _auditoria = '${ApiConfig.baseUrl}/auditoria/';

  List<Map<String, dynamic>> _extraerLista(dynamic data) {
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    if (data is Map<String, dynamic> && data['results'] is List) {
      return (data['results'] as List)
          .whereType<Map<String, dynamic>>()
          .toList();
    }
    return const [];
  }

  // --- Usuarios ---
  Future<List<UserModel>> listarUsuarios({
    String? search,
    bool? activo,
    String? rol,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (activo != null) 'activo': activo.toString(),
      if (rol != null && rol.isNotEmpty) 'rol': rol,
    };
    final data = await _client.get(_usuarios, query: query);
    return _extraerLista(data).map(UserModel.fromJson).toList();
  }

  Future<UserModel> crearUsuario(Map<String, dynamic> datos) async {
    final data = await _client.post(_usuarios, body: datos);
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> actualizarUsuario(
      int id, Map<String, dynamic> datos) async {
    final data = await _client.patch('$_usuarios$id/', body: datos);
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> cambiarEstadoUsuario(int id, {required bool activar}) async {
    final accion = activar ? 'activar' : 'desactivar';
    final data = await _client.post('$_usuarios$id/$accion/');
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  Future<UserModel> asignarRolesUsuario(int id, List<String> roles) async {
    final data = await _put('$_usuarios$id/roles/', {'roles': roles});
    return UserModel.fromJson(data as Map<String, dynamic>);
  }

  // --- Roles y permisos ---
  Future<List<Map<String, dynamic>>> listarRoles() async {
    final data = await _client.get(_roles);
    return _extraerLista(data);
  }

  Future<List<Map<String, dynamic>>> listarPermisos() async {
    final data = await _client.get(_permisos);
    return _extraerLista(data);
  }

  Future<Map<String, dynamic>> asignarPermisosRol(
      int rolId, List<String> permisos) async {
    final data =
        await _put('$_roles$rolId/permisos/', {'permisos': permisos});
    return data as Map<String, dynamic>;
  }

  // --- Inmuebles ---
  Future<List<Map<String, dynamic>>> listarInmuebles({
    String? search,
    String? tipo,
    bool? activo,
    bool mios = false,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (tipo != null && tipo.isNotEmpty) 'tipo': tipo,
      if (activo != null) 'activo': activo.toString(),
      if (mios) 'mios': 'true',
    };
    final data = await _client.get(_inmuebles, query: query);
    return _extraerLista(data);
  }

  Future<Map<String, dynamic>> crearInmueble(
      Map<String, dynamic> datos) async {
    final data = await _client.post(_inmuebles, body: datos);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> actualizarInmueble(
      int id, Map<String, dynamic> datos) async {
    final data = await _client.patch('$_inmuebles$id/', body: datos);
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> cambiarEstadoInmueble(int id,
      {required bool activar}) async {
    final accion = activar ? 'activar' : 'desactivar';
    final data = await _client.post('$_inmuebles$id/$accion/');
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> vincularUsuarioInmueble(
    int inmuebleId, {
    required int usuarioId,
    required String tipoRelacion,
  }) async {
    final data = await _client.post(
      '$_inmuebles$inmuebleId/vincular/',
      body: {
        'usuario_id': usuarioId,
        'tipo_relacion': tipoRelacion,
      },
    );
    return data as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> desvincularUsuarioInmueble(
    int inmuebleId, {
    required int vinculoId,
  }) async {
    final data = await _client.post(
      '$_inmuebles$inmuebleId/desvincular/',
      body: {'vinculo_id': vinculoId},
    );
    return data as Map<String, dynamic>;
  }

  // --- Copropiedades y Parametrización ---
  Future<List<Map<String, dynamic>>> listarCopropiedades() async {
    final data = await _client.get(_copropiedades);
    return _extraerLista(data);
  }

  Future<Map<String, dynamic>> guardarCopropiedad({
    int? id,
    required Map<String, dynamic> datos,
  }) async {
    final data = id == null
        ? await _client.post(_copropiedades, body: datos)
        : await _client.patch('$_copropiedades$id/', body: datos);
    return data as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> listarEstadosConfig() async {
    final data = await _client.get(_estadosConfig);
    return _extraerLista(data);
  }

  // --- Auditoría ---
  Future<List<Map<String, dynamic>>> listarAuditoria({
    String? search,
    String? operacion,
    String? tabla,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (operacion != null && operacion.isNotEmpty) 'operacion': operacion,
      if (tabla != null && tabla.isNotEmpty) 'tabla': tabla,
    };
    final data = await _client.get(_auditoria, query: query);
    return _extraerLista(data);
  }

  Future<dynamic> _put(String url, Map<String, dynamic> body) async {
    final token = await _storage.read(key: 'access_token');
    final resp = await http.put(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(body),
    );
    final decoded =
        resp.body.isEmpty ? <String, dynamic>{} : jsonDecode(resp.body);
    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      final msg = decoded['detail']?.toString() ??
          decoded.values
              .map((v) => v is List ? v.join(' ') : v.toString())
              .join(' ');
      throw ApiException(
        msg.isEmpty ? 'No se pudo completar la operación.' : msg,
        status: resp.statusCode,
        datos: decoded,
      );
    }
    throw ApiException('No se pudo completar la operación.',
        status: resp.statusCode);
  }
}

