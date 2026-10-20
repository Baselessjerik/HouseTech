import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../comunicados_api.dart';
import '../models/modelos.dart';
import '../services/comunicados_service.dart';

final comunicadosServiceProvider = Provider<ComunicadosService>((ref) => ComunicadosService());

/// Estado de una lista paginada (carga inicial, "cargar más" y errores).
class ListaState<T> {
  const ListaState({
    this.items = const [],
    this.pagina = 0,
    this.hayMas = false,
    this.cargando = false,
    this.error,
    this.cargado = false,
  });

  final List<T> items;
  final int pagina;
  final bool hayMas;
  final bool cargando;
  final String? error;
  final bool cargado;

  ListaState<T> copiar({
    List<T>? items,
    int? pagina,
    bool? hayMas,
    bool? cargando,
    String? error,
    bool limpiarError = false,
    bool? cargado,
  }) =>
      ListaState<T>(
        items: items ?? this.items,
        pagina: pagina ?? this.pagina,
        hayMas: hayMas ?? this.hayMas,
        cargando: cargando ?? this.cargando,
        error: limpiarError ? null : (error ?? this.error),
        cargado: cargado ?? this.cargado,
      );
}

abstract class ListaNotifier<T> extends Notifier<ListaState<T>> {
  @override
  ListaState<T> build() => ListaState<T>();

  ComunicadosService get servicio => ref.read(comunicadosServiceProvider);

  Future<PaginaApi<T>> traer(int pagina);

  /// Vuelve a la primera página.
  Future<void> recargar() async {
    state = state.copiar(cargando: true, limpiarError: true);
    try {
      final p = await traer(1);
      state = ListaState<T>(items: p.resultados, pagina: 1, hayMas: p.hayMas, cargado: true);
    } on ApiException catch (e) {
      state = state.copiar(cargando: false, error: e.mensaje, cargado: true);
    }
  }

  Future<void> masResultados() async {
    if (state.cargando || !state.hayMas) return;
    state = state.copiar(cargando: true, limpiarError: true);
    try {
      final p = await traer(state.pagina + 1);
      state = state.copiar(
        items: [...state.items, ...p.resultados],
        pagina: state.pagina + 1,
        hayMas: p.hayMas,
        cargando: false,
      );
    } on ApiException catch (e) {
      state = state.copiar(cargando: false, error: e.mensaje);
    }
  }
}

// ----------------------------------------------------------------------------- avisos
class AvisosNotifier extends ListaNotifier<Comunicado> {
  String buscar = '';
  int? categoria;

  @override
  Future<PaginaApi<Comunicado>> traer(int pagina) =>
      servicio.avisos(pagina: pagina, buscar: buscar, categoria: categoria);

  Future<void> filtrar({String? texto, int? categoriaId, bool limpiarCategoria = false}) {
    if (texto != null) buscar = texto;
    if (limpiarCategoria) {
      categoria = null;
    } else if (categoriaId != null) {
      categoria = categoriaId;
    }
    return recargar();
  }
}

final avisosProvider = NotifierProvider<AvisosNotifier, ListaState<Comunicado>>(AvisosNotifier.new);

// ------------------------------------------------------------------------ notificaciones
class NotificacionesNotifier extends ListaNotifier<NotificacionApp> {
  bool soloNoLeidas = false;

  @override
  Future<PaginaApi<NotificacionApp>> traer(int pagina) =>
      servicio.notificaciones(pagina: pagina, soloNoLeidas: soloNoLeidas);

  Future<void> alternarFiltro(bool valor) {
    soloNoLeidas = valor;
    return recargar();
  }

  Future<void> marcarLeida(NotificacionApp n) async {
    if (n.leida) return;
    try {
      await servicio.leerNotificacion(n.id);
      state = state.copiar(items: [for (final x in state.items) x.id == n.id ? x.comoLeida() : x]);
      ref.invalidate(conteoNoLeidasProvider);
    } on ApiException {
      // sin conexión: se reintentará la próxima vez
    }
  }

  Future<void> marcarTodas() async {
    await servicio.leerTodas();
    ref.invalidate(conteoNoLeidasProvider);
    await recargar();
  }
}

final notificacionesProvider =
    NotifierProvider<NotificacionesNotifier, ListaState<NotificacionApp>>(NotificacionesNotifier.new);

final conteoNoLeidasProvider = FutureProvider<int>(
  (ref) => ref.read(comunicadosServiceProvider).conteoNoLeidas(),
  retry: (_, __) => null,
);

// -------------------------------------------------------------------------- gestión
class MantenimientosNotifier extends ListaNotifier<Mantenimiento> {
  String? estado;

  @override
  Future<PaginaApi<Mantenimiento>> traer(int pagina) => servicio.mantenimientos(pagina: pagina, estado: estado);

  Future<void> filtrarEstado(String? valor) {
    estado = valor;
    return recargar();
  }
}

final mantenimientosProvider =
    NotifierProvider<MantenimientosNotifier, ListaState<Mantenimiento>>(MantenimientosNotifier.new);

class BloqueosNotifier extends ListaNotifier<Bloqueo> {
  bool? activo;

  @override
  Future<PaginaApi<Bloqueo>> traer(int pagina) => servicio.bloqueos(pagina: pagina, activo: activo);

  Future<void> filtrarActivo(bool? valor) {
    activo = valor;
    return recargar();
  }
}

final bloqueosProvider = NotifierProvider<BloqueosNotifier, ListaState<Bloqueo>>(BloqueosNotifier.new);

class ComunicadosAdminNotifier extends ListaNotifier<Comunicado> {
  String? estado;

  @override
  Future<PaginaApi<Comunicado>> traer(int pagina) => servicio.comunicados(pagina: pagina, estado: estado);

  Future<void> filtrarEstado(String? valor) {
    estado = valor;
    return recargar();
  }
}

final comunicadosAdminProvider =
    NotifierProvider<ComunicadosAdminNotifier, ListaState<Comunicado>>(ComunicadosAdminNotifier.new);

// ---------------------------------------------------------------------- listas pequeñas
final categoriasProvider = FutureProvider<List<CategoriaComunicado>>(
  (ref) => ref.read(comunicadosServiceProvider).categorias(),
  retry: (_, __) => null,
);

final disponibilidadProvider = FutureProvider.family<List<DisponibilidadAmenidad>, DateTime?>(
  (ref, momento) => ref.read(comunicadosServiceProvider).disponibilidad(momento: momento),
  retry: (_, __) => null,
);
