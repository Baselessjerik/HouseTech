import '../../../config/api_config.dart';
import '../../comunicados/comunicados_api.dart';
import '../../comunicados/models/modelos.dart';
import '../models/reservas_models.dart';

/// Servicio HTTP para el Módulo 3 (Amenidades, Reservas, Agenda y Reportes).
class ReservasService {
  ReservasService({ApiClient? cliente}) : _c = cliente ?? ApiClient();

  final ApiClient _c;

  static const _amenidades = '${ApiConfig.baseUrl}/amenidades/';
  static const _reservas = '${ApiConfig.baseUrl}/reservas/';
  static const _agenda = '${ApiConfig.baseUrl}/agenda/';
  static const _reporteOcupacion = '${ApiConfig.baseUrl}/reportes/ocupacion/';

  Map<String, String> _q(Map<String, String?> params) => {
        for (final e in params.entries)
          if (e.value != null && e.value!.isNotEmpty) e.key: e.value!,
      };

  // --- Amenidades ---
  Future<List<AmenidadModel>> listarAmenidades({bool? activa}) async {
    final json = await _c.get(_amenidades, query: _q({'activa': activa?.toString()}));
    if (json is List) {
      return json.whereType<Map<String, dynamic>>().map(AmenidadModel.fromJson).toList();
    }
    return PaginaApi.desde(json, AmenidadModel.fromJson).resultados;
  }

  Future<AmenidadModel> guardarAmenidad({int? id, required Map<String, dynamic> datos}) async {
    final json = id == null
        ? await _c.post(_amenidades, body: datos)
        : await _c.patch('$_amenidades$id/', body: datos);
    return AmenidadModel.fromJson(json as Map<String, dynamic>);
  }

  Future<AmenidadModel> cambiarEstadoAmenidad(int id, {required bool activar}) async {
    final accion = activar ? 'activar' : 'desactivar';
    final json = await _c.post('$_amenidades$id/$accion/');
    return AmenidadModel.fromJson(json as Map<String, dynamic>);
  }

  Future<DisponibilidadDiaModel> disponibilidadDia(int amenidadId, String fecha) async {
    final json = await _c.get('$_amenidades$amenidadId/disponibilidad/', query: {'fecha': fecha});
    return DisponibilidadDiaModel.fromJson(json as Map<String, dynamic>);
  }

  // --- Reservas ---
  Future<PaginaApi<ReservaModel>> listarReservas({
    int pagina = 1,
    String? estado,
    int? amenidadId,
    String? buscar,
  }) async {
    final json = await _c.get(
      _reservas,
      query: _q({
        'page': '$pagina',
        'estado': estado,
        'amenidad': amenidadId?.toString(),
        'search': buscar,
      }),
    );
    return PaginaApi.desde(json, ReservaModel.fromJson);
  }

  Future<ReservaModel> crearReserva(Map<String, dynamic> datos) async {
    final json = await _c.post(_reservas, body: datos);
    return ReservaModel.fromJson(json as Map<String, dynamic>);
  }

  Future<ReservaModel> confirmarReserva(int id) async {
    final json = await _c.post('$_reservas$id/confirmar/');
    return ReservaModel.fromJson(json as Map<String, dynamic>);
  }

  Future<ReservaModel> rechazarReserva(int id, {String? motivo}) async {
    final json = await _c.post('$_reservas$id/rechazar/', body: {'motivo': motivo ?? ''});
    return ReservaModel.fromJson(json as Map<String, dynamic>);
  }

  Future<ReservaModel> cancelarReserva(int id, {String? motivo}) async {
    final json = await _c.post('$_reservas$id/cancelar/', body: {'motivo': motivo ?? ''});
    return ReservaModel.fromJson(json as Map<String, dynamic>);
  }

  Future<List<ReservaHistorialModel>> historialReserva(int id) async {
    final json = await _c.get('$_reservas$id/historial/');
    return (json as List)
        .whereType<Map<String, dynamic>>()
        .map(ReservaHistorialModel.fromJson)
        .toList();
  }

  Future<Map<String, dynamic>> procesarReservas() async {
    final json = await _c.post('${_reservas}procesar/');
    return (json as Map<String, dynamic>?) ?? const {};
  }

  // --- Agenda y Reportes ---
  Future<List<EventoAgendaModel>> agenda({String? desde, String? hasta, int? amenidadId}) async {
    final json = await _c.get(
      _agenda,
      query: _q({
        'desde': desde,
        'hasta': hasta,
        'amenidad': amenidadId?.toString(),
      }),
    );
    final map = (json as Map<String, dynamic>?) ?? const {};
    return ((map['eventos'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(EventoAgendaModel.fromJson)
        .toList();
  }

  Future<ReporteOcupacionModel> reporteOcupacion({String? desde, String? hasta}) async {
    final json = await _c.get(_reporteOcupacion, query: _q({'desde': desde, 'hasta': hasta}));
    return ReporteOcupacionModel.fromJson(json as Map<String, dynamic>);
  }
}

