import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../comunicados/comunicados_api.dart';
import '../models/reservas_models.dart';
import '../services/reservas_service.dart';
import 'reservas_residente_page.dart';

/// Pantalla de administración (`amenidades.gestionar`): zonas comunes, gestión de reservas y reporte de ocupación.
class AmenidadesAdminPage extends StatefulWidget {
  const AmenidadesAdminPage({super.key, this.servicio});

  final ReservasService? servicio;

  @override
  State<AmenidadesAdminPage> createState() => _AmenidadesAdminPageState();
}

class _AmenidadesAdminPageState extends State<AmenidadesAdminPage> {
  late final ReservasService _svc = widget.servicio ?? ReservasService();
  int _tab = 0;

  List<AmenidadModel> _amenidades = const [];
  List<ReservaModel> _reservas = const [];
  ReporteOcupacionModel? _ocupacion;

  String? _filtroEstado;
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarTodo();
  }

  Future<void> _cargarTodo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final amenidades = await _svc.listarAmenidades();
      final reservas = await _svc.listarReservas(estado: _filtroEstado);
      ReporteOcupacionModel? ocupacion;
      try {
        ocupacion = await _svc.reporteOcupacion();
      } catch (_) {
        ocupacion = null;
      }
      if (!mounted) return;
      setState(() {
        _amenidades = amenidades;
        _reservas = reservas.resultados;
        _ocupacion = ocupacion;
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            SegmentedButton<int>(
              segments: const [
                ButtonSegment(
                  value: 0,
                  icon: Icon(Icons.pool_rounded),
                  label: Text('Zonas comunes'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.fact_check_rounded),
                  label: Text('Solicitudes y reservas'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.insights_rounded),
                  label: Text('Ocupación'),
                ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _cargarTodo,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                if (_tab == 0) ...[
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _abrirFormularioAmenidad(),
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Nueva amenidad'),
                  ),
                ] else if (_tab == 1) ...[
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _ejecutarProcesamiento,
                    icon: const Icon(Icons.autorenew_rounded),
                    label: const Text('Procesar vencidas'),
                  ),
                ],
              ],
            ),
          ],
        ),
        const SizedBox(height: 20),
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          PanelVacio(
            icono: Icons.error_outline_rounded,
            titulo: 'No se pudo cargar la información',
            subtitulo: _error!,
            accion: OutlinedButton.icon(
              onPressed: _cargarTodo,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Reintentar'),
            ),
          )
        else if (_tab == 0)
          _vistaAmenidades()
        else if (_tab == 1)
          _vistaReservas()
        else
          _vistaOcupacion(),
      ],
    );
  }

  Widget _vistaAmenidades() {
    if (_amenidades.isEmpty) {
      return const PanelVacio(
        icono: Icons.pool_rounded,
        titulo: 'No hay zonas comunes registradas',
        subtitulo: 'Crea la primera amenidad para configurar su aforo, horarios y políticas.',
      );
    }
    return Column(
      children: [
        for (final a in _amenidades)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.apartment_rounded, color: AppColors.oceanBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          a.nombre,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                        ),
                      ),
                      ChipEstado(
                        texto: a.activa ? 'Activa' : 'Inactiva',
                        color: a.activa ? Colors.green.shade700 : Colors.grey.shade700,
                      ),
                    ],
                  ),
                  if (a.descripcion != null && a.descripcion!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(a.descripcion!, style: const TextStyle(color: Colors.black54)),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 6,
                    children: [
                      Text('Aforo máx.: ${a.capacidad ?? 'Sin límite'}'),
                      Text(
                        'Confirmación: ${a.reglas.requiereConfirmacion ? 'Requerida (${a.reglas.horasLimiteConfirmacion} h)' : 'Automática'}',
                      ),
                      Text('Cancelación hasta: ${a.reglas.horasLimiteCancelacion} h antes'),
                      Text(
                        'Duración: ${a.reglas.duracionMinMinutos}–${a.reglas.duracionMaxMinutos} min',
                      ),
                      if (a.reglas.maxReservasMesInmueble != null)
                        Text('Cupo mensual/inmueble: ${a.reglas.maxReservasMesInmueble}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => _abrirFormularioAmenidad(existente: a),
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Editar'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => _cambiarActiva(a),
                        icon: Icon(
                          a.activa ? Icons.visibility_off_outlined : Icons.check_circle_outline,
                          size: 18,
                        ),
                        label: Text(a.activa ? 'Desactivar' : 'Activar'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _vistaReservas() {
    const estados = [
      null,
      'SOLICITADA',
      'CONFIRMADA',
      'FINALIZADA',
      'CANCELADA',
      'RECHAZADA',
      'EXPIRADA',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final est in estados)
              ChoiceChip(
                label: Text(est ?? 'Todas'),
                selected: _filtroEstado == est,
                onSelected: (_) {
                  setState(() => _filtroEstado = est);
                  _cargarTodo();
                },
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (_reservas.isEmpty)
          const PanelVacio(
            icono: Icons.event_busy_rounded,
            titulo: 'No hay reservas con el filtro seleccionado',
            subtitulo: 'Cambia el filtro de estado para consultar otras solicitudes.',
          )
        else
          for (final r in _reservas)
            Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${r.amenidadNombre} · ${r.residente}',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                          ),
                        ),
                        ChipEstado(texto: r.estadoNombre, color: colorEstadoReserva(r.estado)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 16,
                      runSpacing: 6,
                      children: [
                        Text('Inicio: ${formatoFechaHora(r.fechaInicio)}'),
                        Text('Fin: ${formatoFechaHora(r.fechaFin)}'),
                        if (r.numPersonas != null) Text('Personas: ${r.numPersonas}'),
                        if (r.inmuebleCodigo != null) Text('Inmueble: ${r.inmuebleCodigo}'),
                      ],
                    ),
                    if (r.motivoCancelacion != null && r.motivoCancelacion!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text('Detalle: ${r.motivoCancelacion}',
                          style: TextStyle(color: Colors.red.shade700)),
                    ],
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        TextButton.icon(
                          onPressed: () => mostrarHistorialReserva(context, _svc, r),
                          icon: const Icon(Icons.history_rounded, size: 18),
                          label: const Text('Historial'),
                        ),
                        if (r.estado == 'SOLICITADA') ...[
                          FilledButton.tonalIcon(
                            onPressed: () => _confirmarReserva(r),
                            icon: const Icon(Icons.check_rounded, size: 18),
                            label: const Text('Confirmar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _rechazarOCancelar(r, rechazar: true),
                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.redAccent),
                            label: const Text('Rechazar', style: TextStyle(color: Colors.redAccent)),
                          ),
                        ],
                        if (r.puedeCancelar)
                          OutlinedButton.icon(
                            onPressed: () => _rechazarOCancelar(r, rechazar: false),
                            icon: const Icon(Icons.cancel_outlined, size: 18),
                            label: const Text('Cancelar'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
      ],
    );
  }

  Widget _vistaOcupacion() {
    final rep = _ocupacion;
    if (rep == null) {
      return const PanelVacio(
        icono: Icons.bar_chart_rounded,
        titulo: 'Reporte de ocupación no disponible',
        subtitulo: 'Se requiere el permiso reportes.ver para consultar métricas de ocupación.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _MetricaCard(
              titulo: 'Horas reservadas',
              valor: '${rep.horasReservadas} h',
              subtitulo: 'De ${rep.horasDisponibles} h disponibles',
            ),
            _MetricaCard(
              titulo: 'Ocupación global',
              valor: rep.ocupacionPct != null ? '${rep.ocupacionPct}%' : 'N/A',
              subtitulo: '${rep.reservas} reservas efectivas',
            ),
            _MetricaCard(
              titulo: 'Tasa de cancelación',
              valor: '${rep.tasaCancelacionPct}%',
              subtitulo: 'Últimos 30 días',
            ),
          ],
        ),
        const SizedBox(height: 20),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Detalle por amenidad',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                for (final a in rep.amenidades)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(a.amenidad, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      'Reservadas: ${a.horasReservadas} h / ${a.horasDisponibles} h · '
                      'Reservas: ${a.reservas} · Cancelación: ${a.tasaCancelacionPct}%'
                      '${a.horaPico != null ? ' · Hora pico: ${a.horaPico}' : ''}',
                    ),
                    trailing: ChipEstado(
                      texto: a.ocupacionPct != null ? '${a.ocupacionPct}%' : '0%',
                      color: AppColors.oceanBlue,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _cambiarActiva(AmenidadModel a) async {
    try {
      await _svc.cambiarEstadoAmenidad(a.id, activar: !a.activa);
      if (!mounted) return;
      avisoSnack(context, a.activa ? 'Amenidad desactivada.' : 'Amenidad activada.');
      await _cargarTodo();
    } on ApiException catch (e) {
      if (!mounted) return;
      avisoSnack(context, e.mensaje, error: true);
    }
  }

  Future<void> _confirmarReserva(ReservaModel r) async {
    try {
      await _svc.confirmarReserva(r.id);
      if (!mounted) return;
      avisoSnack(context, 'Reserva confirmada.');
      await _cargarTodo();
    } on ApiException catch (e) {
      if (!mounted) return;
      avisoSnack(context, e.mensaje, error: true);
    }
  }

  Future<void> _rechazarOCancelar(ReservaModel r, {required bool rechazar}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${rechazar ? 'Rechazar' : 'Cancelar'} reserva · ${r.amenidadNombre}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Motivo',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(rechazar ? 'Rechazar' : 'Cancelar reserva'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      if (rechazar) {
        await _svc.rechazarReserva(r.id, motivo: ctrl.text.trim());
      } else {
        await _svc.cancelarReserva(r.id, motivo: ctrl.text.trim());
      }
      if (!mounted) return;
      avisoSnack(context, rechazar ? 'Solicitud rechazada.' : 'Reserva cancelada.');
      await _cargarTodo();
    } on ApiException catch (e) {
      if (!mounted) return;
      avisoSnack(context, e.mensaje, error: true);
    }
  }

  Future<void> _ejecutarProcesamiento() async {
    try {
      final res = await _svc.procesarReservas();
      if (!mounted) return;
      avisoSnack(
        context,
        'Proceso ejecutado: ${res['liberadas'] ?? 0} liberadas, '
        '${res['recordatorios'] ?? 0} recordatorios, '
        '${res['finalizadas'] ?? 0} finalizadas.',
      );
      await _cargarTodo();
    } on ApiException catch (e) {
      if (!mounted) return;
      avisoSnack(context, e.mensaje, error: true);
    }
  }

  Future<void> _abrirFormularioAmenidad({AmenidadModel? existente}) async {
    final nombreCtrl = TextEditingController(text: existente?.nombre ?? '');
    final descCtrl = TextEditingController(text: existente?.descripcion ?? '');
    final capCtrl = TextEditingController(text: existente?.capacidad?.toString() ?? '20');
    final minCtrl =
        TextEditingController(text: '${existente?.reglas.duracionMinMinutos ?? 30}');
    final maxCtrl =
        TextEditingController(text: '${existente?.reglas.duracionMaxMinutos ?? 240}');
    final cancCtrl =
        TextEditingController(text: '${existente?.reglas.horasLimiteCancelacion ?? 24}');
    bool requiereConfirmacion = existente?.reglas.requiereConfirmacion ?? true;
    String? errorLocal;

    final guardado = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: Text(existente == null ? 'Nueva amenidad' : 'Editar ${existente.nombre}'),
          content: SizedBox(
            width: 440,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nombreCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Nombre',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Descripción',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: capCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Aforo máximo (personas)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duración mín. (min)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: maxCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Duración máx. (min)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: cancCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Horas límite de cancelación',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Requiere confirmación administrativa'),
                    value: requiereConfirmacion,
                    onChanged: (v) => setModal(() => requiereConfirmacion = v),
                  ),
                  if (errorLocal != null)
                    Text(errorLocal!, style: TextStyle(color: Colors.red.shade700)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () async {
                if (nombreCtrl.text.trim().isEmpty) {
                  setModal(() => errorLocal = 'El nombre es obligatorio.');
                  return;
                }
                try {
                  await _svc.guardarAmenidad(
                    id: existente?.id,
                    datos: {
                      'nombre': nombreCtrl.text.trim(),
                      'descripcion': descCtrl.text.trim(),
                      'capacidad': int.tryParse(capCtrl.text.trim()),
                      'reglas': {
                        'duracion_min_minutos': int.tryParse(minCtrl.text.trim()) ?? 30,
                        'duracion_max_minutos': int.tryParse(maxCtrl.text.trim()) ?? 240,
                        'horas_limite_cancelacion': int.tryParse(cancCtrl.text.trim()) ?? 24,
                        'requiere_confirmacion': requiereConfirmacion,
                      },
                      if (existente == null)
                        'horarios': [
                          for (var d = 1; d <= 7; d++)
                            {'dia_semana': d, 'hora_apertura': '08:00', 'hora_cierre': '20:00'},
                        ],
                    },
                  );
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } on ApiException catch (e) {
                  setModal(() => errorLocal = e.mensaje);
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (guardado == true && mounted) {
      avisoSnack(context, 'Amenidad guardada correctamente.');
      await _cargarTodo();
    }
  }
}

class _MetricaCard extends StatelessWidget {
  const _MetricaCard({
    required this.titulo,
    required this.valor,
    required this.subtitulo,
  });

  final String titulo;
  final String valor;
  final String subtitulo;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 240,
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titulo, style: const TextStyle(color: Colors.black54, fontSize: 12)),
                const SizedBox(height: 6),
                Text(valor,
                    style: const TextStyle(
                        fontSize: 24, fontWeight: FontWeight.w800, color: AppColors.oceanBlue)),
                const SizedBox(height: 4),
                Text(subtitulo, style: const TextStyle(fontSize: 12, color: Colors.black54)),
              ],
            ),
          ),
        ),
      );
}

