import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/empty_state.dart';
import '../models/modelos.dart';
import '../providers/comunicados_providers.dart';
import '../services/comunicados_service.dart';
import '../widgets/ui.dart';

/// Administración de mantenimientos (RF1) y bloqueos de amenidades (RF2-RF5, RF7).
class BloqueosAdminPage extends ConsumerStatefulWidget {
  const BloqueosAdminPage({super.key});

  @override
  ConsumerState<BloqueosAdminPage> createState() => _BloqueosAdminPageState();
}

class _BloqueosAdminPageState extends ConsumerState<BloqueosAdminPage> {
  int _vista = 1;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(mantenimientosProvider.notifier).recargar();
      ref.read(bloqueosProvider.notifier).recargar();
      ref.invalidate(disponibilidadProvider);
    });
  }

  Future<List<DisponibilidadAmenidad>?> _amenidades() async {
    try {
      return await ref.read(disponibilidadProvider(null).future);
    } catch (e) {
      if (mounted) mostrarMensaje(context, 'No se pudieron cargar las amenidades.', error: true);
      return null;
    }
  }

  Future<void> _nuevo() async {
    final amenidades = await _amenidades();
    if (amenidades == null || !mounted) return;
    if (_vista == 0) {
      final datos = await showDialog<Map<String, dynamic>>(
          context: context, builder: (_) => MantenimientoFormDialog(amenidades: amenidades));
      if (datos == null || !mounted) return;
      final ok = await ejecutarConConfirmacion(
        context,
        (c) => ref.read(comunicadosServiceProvider).guardarMantenimiento(datos: datos, confirmar: c),
        exito: 'Mantenimiento registrado',
      );
      if (ok) {
        ref.read(mantenimientosProvider.notifier).recargar();
        ref.read(bloqueosProvider.notifier).recargar();
      }
    } else {
      final datos = await showDialog<Map<String, dynamic>>(
          context: context, builder: (_) => BloqueoFormDialog(amenidades: amenidades));
      if (datos == null || !mounted) return;
      final ok = await ejecutarConConfirmacion(
        context,
        (c) => ref.read(comunicadosServiceProvider).guardarBloqueo(datos: datos, confirmar: c),
        exito: 'Bloqueo programado',
      );
      if (ok) ref.read(bloqueosProvider.notifier).recargar();
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Encabezado(
            titulo: 'Bloqueos y mantenimientos',
            subtitulo: 'Programa mantenimientos y bloquea amenidades; los residentes son notificados.',
            accion: FilledButton.icon(
              onPressed: _nuevo,
              icon: const Icon(Icons.add_rounded),
              label: Text(_vista == 0 ? 'Nuevo mantenimiento' : 'Nuevo bloqueo'),
            ),
          ),
          const SizedBox(height: 20),
          SelectorVista(etiquetas: const ['Mantenimientos', 'Bloqueos'], indice: _vista, onCambio: (i) => setState(() => _vista = i)),
          const SizedBox(height: 20),
          if (_vista == 0) const _MantenimientosVista() else const _BloqueosVista(),
        ],
      );
}

// ------------------------------------------------------------------------ mantenimientos
class _MantenimientosVista extends ConsumerWidget {
  const _MantenimientosVista();

  static const _estados = [
    OpcionSelector<String>('', 'Todos'),
    OpcionSelector<String>('PROGRAMADO', 'Programados'),
    OpcionSelector<String>('EN_CURSO', 'En curso'),
    OpcionSelector<String>('FINALIZADO', 'Finalizados'),
    OpcionSelector<String>('CANCELADO', 'Cancelados'),
  ];

  Future<void> _editar(BuildContext context, WidgetRef ref, Mantenimiento m) async {
    List<DisponibilidadAmenidad> amenidades;
    try {
      amenidades = await ref.read(disponibilidadProvider(null).future);
    } catch (_) {
      if (context.mounted) mostrarMensaje(context, 'No se pudieron cargar las amenidades.', error: true);
      return;
    }
    if (!context.mounted) return;
    final datos = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => MantenimientoFormDialog(amenidades: amenidades, existente: m));
    if (datos == null || !context.mounted) return;
    final ok = await ejecutarConConfirmacion(
      context,
      (c) => ref.read(comunicadosServiceProvider).guardarMantenimiento(id: m.id, datos: datos, confirmar: c),
      exito: 'Mantenimiento actualizado',
    );
    if (ok) {
      ref.read(mantenimientosProvider.notifier).recargar();
      ref.read(bloqueosProvider.notifier).recargar();
    }
  }

  Future<void> _transicion(BuildContext context, WidgetRef ref, Mantenimiento m, String accion) async {
    final textos = {
      'iniciar': ('Iniciar mantenimiento', 'Se marcará «${m.titulo}» como en curso.', 'Iniciar'),
      'finalizar': (
        'Finalizar mantenimiento',
        'Se marcará como finalizado y se liberarán los bloqueos asociados.',
        'Finalizar'
      ),
      'cancelar': (
        'Cancelar mantenimiento',
        'Se cancelará «${m.titulo}» y se liberarán los bloqueos asociados. Se avisará a los residentes.',
        'Cancelar mantenimiento'
      ),
    }[accion]!;
    final ok = await confirmar(context,
        titulo: textos.$1, mensaje: textos.$2, textoConfirmar: textos.$3, peligro: accion == 'cancelar');
    if (!ok || !context.mounted) return;
    final hecho = await ejecutarSimple(
      context,
      () => ref.read(comunicadosServiceProvider).cambiarEstadoMantenimiento(m.id, accion),
      exito: 'Mantenimiento actualizado',
    );
    if (hecho) {
      ref.read(mantenimientosProvider.notifier).recargar();
      ref.read(bloqueosProvider.notifier).recargar();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(mantenimientosProvider);
    final notifier = ref.read(mantenimientosProvider.notifier);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final e in _estados)
          ChoiceChip(
            label: Text(e.etiqueta),
            selected: (notifier.estado ?? '') == e.valor,
            onSelected: (_) => notifier.filtrarEstado(e.valor.isEmpty ? null : e.valor),
          ),
      ]),
      const SizedBox(height: 16),
      ListaPaginada<Mantenimiento>(
        estado: estado,
        onReintentar: notifier.recargar,
        onMas: notifier.masResultados,
        vacio: const EmptyState(
          icon: Icons.build_circle_outlined,
          titulo: 'Sin mantenimientos',
          detalle: 'Registra el primer mantenimiento de una zona común.',
        ),
        itemBuilder: (context, m) => AppCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              backgroundColor: colorEstado(m.estado).withAlpha(30),
              child: Icon(Icons.build_rounded, color: colorEstado(m.estado)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(m.titulo,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  EstadoChip(m.estadoNombre ?? nombreEstado(m.estado), color: colorEstado(m.estado)),
                ]),
                const SizedBox(height: 6),
                Text('${m.amenidadNombre ?? 'Zonas comunes'} · ${rangoFechas(m.fechaInicio, m.fechaFin)}',
                    style: const TextStyle(color: Colors.black87)),
                if (m.responsable != null && m.responsable!.isNotEmpty)
                  Text('Responsable: ${m.responsable}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                if (m.descripcion != null && m.descripcion!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(m.descripcion!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                  ),
                if (m.bloqueosActivos > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('${m.bloqueosActivos} bloqueo(s) activo(s) asociado(s)',
                        style: const TextStyle(color: Color(0xFFD97706), fontSize: 12.5, fontWeight: FontWeight.w600)),
                  ),
              ]),
            ),
            if (m.editable)
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                onSelected: (a) => a == 'editar' ? _editar(context, ref, m) : _transicion(context, ref, m, a),
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'editar', child: Text('Editar')),
                  if (m.estado == 'PROGRAMADO') const PopupMenuItem(value: 'iniciar', child: Text('Iniciar')),
                  if (m.estado == 'EN_CURSO') const PopupMenuItem(value: 'finalizar', child: Text('Finalizar')),
                  const PopupMenuItem(value: 'cancelar', child: Text('Cancelar mantenimiento')),
                ],
              ),
          ]),
        ),
      ),
    ]);
  }
}

// ----------------------------------------------------------------------------- bloqueos
class _BloqueosVista extends ConsumerWidget {
  const _BloqueosVista();

  static const _filtros = [
    OpcionSelector<int>(0, 'Todos'),
    OpcionSelector<int>(1, 'Vigentes y próximos'),
    OpcionSelector<int>(2, 'Finalizados o cancelados'),
  ];

  Future<void> _editar(BuildContext context, WidgetRef ref, Bloqueo b) async {
    List<DisponibilidadAmenidad> amenidades;
    try {
      amenidades = await ref.read(disponibilidadProvider(null).future);
    } catch (_) {
      if (context.mounted) mostrarMensaje(context, 'No se pudieron cargar las amenidades.', error: true);
      return;
    }
    if (!context.mounted) return;
    final datos = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => BloqueoFormDialog(amenidades: amenidades, existente: b));
    if (datos == null || !context.mounted) return;
    final ok = await ejecutarConConfirmacion(
      context,
      (c) => ref.read(comunicadosServiceProvider).guardarBloqueo(id: b.id, datos: datos, confirmar: c),
      exito: 'Bloqueo actualizado',
    );
    if (ok) ref.read(bloqueosProvider.notifier).recargar();
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref, Bloqueo b) async {
    final ok = await confirmar(context,
        titulo: 'Cancelar bloqueo',
        mensaje: 'La amenidad «${b.amenidadNombre}» volverá a poder reservarse en ese horario y se avisará a los residentes.',
        textoConfirmar: 'Cancelar bloqueo',
        peligro: true);
    if (!ok || !context.mounted) return;
    final hecho = await ejecutarSimple(context, () => ref.read(comunicadosServiceProvider).cancelarBloqueo(b.id),
        exito: 'Bloqueo cancelado');
    if (hecho) ref.read(bloqueosProvider.notifier).recargar();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(bloqueosProvider);
    final notifier = ref.read(bloqueosProvider.notifier);
    final actual = notifier.activo == null ? 0 : (notifier.activo! ? 1 : 2);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in _filtros)
          ChoiceChip(
            label: Text(f.etiqueta),
            selected: actual == f.valor,
            onSelected: (_) => notifier.filtrarActivo(f.valor == 0 ? null : f.valor == 1),
          ),
      ]),
      const SizedBox(height: 16),
      ListaPaginada<Bloqueo>(
        estado: estado,
        onReintentar: notifier.recargar,
        onMas: notifier.masResultados,
        vacio: const EmptyState(
          icon: Icons.lock_clock_outlined,
          titulo: 'Sin bloqueos',
          detalle: 'Cuando bloquees una amenidad aparecerá en esta lista.',
        ),
        itemBuilder: (context, b) => AppCard(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(
              backgroundColor: colorEstado(b.estado).withAlpha(30),
              child: Icon(Icons.lock_clock_rounded, color: colorEstado(b.estado)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Wrap(spacing: 10, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  Text(b.amenidadNombre,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textDark)),
                  EstadoChip(nombreEstado(b.estado), color: colorEstado(b.estado)),
                ]),
                const SizedBox(height: 6),
                Text(rangoFechas(b.fechaInicio, b.fechaFin), style: const TextStyle(color: Colors.black87)),
                const SizedBox(height: 2),
                Text('Motivo: ${b.motivo}', style: const TextStyle(color: Colors.black54, fontSize: 13)),
                if (b.mantenimientoTitulo != null)
                  Text('Mantenimiento: ${b.mantenimientoTitulo}',
                      style: const TextStyle(color: Colors.black54, fontSize: 13)),
              ]),
            ),
            if (b.editable)
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                onSelected: (a) => a == 'editar' ? _editar(context, ref, b) : _cancelar(context, ref, b),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                  PopupMenuItem(value: 'cancelar', child: Text('Cancelar bloqueo')),
                ],
              ),
          ]),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------------------------ formularios
class MantenimientoFormDialog extends StatefulWidget {
  const MantenimientoFormDialog({super.key, required this.amenidades, this.existente});

  final List<DisponibilidadAmenidad> amenidades;
  final Mantenimiento? existente;

  @override
  State<MantenimientoFormDialog> createState() => _MantenimientoFormDialogState();
}

class _MantenimientoFormDialogState extends State<MantenimientoFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _descripcion;
  late final TextEditingController _responsable;
  late int _amenidad; // 0 = sin amenidad (zonas comunes)
  DateTime? _inicio;
  DateTime? _fin;
  bool _bloquear = true;
  String? _errorFechas;

  bool get _edita => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final m = widget.existente;
    _titulo = TextEditingController(text: m?.titulo ?? '');
    _descripcion = TextEditingController(text: m?.descripcion ?? '');
    _responsable = TextEditingController(text: m?.responsable ?? '');
    _amenidad = m?.amenidadId ?? 0;
    _inicio = m?.fechaInicio;
    _fin = m?.fechaFin;
  }

  @override
  void dispose() {
    _titulo.dispose();
    _descripcion.dispose();
    _responsable.dispose();
    super.dispose();
  }

  void _guardar() {
    final valido = _form.currentState!.validate();
    String? error;
    if (_inicio == null || _fin == null) {
      error = 'Selecciona la fecha de inicio y la de fin.';
    } else if (!_fin!.isAfter(_inicio!)) {
      error = 'La fecha de fin debe ser posterior a la de inicio.';
    }
    setState(() => _errorFechas = error);
    if (!valido || error != null) return;
    Navigator.pop(context, <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'descripcion': _descripcion.text.trim(),
      'responsable': _responsable.text.trim(),
      'amenidad': _amenidad == 0 ? null : _amenidad,
      'fecha_inicio': fechaParaApi(_inicio!),
      'fecha_fin': fechaParaApi(_fin!),
      if (!_edita) 'crear_bloqueo': _bloquear && _amenidad != 0,
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_edita ? 'Editar mantenimiento' : 'Nuevo mantenimiento'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 4),
                TextFormField(
                  controller: _titulo,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un título' : null,
                ),
                const SizedBox(height: 8),
                CampoSelector<int>(
                  etiqueta: 'Amenidad',
                  valor: _amenidad,
                  opciones: [
                    const OpcionSelector<int>(0, 'Zonas comunes (sin amenidad)'),
                    for (final a in widget.amenidades) OpcionSelector<int>(a.id, a.nombre),
                  ],
                  onCambio: (v) => setState(() => _amenidad = v),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _descripcion,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _responsable,
                  maxLength: 150,
                  decoration: const InputDecoration(labelText: 'Responsable (opcional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                SelectorFechaHora(etiqueta: 'Inicio', valor: _inicio, onCambio: (d) => setState(() => _inicio = d)),
                const SizedBox(height: 14),
                SelectorFechaHora(etiqueta: 'Fin', valor: _fin, onCambio: (d) => setState(() => _fin = d)),
                if (_errorFechas != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(_errorFechas!, style: const TextStyle(color: colorAlerta, fontSize: 12.5)),
                    ),
                  ),
                if (!_edita && _amenidad != 0)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bloquear la amenidad durante el mantenimiento'),
                    value: _bloquear,
                    onChanged: (v) => setState(() => _bloquear = v),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _guardar, child: Text(_edita ? 'Guardar cambios' : 'Registrar')),
        ],
      );
}

class BloqueoFormDialog extends StatefulWidget {
  const BloqueoFormDialog({super.key, required this.amenidades, this.existente});

  final List<DisponibilidadAmenidad> amenidades;
  final Bloqueo? existente;

  @override
  State<BloqueoFormDialog> createState() => _BloqueoFormDialogState();
}

class _BloqueoFormDialogState extends State<BloqueoFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _motivo;
  late int _amenidad; // 0 = sin elegir
  DateTime? _inicio;
  DateTime? _fin;
  String? _errorFechas;

  bool get _edita => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final b = widget.existente;
    _motivo = TextEditingController(text: b?.motivo ?? '');
    _amenidad = b?.amenidadId ?? 0;
    _inicio = b?.fechaInicio;
    _fin = b?.fechaFin;
  }

  @override
  void dispose() {
    _motivo.dispose();
    super.dispose();
  }

  void _guardar() {
    final valido = _form.currentState!.validate();
    String? error;
    if (_amenidad == 0) {
      error = 'Selecciona la amenidad a bloquear.';
    } else if (_inicio == null || _fin == null) {
      error = 'Selecciona la fecha de inicio y la de fin.';
    } else if (!_fin!.isAfter(_inicio!)) {
      error = 'La fecha de fin debe ser posterior a la de inicio.';
    }
    setState(() => _errorFechas = error);
    if (!valido || error != null) return;
    Navigator.pop(context, <String, dynamic>{
      if (!_edita) 'amenidad': _amenidad,
      'fecha_inicio': fechaParaApi(_inicio!),
      'fecha_fin': fechaParaApi(_fin!),
      'motivo': _motivo.text.trim(),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_edita ? 'Editar bloqueo' : 'Nuevo bloqueo'),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const SizedBox(height: 4),
                CampoSelector<int>(
                  etiqueta: 'Amenidad',
                  valor: _amenidad,
                  habilitado: !_edita,
                  opciones: [
                    if (_amenidad == 0) const OpcionSelector<int>(0, 'Selecciona una amenidad'),
                    for (final a in widget.amenidades) OpcionSelector<int>(a.id, a.nombre),
                  ],
                  onCambio: (v) => setState(() => _amenidad = v),
                ),
                const SizedBox(height: 14),
                SelectorFechaHora(etiqueta: 'Inicio', valor: _inicio, onCambio: (d) => setState(() => _inicio = d)),
                const SizedBox(height: 14),
                SelectorFechaHora(etiqueta: 'Fin', valor: _fin, onCambio: (d) => setState(() => _fin = d)),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _motivo,
                  maxLines: 3,
                  maxLength: 500,
                  decoration: const InputDecoration(labelText: 'Motivo del bloqueo', border: OutlineInputBorder()),
                  validator: (v) {
                    final t = v?.trim() ?? '';
                    if (t.isEmpty) return 'El motivo es obligatorio';
                    if (t.length < 3) return 'Describe un poco más el motivo';
                    return null;
                  },
                ),
                if (_errorFechas != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(_errorFechas!, style: const TextStyle(color: colorAlerta, fontSize: 12.5)),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _guardar, child: Text(_edita ? 'Guardar cambios' : 'Programar bloqueo')),
        ],
      );
}
