import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../config/api_config.dart';
import '../../../models/user_model.dart';
import '../../comunicados/comunicados_api.dart';

class PaginaResultado<T> {
  const PaginaResultado({
    required this.items,
    required this.total,
    required this.tieneSiguiente,
    required this.tieneAnterior,
  });

  final List<T> items;
  final int total;
  final bool tieneSiguiente;
  final bool tieneAnterior;
}

class Modulo1Service {
  Modulo1Service({ApiClient? client, FlutterSecureStorage? storage})
      : _client = client ?? ApiClient(storage: storage);

  final ApiClient _client;

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

  PaginaResultado<T> _extraerPagina<T>(
    dynamic data,
    T Function(Map<String, dynamic>) mapper,
  ) {
    if (data is Map<String, dynamic> && data['results'] is List) {
      final raw = (data['results'] as List)
          .whereType<Map<String, dynamic>>()
          .map(mapper)
          .toList();
      final total = (data['count'] is int) ? data['count'] as int : raw.length;
      return PaginaResultado<T>(
        items: raw,
        total: total,
        tieneSiguiente: data['next'] != null,
        tieneAnterior: data['previous'] != null,
      );
    }
    final raw = _extraerLista(data).map(mapper).toList();
    return PaginaResultado<T>(
      items: raw,
      total: raw.length,
      tieneSiguiente: false,
      tieneAnterior: false,
    );
  }

  // --- Usuarios ---
  Future<PaginaResultado<UserModel>> listarUsuariosPaginado({
    String? search,
    bool? activo,
    String? rol,
    int page = 1,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (activo != null) 'activo': activo.toString(),
      if (rol != null && rol.isNotEmpty) 'rol': rol,
      if (page > 1) 'page': page.toString(),
    };
    final data = await _client.get(_usuarios, query: query);
    return _extraerPagina(data, UserModel.fromJson);
  }

  Future<List<UserModel>> listarUsuarios({
    String? search,
    bool? activo,
    String? rol,
    bool todasLasPaginas = false,
  }) async {
    if (!todasLasPaginas) {
      final res = await listarUsuariosPaginado(
        search: search,
        activo: activo,
        rol: rol,
      );
      return res.items;
    }
    final acum = <UserModel>[];
    var page = 1;
    while (page <= 25) {
      final res = await listarUsuariosPaginado(
        search: search,
        activo: activo,
        rol: rol,
        page: page,
      );
      acum.addAll(res.items);
      if (!res.tieneSiguiente) break;
      page++;
    }
    return acum;
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
    final data = await _client.put('$_usuarios$id/roles/', body: {'roles': roles});
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
        await _client.put('$_roles$rolId/permisos/', body: {'permisos': permisos});
    return data as Map<String, dynamic>;
  }

  // --- Inmuebles ---
  Future<PaginaResultado<Map<String, dynamic>>> listarInmueblesPaginado({
    String? search,
    String? tipo,
    bool? activo,
    bool mios = false,
    int page = 1,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (tipo != null && tipo.isNotEmpty) 'tipo': tipo,
      if (activo != null) 'activo': activo.toString(),
      if (mios) 'mios': 'true',
      if (page > 1) 'page': page.toString(),
    };
    final data = await _client.get(_inmuebles, query: query);
    return _extraerPagina(data, (m) => m);
  }

  Future<List<Map<String, dynamic>>> listarInmuebles({
    String? search,
    String? tipo,
    bool? activo,
    bool mios = false,
  }) async {
    final res = await listarInmueblesPaginado(
      search: search,
      tipo: tipo,
      activo: activo,
      mios: mios,
    );
    return res.items;
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
  Future<PaginaResultado<Map<String, dynamic>>> listarAuditoriaPaginada({
    String? search,
    String? operacion,
    String? tabla,
    String? fecha,
    int page = 1,
  }) async {
    final query = <String, String>{
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
      if (operacion != null && operacion.isNotEmpty) 'operacion': operacion,
      if (tabla != null && tabla.isNotEmpty) 'tabla': tabla,
      if (fecha != null && fecha.isNotEmpty) 'fecha': fecha,
      if (page > 1) 'page': page.toString(),
    };
    final data = await _client.get(_auditoria, query: query);
    return _extraerPagina(data, (m) => m);
  }

  Future<List<Map<String, dynamic>>> listarAuditoria({
    String? search,
    String? operacion,
    String? tabla,
    String? fecha,
  }) async {
    final res = await listarAuditoriaPaginada(
      search: search,
      operacion: operacion,
      tabla: tabla,
      fecha: fecha,
    );
    return res.items;
  }
}
