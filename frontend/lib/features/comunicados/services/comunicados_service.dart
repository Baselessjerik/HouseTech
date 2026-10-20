import '../comunicados_api.dart';
import '../models/modelos.dart';

String _iso(DateTime d) => d.toUtc().toIso8601String();

/// Acceso a la API del Módulo 2. Todas las llamadas lanzan [ApiException] con un mensaje legible.
class ComunicadosService {
  ComunicadosService({ApiClient? cliente}) : _c = cliente ?? ApiClient();

  final ApiClient _c;

  Map<String, String> _q(int pagina, Map<String, String?> extra) => {
        'page': '$pagina',
        for (final e in extra.entries)
          if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
      };

  // ---------------------------------------------------------------- avisos (RF14)
  Future<PaginaApi<Comunicado>> avisos({int pagina = 1, String? buscar, int? categoria}) async {
    final json = await _c.get(ComunicadosApi.avisos,
        query: _q(pagina, {'search': buscar, 'categoria': categoria?.toString()}));
    return PaginaApi.desde(json, Comunicado.fromJson);
  }

  // ----------------------------------------------------------- notificaciones (RF8, RF16)
  Future<PaginaApi<NotificacionApp>> notificaciones({int pagina = 1, bool soloNoLeidas = false}) async {
    final json = await _c.get(ComunicadosApi.notificaciones,
        query: _q(pagina, {'leida': soloNoLeidas ? 'false' : null}));
    return PaginaApi.desde(json, NotificacionApp.fromJson);
  }

  Future<int> conteoNoLeidas() async {
    final json = await _c.get('${ComunicadosApi.notificaciones}no-leidas/conteo/');
    return (json as Map<String, dynamic>)['no_leidas'] as int? ?? 0;
  }

  Future<void> leerNotificacion(int id) => _c.post('${ComunicadosApi.notificaciones}$id/leer/');

  Future<void> leerTodas() => _c.post('${ComunicadosApi.notificaciones}leer-todas/');

  // ------------------------------------------------------------- disponibilidad (RF6)
  Future<List<DisponibilidadAmenidad>> disponibilidad({DateTime? momento}) async {
    final json = await _c.get(ComunicadosApi.disponibilidad,
        query: momento == null ? null : {'momento': _iso(momento)});
    return (json as List).whereType<Map<String, dynamic>>().map(DisponibilidadAmenidad.fromJson).toList();
  }

  // ------------------------------------------------------------- categorías (RF12)
  Future<List<CategoriaComunicado>> categorias() async {
    final json = await _c.get(ComunicadosApi.categorias);
    return PaginaApi.desde(json, CategoriaComunicado.fromJson).resultados;
  }

  Future<void> guardarCategoria({int? id, required Map<String, dynamic> datos}) async {
    if (id == null) {
      await _c.post(ComunicadosApi.categorias, body: datos);
    } else {
      await _c.patch('${ComunicadosApi.categorias}$id/', body: datos);
    }
  }

  Future<void> eliminarCategoria(int id) => _c.delete('${ComunicadosApi.categorias}$id/');

  // --------------------------------------------------------------- mantenimientos (RF1)
  Future<PaginaApi<Mantenimiento>> mantenimientos({int pagina = 1, String? estado, String? buscar}) async {
    final json = await _c.get(ComunicadosApi.mantenimientos, query: _q(pagina, {'estado': estado, 'search': buscar}));
    return PaginaApi.desde(json, Mantenimiento.fromJson);
  }

  Future<void> guardarMantenimiento({int? id, required Map<String, dynamic> datos, bool confirmar = false}) async {
    final q = confirmar ? {'confirmar': 'true'} : null;
    if (id == null) {
      await _c.post(ComunicadosApi.mantenimientos, body: datos, query: q);
    } else {
      await _c.patch('${ComunicadosApi.mantenimientos}$id/', body: datos, query: q);
    }
  }

  /// [accion]: iniciar, finalizar o cancelar.
  Future<void> cambiarEstadoMantenimiento(int id, String accion) =>
      _c.post('${ComunicadosApi.mantenimientos}$id/$accion/');

  // ------------------------------------------------------------------- bloqueos (RF2-RF7)
  Future<PaginaApi<Bloqueo>> bloqueos({int pagina = 1, bool? activo, String? buscar}) async {
    final json = await _c.get(ComunicadosApi.bloqueos,
        query: _q(pagina, {'activo': activo?.toString(), 'search': buscar}));
    return PaginaApi.desde(json, Bloqueo.fromJson);
  }

  Future<void> guardarBloqueo({int? id, required Map<String, dynamic> datos, bool confirmar = false}) async {
    final q = confirmar ? {'confirmar': 'true'} : null;
    if (id == null) {
      await _c.post(ComunicadosApi.bloqueos, body: datos, query: q);
    } else {
      await _c.patch('${ComunicadosApi.bloqueos}$id/', body: datos, query: q);
    }
  }

  Future<void> cancelarBloqueo(int id) => _c.post('${ComunicadosApi.bloqueos}$id/cancelar/');

  // ------------------------------------------------------------ comunicados (RF9-RF15)
  Future<PaginaApi<Comunicado>> comunicados({int pagina = 1, String? estado, String? buscar}) async {
    final json = await _c.get(ComunicadosApi.comunicados, query: _q(pagina, {'estado': estado, 'search': buscar}));
    return PaginaApi.desde(json, Comunicado.fromJson);
  }

  Future<void> guardarComunicado({int? id, required Map<String, dynamic> datos}) async {
    if (id == null) {
      await _c.post(ComunicadosApi.comunicados, body: datos);
    } else {
      await _c.patch('${ComunicadosApi.comunicados}$id/', body: datos);
    }
  }

  Future<void> publicar(int id) => _c.post('${ComunicadosApi.comunicados}$id/publicar/');

  Future<void> programar(int id, DateTime fecha) =>
      _c.post('${ComunicadosApi.comunicados}$id/programar/', body: {'fecha_programada': _iso(fecha)});

  Future<void> archivar(int id) => _c.post('${ComunicadosApi.comunicados}$id/archivar/');

  Future<List<VersionComunicado>> historial(int id) async {
    final json = await _c.get('${ComunicadosApi.comunicados}$id/historial/');
    return (json as List).whereType<Map<String, dynamic>>().map(VersionComunicado.fromJson).toList();
  }

  // --------------------------------------------------------------- opciones de formulario
  Future<List<OpcionRol>> roles() async {
    final json = await _c.get(ComunicadosApi.opcionesRoles);
    return (json as List).whereType<Map<String, dynamic>>().map(OpcionRol.fromJson).toList();
  }

  Future<List<OpcionUsuario>> buscarUsuarios(String texto) async {
    final json = await _c.get(ComunicadosApi.opcionesUsuarios, query: {'search': texto});
    return (json as List).whereType<Map<String, dynamic>>().map(OpcionUsuario.fromJson).toList();
  }

  Future<List<OpcionUsuario>> usuariosPorIds(List<int> ids) async {
    if (ids.isEmpty) return const [];
    final json = await _c.get(ComunicadosApi.opcionesUsuarios, query: {'ids': ids.join(',')});
    return (json as List).whereType<Map<String, dynamic>>().map(OpcionUsuario.fromJson).toList();
  }
}

/// Convierte fechas locales a ISO-8601 UTC para enviarlas a la API.
String fechaParaApi(DateTime d) => _iso(d);
