import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../comunicados/comunicados_api.dart';
import '../../comunicados/widgets/ui.dart';
import '../models/reservas_models.dart';
import '../services/reservas_service.dart';

String _fechaYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _horaHm(DateTime d) =>
    '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

String formatoFechaHora(DateTime d) => fechaHora(d);

void avisoSnack(BuildContext context, String texto, {bool error = false}) =>
    mostrarMensaje(context, texto, error: error);

class ChipEstado extends StatelessWidget {
  const ChipEstado({super.key, required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) => EstadoChip(texto, color: color);
}

class PanelVacio extends StatelessWidget {
  const PanelVacio({
    super.key,
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    this.accion,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final Widget? accion;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icono, size: 44, color: AppColors.oceanBlue),
                const SizedBox(height: 12),
                Text(
                  titulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitulo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.black54),
                ),
                if (accion != null) ...[
                  const SizedBox(height: 16),
                  accion!,
                ],
              ],
            ),
          ),
        ),
      );
}

Color colorEstadoReserva(String codigo) {
  switch (codigo) {
    case 'CONFIRMADA':
      return Colors.green.shade700;
    case 'SOLICITADA':
      return Colors.orange.shade800;
    case 'FINALIZADA':
      return AppColors.oceanBlue;
    case 'CANCELADA':
    case 'RECHAZADA':
    case 'EXPIRADA':
      return Colors.red.shade700;
    default:
      return Colors.blueGrey;
  }
}

/// Pantalla del residente (`reservas.solicitar`): solicitar reservas, consultar disponibilidad y ver agenda.
class ReservasResidentePage extends StatefulWidget {
  const ReservasResidentePage({super.key, this.servicio});

  final ReservasService? servicio;

  @override
  State<ReservasResidentePage> createState() => _ReservasResidentePageState();
}

class _ReservasResidentePageState extends State<ReservasResidentePage> {
  late final ReservasService _svc = widget.servicio ?? ReservasService();
  int _tab = 0;

  // Datos
  List<AmenidadModel> _amenidades = const [];
  List<ReservaModel> _reservas = const [];
  List<EventoAgendaModel> _agenda = const [];
  DisponibilidadDiaModel? _disponibilidadDia;

  bool _cargando = true;
  String? _error;

  int? _amenidadSeleccionadaId;
  DateTime _fechaConsulta = DateTime.now().add(const Duration(days: 1));

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
      final resAmenidades = await _svc.listarAmenidades(activa: true);
      final resReservas = await _svc.listarReservas();
      final resAgenda = await _svc.agenda();
      final selId = _amenidadSeleccionadaId ??
          (resAmenidades.isNotEmpty ? resAmenidades.first.id : null);
      DisponibilidadDiaModel? disp;
      if (selId != null) {
        disp = await _svc.disponibilidadDia(selId, _fechaYmd(_fechaConsulta));
      }
      if (!mounted) return;
      setState(() {
        _amenidades = resAmenidades;
        _reservas = resReservas.resultados;
        _agenda = resAgenda;
        _amenidadSeleccionadaId = selId;
        _disponibilidadDia = disp;
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

  Future<void> _cargarDisponibilidad() async {
    final id = _amenidadSeleccionadaId;
    if (id == null) return;
    try {
      final disp = await _svc.disponibilidadDia(id, _fechaYmd(_fechaConsulta));
      if (!mounted) return;
      setState(() => _disponibilidadDia = disp);
    } catch (e) {
      if (!mounted) return;
      avisoSnack(context, e.toString(), error: true);
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
                  icon: Icon(Icons.event_available_rounded),
                  label: Text('Mis reservas'),
                ),
                ButtonSegment(
                  value: 1,
                  icon: Icon(Icons.schedule_rounded),
                  label: Text('Disponibilidad'),
                ),
                ButtonSegment(
                  value: 2,
                  icon: Icon(Icons.calendar_month_rounded),
                  label: Text('Agenda'),
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
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _amenidades.isEmpty ? null : _abrirDialogoSolicitar,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Solicitar reserva'),
                ),
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
          _vistaMisReservas()
        else if (_tab == 1)
          _vistaDisponibilidad()
        else
          _vistaAgenda(),
      ],
    );
  }

  Widget _vistaMisReservas() {
    if (_reservas.isEmpty) {
      return const PanelVacio(
        icono: Icons.event_busy_rounded,
        titulo: 'Aún no tienes reservas registradas',
        subtitulo: 'Usa el botón «Solicitar reserva» para agendar una zona común.',
      );
    }
    return Column(
      children: [
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
                      const Icon(Icons.pool_rounded, color: AppColors.oceanBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          r.amenidadNombre,
                          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                        ),
                      ),
                      ChipEstado(texto: r.estadoNombre, color: colorEstadoReserva(r.estado)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 6,
                    children: [
                      Text('Inicio: ${formatoFechaHora(r.fechaInicio)}'),
                      Text('Fin: ${formatoFechaHora(r.fechaFin)}'),
                      if (r.numPersonas != null) Text('Personas: ${r.numPersonas}'),
                      if (r.inmuebleCodigo != null) Text('Inmueble: ${r.inmuebleCodigo}'),
                    ],
                  ),
                  if (r.observaciones != null && r.observaciones!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Observaciones: ${r.observaciones}',
                        style: const TextStyle(color: Colors.black54)),
                  ],
                  if (r.motivoCancelacion != null && r.motivoCancelacion!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text('Motivo: ${r.motivoCancelacion}',
                        style: TextStyle(color: Colors.red.shade700)),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () => mostrarHistorialReserva(context, _svc, r),
                        icon: const Icon(Icons.history_rounded, size: 18),
                        label: const Text('Historial'),
                      ),
                      if (r.puedeCancelar) ...[
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: () => _cancelarReserva(r),
                          icon: const Icon(Icons.cancel_outlined, size: 18, color: Colors.redAccent),
                          label: const Text('Cancelar', style: TextStyle(color: Colors.redAccent)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _vistaDisponibilidad() {
    final disp = _disponibilidadDia;
    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<int>(
                    initialValue: _amenidadSeleccionadaId,
                    decoration: const InputDecoration(
                      labelText: 'Amenidad',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final a in _amenidades)
                        DropdownMenuItem(value: a.id, child: Text(a.nombre)),
                    ],
                    onChanged: (v) {
                      setState(() => _amenidadSeleccionadaId = v);
                      _cargarDisponibilidad();
                    },
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () async {
                    final f = await showDatePicker(
                      context: context,
                      initialDate: _fechaConsulta,
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 90)),
                    );
                    if (f != null) {
                      setState(() => _fechaConsulta = f);
                      _cargarDisponibilidad();
                    }
                  },
                  icon: const Icon(Icons.event_rounded),
                  label: Text('Fecha: ${_fechaYmd(_fechaConsulta)}'),
                ),
              ],
            ),
            const Divider(height: 32),
            if (disp == null)
              const Text('Selecciona una amenidad para consultar sus horarios.')
            else ...[
              Text(
                '${disp.amenidad} · ${disp.fecha}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                'Duración permitida: ${disp.duracionMinMinutos} a ${disp.duracionMaxMinutos} min'
                '${disp.capacidad != null ? ' · Aforo máx.: ${disp.capacidad} personas' : ''}',
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              const Text('Franjas disponibles para reservar:',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (disp.libres.isEmpty)
                const Text('No hay franjas disponibles en esta fecha.',
                    style: TextStyle(color: Colors.black54))
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final l in disp.libres)
                      ChipEstado(
                        texto: '${_horaHm(l.inicio)} – ${_horaHm(l.fin)}',
                        color: Colors.green.shade700,
                      ),
                  ],
                ),
              if (disp.ocupados.isNotEmpty) ...[
                const SizedBox(height: 18),
                const Text('Franjas ocupadas o bloqueadas:',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final o in disp.ocupados)
                      ChipEstado(
                        texto:
                            '${_horaHm(o.inicio)} – ${_horaHm(o.fin)} (${o.detalle ?? o.tipo ?? 'Ocupado'})',
                        color: Colors.red.shade700,
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _vistaAgenda() {
    if (_agenda.isEmpty) {
      return const PanelVacio(
        icono: Icons.calendar_today_rounded,
        titulo: 'Agenda sin eventos próximos',
        subtitulo: 'No hay reservas ni bloqueos programados para los próximos 30 días.',
      );
    }
    return Column(
      children: [
        for (final e in _agenda)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    (e.tipo == 'BLOQUEO' ? Colors.red : AppColors.oceanBlue).withAlpha(28),
                child: Icon(
                  e.tipo == 'BLOQUEO' ? Icons.lock_clock_rounded : Icons.event_rounded,
                  color: e.tipo == 'BLOQUEO' ? Colors.red.shade700 : AppColors.oceanBlue,
                ),
              ),
              title: Text(e.titulo, style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(
                '${e.amenidad} · ${formatoFechaHora(e.inicio)} a ${_horaHm(e.fin)}'
                '${e.motivo != null ? ' · ${e.motivo}' : ''}',
              ),
              trailing: e.estadoNombre != null
                  ? ChipEstado(
                      texto: e.estadoNombre!,
                      color: colorEstadoReserva(e.estado ?? ''),
                    )
                  : ChipEstado(
                      texto: e.tipo == 'BLOQUEO' ? 'Bloqueo' : 'Ocupado',
                      color: e.tipo == 'BLOQUEO' ? Colors.red.shade700 : Colors.blueGrey,
                    ),
            ),
          ),
      ],
    );
  }

  Future<void> _cancelarReserva(ReservaModel r) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancelar reserva en ${r.amenidadNombre}'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Motivo de cancelación (opcional)',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Volver')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar cancelación'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _svc.cancelarReserva(r.id, motivo: ctrl.text.trim());
      if (!mounted) return;
      avisoSnack(context, 'Reserva cancelada correctamente.');
      await _cargarTodo();
    } on ApiException catch (e) {
      if (!mounted) return;
      avisoSnack(context, e.mensaje, error: true);
    }
  }

  Future<void> _abrirDialogoSolicitar() async {
    AmenidadModel amenidad = _amenidades.first;
    DateTime fecha = DateTime.now().add(const Duration(days: 2));
    TimeOfDay inicio = const TimeOfDay(hour: 10, minute: 0);
    TimeOfDay fin = const TimeOfDay(hour: 12, minute: 0);
    final personasCtrl = TextEditingController(text: '4');
    final obsCtrl = TextEditingController();
    String? errorLocal;
    bool enviando = false;

    final creada = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModal) => AlertDialog(
          title: const Text('Solicitar reserva de zona común'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<AmenidadModel>(
                    initialValue: amenidad,
                    decoration: const InputDecoration(
                      labelText: 'Zona común / Amenidad',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final a in _amenidades)
                        DropdownMenuItem(
                          value: a,
                          child: Text(
                            '${a.nombre}${a.capacidad != null ? ' (máx. ${a.capacidad})' : ''}',
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      if (v != null) setModal(() => amenidad = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final f = await showDatePicker(
                              context: ctx,
                              initialDate: fecha,
                              firstDate: DateTime.now(),
                              lastDate: DateTime.now().add(const Duration(days: 90)),
                            );
                            if (f != null) setModal(() => fecha = f);
                          },
                          icon: const Icon(Icons.calendar_today_rounded, size: 18),
                          label: Text(_fechaYmd(fecha)),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(context: ctx, initialTime: inicio);
                            if (t != null) setModal(() => inicio = t);
                          },
                          icon: const Icon(Icons.access_time_rounded, size: 18),
                          label: Text(
                              'Inicio ${inicio.hour.toString().padLeft(2, '0')}:${inicio.minute.toString().padLeft(2, '0')}'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final t = await showTimePicker(context: ctx, initialTime: fin);
                            if (t != null) setModal(() => fin = t);
                          },
                          icon: const Icon(Icons.access_time_filled_rounded, size: 18),
                          label: Text(
                              'Fin ${fin.hour.toString().padLeft(2, '0')}:${fin.minute.toString().padLeft(2, '0')}'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: personasCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número de asistentes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: obsCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'Observaciones (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (errorLocal != null) ...[
                    const SizedBox(height: 12),
                    Text(errorLocal!, style: TextStyle(color: Colors.red.shade700)),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: enviando ? null : () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: enviando
                  ? null
                  : () async {
                      final numPersonas = int.tryParse(personasCtrl.text.trim()) ?? 0;
                      if (numPersonas < 1) {
                        setModal(() => errorLocal = 'Ingresa al menos 1 asistente.');
                        return;
                      }
                      final dtIni = DateTime(
                          fecha.year, fecha.month, fecha.day, inicio.hour, inicio.minute);
                      final dtFin =
                          DateTime(fecha.year, fecha.month, fecha.day, fin.hour, fin.minute);
                      setModal(() {
                        enviando = true;
                        errorLocal = null;
                      });
                      try {
                        await _svc.crearReserva({
                          'amenidad': amenidad.id,
                          'fecha_inicio': dtIni.toUtc().toIso8601String(),
                          'fecha_fin': dtFin.toUtc().toIso8601String(),
                          'num_personas': numPersonas,
                          if (obsCtrl.text.trim().isNotEmpty)
                            'observaciones': obsCtrl.text.trim(),
                        });
                        if (ctx.mounted) Navigator.pop(ctx, true);
                      } on ApiException catch (e) {
                        setModal(() {
                          enviando = false;
                          errorLocal = e.mensaje;
                        });
                      }
                    },
              child: const Text('Enviar solicitud'),
            ),
          ],
        ),
      ),
    );

    if (creada == true && mounted) {
      avisoSnack(context, 'Reserva registrada correctamente.');
      await _cargarTodo();
    }
  }
}

Future<void> mostrarHistorialReserva(
  BuildContext context,
  ReservasService svc,
  ReservaModel reserva,
) async {
  try {
    final eventos = await svc.historialReserva(reserva.id);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Historial · ${reserva.amenidadNombre}'),
        content: SizedBox(
          width: 480,
          child: eventos.isEmpty
              ? const Text('Sin eventos registrados.')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final ev in eventos)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.timeline_rounded, color: AppColors.oceanBlue),
                        title: Text(
                          '${ev.estadoAnterior != null ? '${ev.estadoAnterior} → ' : ''}${ev.estadoNuevoNombre}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          '${formatoFechaHora(ev.fecha)}'
                          '${ev.usuarioNombre != null ? ' · ${ev.usuarioNombre}' : ' · Sistema'}'
                          '${ev.detalle != null ? '\n${ev.detalle}' : ''}',
                        ),
                      ),
                  ],
                ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar')),
        ],
      ),
    );
  } on ApiException catch (e) {
    if (!context.mounted) return;
    avisoSnack(context, e.mensaje, error: true);
  }
}

