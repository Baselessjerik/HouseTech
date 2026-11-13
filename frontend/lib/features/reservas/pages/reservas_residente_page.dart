import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../comunicados/comunicados_api.dart';
import '../../comunicados/widgets/ui.dart';
import '../formato_hora.dart';
import '../models/reservas_models.dart';
import '../services/reservas_service.dart';

String _fechaYmd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String _horaHm(DateTime d) => horaDe(d);

/// Fecha y hora con el formato elegido por el usuario (24 h o a. m./p. m.).
String formatoFechaHora(DateTime d) => fechaHoraDe(d);

bool _mismoDia(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// Busca en una reserva por amenidad, estado, inmueble, residente, observaciones y fecha.
bool reservaCoincide(ReservaModel r, String consulta) => coincideBusqueda(consulta, [
      r.amenidadNombre,
      r.estadoNombre,
      r.estado,
      r.inmuebleCodigo,
      r.residente,
      r.observaciones,
      _fechaYmd(r.fechaInicio),
      fechaHoraDe(r.fechaInicio),
    ]);

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

  // Búsqueda (barra superior)
  final _busquedaCtrl = TextEditingController();
  String _busqueda = '';

  @override
  void initState() {
    super.initState();
    FormatoHora.cargar();
    _cargarTodo();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
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

  // --- Búsqueda ---------------------------------------------------------------------------

  List<ReservaModel> get _reservasFiltradas =>
      [for (final r in _reservas) if (reservaCoincide(r, _busqueda)) r];

  List<EventoAgendaModel> get _agendaFiltrada => [
        for (final e in _agenda)
          if (coincideBusqueda(_busqueda, [
            e.titulo,
            e.amenidad,
            e.estadoNombre,
            e.motivo,
            e.tipo == 'BLOQUEO' ? 'bloqueo' : 'reserva',
            _fechaYmd(e.inicio),
            fechaHoraDe(e.inicio),
          ]))
            e,
      ];

  List<AmenidadModel> get _amenidadesFiltradas => [
        for (final a in _amenidades)
          if (coincideBusqueda(_busqueda, [a.nombre, a.descripcion])) a,
      ];

  void _alBuscar(String valor) {
    setState(() => _busqueda = valor);
    // En «Disponibilidad», si la amenidad elegida ya no coincide, se pasa a la primera que sí.
    final coincidentes = _amenidadesFiltradas;
    if (coincidentes.isNotEmpty &&
        !coincidentes.any((a) => a.id == _amenidadSeleccionadaId)) {
      setState(() => _amenidadSeleccionadaId = coincidentes.first.id);
      _cargarDisponibilidad();
    }
  }

  Widget _sinResultados() => PanelVacio(
        icono: Icons.search_off_rounded,
        titulo: 'Sin resultados para «${_busqueda.trim()}»',
        subtitulo: 'Prueba con otro nombre de amenidad, estado o inmueble.',
        accion: TextButton(
          onPressed: () {
            _busquedaCtrl.clear();
            _alBuscar('');
          },
          child: const Text('Limpiar búsqueda'),
        ),
      );

  // --- Vista ------------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // Se reconstruye al cambiar entre 24 h y a. m./p. m.
    return ValueListenableBuilder<bool>(
      valueListenable: FormatoHora.usar24h,
      builder: (context, _, __) => _contenido(),
    );
  }

  Widget _contenido() {
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                const SelectorFormatoHora(),
                IconButton(
                  tooltip: 'Actualizar',
                  onPressed: _cargarTodo,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                FilledButton.icon(
                  onPressed: _amenidades.isEmpty ? null : () => _abrirDialogoSolicitar(),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Solicitar reserva'),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),
        BarraBusquedaReservas(
          controlador: _busquedaCtrl,
          onCambio: _alBuscar,
          sugerencia: _tab == 1
              ? 'Buscar amenidad…'
              : 'Buscar por amenidad, estado, inmueble o fecha (AAAA-MM-DD)…',
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
    final reservas = _reservasFiltradas;
    if (reservas.isEmpty) return _sinResultados();
    return Column(
      children: [
        for (final r in reservas)
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
    final coincidentes = _amenidadesFiltradas;
    if (_busqueda.trim().isNotEmpty && coincidentes.isEmpty) return _sinResultados();
    // La amenidad elegida siempre está en la lista, aunque no coincida con la búsqueda.
    final opciones = [
      ...coincidentes,
      for (final a in _amenidades)
        if (a.id == _amenidadSeleccionadaId && !coincidentes.contains(a)) a,
    ];
    AmenidadModel? amenidadSel;
    for (final a in _amenidades) {
      if (a.id == _amenidadSeleccionadaId) amenidadSel = a;
    }
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
                    key: ValueKey('amenidad-$_amenidadSeleccionadaId'),
                    initialValue: _amenidadSeleccionadaId,
                    decoration: const InputDecoration(
                      labelText: 'Amenidad',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final a in opciones)
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
                    final hoy = DateTime.now();
                    final f = await showDatePicker(
                      context: context,
                      initialDate: _fechaConsulta,
                      firstDate: DateTime(hoy.year, hoy.month, hoy.day),
                      lastDate: hoy.add(const Duration(days: 90)),
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
                [
                  if (disp.horarios.isNotEmpty)
                    'Horario: ${disp.horarios.map((h) => '${horaDeTexto(h['apertura']!)} – ${horaDeTexto(h['cierre']!)}').join(', ')}',
                  'Duración permitida: ${disp.duracionMinMinutos} a ${disp.duracionMaxMinutos} min',
                  if (disp.capacidad != null) 'Aforo máx.: ${disp.capacidad} personas',
                ].join(' · '),
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 16),
              PanelFranjasDia(
                disponibilidad: disp,
                onElegirLibre: amenidadSel == null
                    ? null
                    : (franja) => _abrirDialogoSolicitar(
                          amenidadInicial: amenidadSel,
                          inicioInicial: franja.inicio,
                          finInicial: _finSugerido(franja, disp.duracionMaxMinutos),
                        ),
              ),
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
    final agenda = _agendaFiltrada;
    if (agenda.isEmpty) return _sinResultados();
    return Column(
      children: [
        for (final e in agenda)
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

  Future<void> _abrirDialogoSolicitar({
    AmenidadModel? amenidadInicial,
    DateTime? inicioInicial,
    DateTime? finInicial,
  }) async {
    final creada = await showDialog<bool>(
      context: context,
      builder: (_) => DialogoSolicitarReserva(
        servicio: _svc,
        amenidades: _amenidades,
        amenidadInicial: amenidadInicial,
        inicioInicial: inicioInicial,
        finInicial: finInicial,
      ),
    );
    if (creada == true && mounted) {
      avisoSnack(context, 'Reserva registrada correctamente.');
      await _cargarTodo();
    }
  }
}

/// Fin sugerido al elegir una franja libre: lo que alcance de la franja sin pasar la duración máxima.
DateTime _finSugerido(FranjaTiempoModel franja, int duracionMaxMinutos) {
  final maximo = franja.inicio.add(Duration(minutes: duracionMaxMinutos));
  return franja.fin.isBefore(maximo) ? franja.fin : maximo;
}

/// Franjas del día: libres (se pueden tocar para reservar), ocupadas/bloqueadas y horas que ya pasaron.
class PanelFranjasDia extends StatelessWidget {
  const PanelFranjasDia({super.key, required this.disponibilidad, this.onElegirLibre});

  final DisponibilidadDiaModel disponibilidad;
  final ValueChanged<FranjaTiempoModel>? onElegirLibre;

  /// Desde la apertura hasta `reservable_desde`, si ese corte cae dentro del día consultado.
  ({DateTime desde, DateTime hasta})? _franjaPasada() {
    final d = disponibilidad;
    final corte = d.reservableDesde;
    final fecha = DateTime.tryParse(d.fecha);
    if (corte == null || fecha == null || d.horarios.isEmpty) return null;
    final ap = d.horarios.first['apertura']!.split(':');
    final apertura = DateTime(fecha.year, fecha.month, fecha.day,
        int.tryParse(ap[0]) ?? 0, ap.length > 1 ? int.tryParse(ap[1]) ?? 0 : 0);
    final finDia = DateTime(fecha.year, fecha.month, fecha.day + 1);
    if (!corte.isAfter(apertura)) return null;
    return (desde: apertura, hasta: corte.isBefore(finDia) ? corte : finDia);
  }

  @override
  Widget build(BuildContext context) {
    final d = disponibilidad;
    final pasada = _franjaPasada();
    final hoy = pasada != null && _mismoDia(pasada.desde, DateTime.now());
    final todoPasado = pasada != null && !pasada.hasta.isBefore(DateTime.tryParse(d.fecha)!.add(const Duration(days: 1)));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!d.abierta)
          const Text('La amenidad no abre este día.', style: TextStyle(color: Colors.black54))
        else ...[
          Text(
            onElegirLibre != null
                ? 'Horarios disponibles (toca uno para reservarlo):'
                : 'Horarios disponibles:',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          if (d.libres.isEmpty)
            Text(
              todoPasado
                  ? 'Este día ya pasó; ningún horario está disponible.'
                  : 'No hay horarios disponibles en esta fecha.',
              style: const TextStyle(color: Colors.black54),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in d.libres)
                  ActionChip(
                    avatar: Icon(Icons.check_circle_rounded, size: 18, color: Colors.green.shade700),
                    label: Text('${horaDe(l.inicio)} – ${horaDe(l.fin)} · Disponible'),
                    side: BorderSide(color: Colors.green.shade300),
                    backgroundColor: Colors.green.shade50,
                    onPressed: onElegirLibre == null ? null : () => onElegirLibre!(l),
                  ),
              ],
            ),
          if (d.ocupados.isNotEmpty || (pasada != null && !todoPasado)) ...[
            const SizedBox(height: 18),
            const Text('Horarios no disponibles:', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (pasada != null && !todoPasado)
                  ChipEstado(
                    texto: '${horaDe(pasada.desde)} – ${horaDe(pasada.hasta)} · '
                        '${hoy ? 'Ya pasó o sin anticipación mínima' : 'Sin anticipación mínima'}',
                    color: Colors.grey.shade700,
                  ),
                for (final o in d.ocupados)
                  ChipEstado(
                    texto: '${horaDe(o.inicio)} – ${horaDe(o.fin)} · '
                        '${o.tipo == 'BLOQUEO' ? 'Bloqueado${o.detalle != null ? ': ${o.detalle}' : ''}' : 'Ocupado'}',
                    color: Colors.red.shade700,
                  ),
              ],
            ),
          ],
        ],
      ],
    );
  }
}

/// Diálogo para solicitar una reserva. Mientras el residente elige amenidad, fecha y horas,
/// muestra los horarios del día y verifica en el backend si el horario está disponible.
class DialogoSolicitarReserva extends StatefulWidget {
  const DialogoSolicitarReserva({
    super.key,
    required this.servicio,
    required this.amenidades,
    this.amenidadInicial,
    this.inicioInicial,
    this.finInicial,
  });

  final ReservasService servicio;
  final List<AmenidadModel> amenidades;
  final AmenidadModel? amenidadInicial;
  final DateTime? inicioInicial;
  final DateTime? finInicial;

  @override
  State<DialogoSolicitarReserva> createState() => _DialogoSolicitarReservaState();
}

class _DialogoSolicitarReservaState extends State<DialogoSolicitarReserva> {
  late AmenidadModel _amenidad;
  late DateTime _fecha;
  late TimeOfDay _inicio;
  late TimeOfDay _fin;
  final _personasCtrl = TextEditingController(text: '4');
  final _obsCtrl = TextEditingController();
  String? _errorLocal;
  bool _enviando = false;

  DisponibilidadDiaModel? _dia;
  String? _claveDia;
  VerificacionHorarioModel? _verificacion;
  bool _verificando = true; // la primera verificación arranca en initState
  int _consulta = 0;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _amenidad = widget.amenidadInicial ?? widget.amenidades.first;
    final ini = widget.inicioInicial;
    final fin = widget.finInicial;
    _fecha = ini ?? DateTime.now().add(const Duration(days: 2));
    _inicio = ini != null ? TimeOfDay.fromDateTime(ini) : const TimeOfDay(hour: 10, minute: 0);
    _fin = fin != null ? TimeOfDay.fromDateTime(fin) : const TimeOfDay(hour: 12, minute: 0);
    _consultar();
  }

  @override
  void dispose() {
    _espera?.cancel();
    _personasCtrl.dispose();
    _obsCtrl.dispose();
    super.dispose();
  }

  DateTime get _dtInicio => DateTime(_fecha.year, _fecha.month, _fecha.day, _inicio.hour, _inicio.minute);
  DateTime get _dtFin => DateTime(_fecha.year, _fecha.month, _fecha.day, _fin.hour, _fin.minute);

  /// Vuelve a verificar tras un cambio (con una pequeña espera si se está escribiendo).
  void _cambio({bool escribiendo = false}) {
    _espera?.cancel();
    if (escribiendo) {
      _espera = Timer(const Duration(milliseconds: 400), _consultar);
    } else {
      _consultar();
    }
  }

  Future<void> _consultar() async {
    final consulta = ++_consulta;
    final inicio = _dtInicio;
    final fin = _dtFin;
    final clave = '${_amenidad.id}-${_fechaYmd(_fecha)}';
    if (!_verificando) setState(() => _verificando = true);
    try {
      final dia = clave == _claveDia && _dia != null
          ? _dia!
          : await widget.servicio.disponibilidadDia(_amenidad.id, _fechaYmd(_fecha));
      VerificacionHorarioModel verificacion;
      if (!inicio.isAfter(DateTime.now())) {
        verificacion = const VerificacionHorarioModel(
          disponible: false,
          motivos: ['Ese horario ya pasó; ya no está disponible.'],
          codigos: ['HORARIO_PASADO'],
        );
      } else if (!fin.isAfter(inicio)) {
        verificacion = const VerificacionHorarioModel(
          disponible: false,
          motivos: ['La hora de fin debe ser posterior a la hora de inicio.'],
          codigos: ['FECHAS_INVALIDAS'],
        );
      } else {
        verificacion = await widget.servicio.verificarHorario(
          _amenidad.id,
          inicio: inicio,
          fin: fin,
          numPersonas: int.tryParse(_personasCtrl.text.trim()),
        );
      }
      if (!mounted || consulta != _consulta) return;
      setState(() {
        _dia = dia;
        _claveDia = clave;
        _verificacion = verificacion;
        _verificando = false;
      });
    } catch (_) {
      // Si la verificación falla, no se bloquea el envío: el backend valida igual al crear.
      if (!mounted || consulta != _consulta) return;
      setState(() {
        _verificacion = null;
        _verificando = false;
      });
    }
  }

  void _elegirFranja(FranjaTiempoModel franja) {
    final fin = _finSugerido(franja, _dia?.duracionMaxMinutos ?? 240);
    setState(() {
      _inicio = TimeOfDay.fromDateTime(franja.inicio);
      _fin = TimeOfDay.fromDateTime(fin);
    });
    _cambio();
  }

  Future<void> _enviar() async {
    final numPersonas = int.tryParse(_personasCtrl.text.trim()) ?? 0;
    if (numPersonas < 1) {
      setState(() => _errorLocal = 'Ingresa al menos 1 asistente.');
      return;
    }
    setState(() {
      _enviando = true;
      _errorLocal = null;
    });
    try {
      await widget.servicio.crearReserva({
        'amenidad': _amenidad.id,
        'fecha_inicio': _dtInicio.toUtc().toIso8601String(),
        'fecha_fin': _dtFin.toUtc().toIso8601String(),
        'num_personas': numPersonas,
        if (_obsCtrl.text.trim().isNotEmpty) 'observaciones': _obsCtrl.text.trim(),
      });
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _enviando = false;
        _errorLocal = e.mensaje;
      });
      _cambio(); // el horario pudo ocuparse mientras tanto
    }
  }

  Widget _estadoHorario() {
    if (_verificando && _verificacion == null) {
      return const Row(
        children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Verificando horario…'),
        ],
      );
    }
    final v = _verificacion;
    if (v == null) return const SizedBox.shrink();
    final color = v.disponible ? Colors.green.shade700 : Colors.red.shade700;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        border: Border.all(color: color.withAlpha(90)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(v.disponible ? Icons.check_circle_rounded : Icons.cancel_rounded, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.disponible
                      ? 'Este horario está disponible'
                      : v.yaNoDisponible
                          ? 'Ese horario ya no está disponible'
                          : 'Ese horario no se puede reservar',
                  style: TextStyle(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              if (_verificando)
                const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          for (final m in v.motivos)
            Padding(
              padding: const EdgeInsets.only(left: 32, top: 4),
              child: Text('• $m', style: TextStyle(color: color)),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hoy = DateTime.now();
    final bloqueado = _verificacion != null && !_verificacion!.disponible;
    return AlertDialog(
      title: const Text('Solicitar reserva de zona común'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<AmenidadModel>(
                initialValue: _amenidad,
                decoration: const InputDecoration(
                  labelText: 'Zona común / Amenidad',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final a in widget.amenidades)
                    DropdownMenuItem(
                      value: a,
                      child: Text('${a.nombre}${a.capacidad != null ? ' (máx. ${a.capacidad})' : ''}'),
                    ),
                ],
                onChanged: (v) {
                  if (v == null) return;
                  setState(() => _amenidad = v);
                  _cambio();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final f = await showDatePicker(
                          context: context,
                          initialDate: _fecha.isBefore(hoy) ? hoy : _fecha,
                          firstDate: DateTime(hoy.year, hoy.month, hoy.day),
                          lastDate: hoy.add(const Duration(days: 90)),
                        );
                        if (f == null) return;
                        setState(() => _fecha = f);
                        _cambio();
                      },
                      icon: const Icon(Icons.calendar_today_rounded, size: 18),
                      label: Text(_fechaYmd(_fecha)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final t = await elegirHora(context, _inicio);
                        if (t == null) return;
                        setState(() => _inicio = t);
                        _cambio();
                      },
                      icon: const Icon(Icons.access_time_rounded, size: 18),
                      label: Text('Inicio ${horaDeTime(_inicio)}'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final t = await elegirHora(context, _fin);
                        if (t == null) return;
                        setState(() => _fin = t);
                        _cambio();
                      },
                      icon: const Icon(Icons.access_time_filled_rounded, size: 18),
                      label: Text('Fin ${horaDeTime(_fin)}'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _estadoHorario(),
              if (_dia != null) ...[
                const SizedBox(height: 16),
                PanelFranjasDia(disponibilidad: _dia!, onElegirLibre: _elegirFranja),
              ],
              const SizedBox(height: 16),
              TextField(
                controller: _personasCtrl,
                keyboardType: TextInputType.number,
                onChanged: (_) => _cambio(escribiendo: true),
                decoration: const InputDecoration(
                  labelText: 'Número de asistentes',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _obsCtrl,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Observaciones (opcional)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_errorLocal != null) ...[
                const SizedBox(height: 12),
                Text(_errorLocal!, style: TextStyle(color: Colors.red.shade700)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _enviando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _enviando || bloqueado ? null : _enviar,
          child: const Text('Enviar solicitud'),
        ),
      ],
    );
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

