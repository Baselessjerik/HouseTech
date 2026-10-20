import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/empty_state.dart';
import '../comunicados_api.dart';
import '../models/modelos.dart';
import '../providers/comunicados_providers.dart';
import '../services/comunicados_service.dart';
import '../widgets/ui.dart';

/// Administración de comunicados (RF9-RF13, RF15) y categorías (RF12).
class ComunicadosAdminPage extends ConsumerStatefulWidget {
  const ComunicadosAdminPage({super.key});

  @override
  ConsumerState<ComunicadosAdminPage> createState() => _ComunicadosAdminPageState();
}

class _ComunicadosAdminPageState extends ConsumerState<ComunicadosAdminPage> {
  int _vista = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(comunicadosAdminProvider.notifier).recargar();
      ref.invalidate(categoriasProvider);
    });
  }

  Future<void> _nuevoComunicado() async {
    final categorias = await _categorias();
    if (categorias == null || !mounted) return;
    final datos = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => ComunicadoFormDialog(categorias: categorias));
    if (datos == null || !mounted) return;
    final ok = await ejecutarSimple(
        context, () => ref.read(comunicadosServiceProvider).guardarComunicado(datos: datos),
        exito: 'Comunicado guardado como borrador');
    if (ok) ref.read(comunicadosAdminProvider.notifier).recargar();
  }

  Future<List<CategoriaComunicado>?> _categorias() async {
    try {
      return await ref.read(categoriasProvider.future);
    } catch (_) {
      if (mounted) mostrarMensaje(context, 'No se pudieron cargar las categorías.', error: true);
      return null;
    }
  }

  Future<void> _nuevaCategoria() async {
    final datos = await showDialog<Map<String, dynamic>>(context: context, builder: (_) => const CategoriaFormDialog());
    if (datos == null || !mounted) return;
    final ok = await ejecutarSimple(
        context, () => ref.read(comunicadosServiceProvider).guardarCategoria(datos: datos),
        exito: 'Categoría creada');
    if (ok) ref.invalidate(categoriasProvider);
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Encabezado(
            titulo: 'Administrar comunicados',
            subtitulo: 'Crea, programa y publica avisos para los residentes.',
            accion: FilledButton.icon(
              onPressed: _vista == 0 ? _nuevoComunicado : _nuevaCategoria,
              icon: const Icon(Icons.add_rounded),
              label: Text(_vista == 0 ? 'Nuevo comunicado' : 'Nueva categoría'),
            ),
          ),
          const SizedBox(height: 20),
          SelectorVista(
              etiquetas: const ['Comunicados', 'Categorías'], indice: _vista, onCambio: (i) => setState(() => _vista = i)),
          const SizedBox(height: 20),
          if (_vista == 0) const _ComunicadosVista() else const _CategoriasVista(),
        ],
      );
}

// ------------------------------------------------------------------------- comunicados
class _ComunicadosVista extends ConsumerWidget {
  const _ComunicadosVista();

  static const _estados = [
    OpcionSelector<String>('', 'Todos'),
    OpcionSelector<String>('BORRADOR', 'Borradores'),
    OpcionSelector<String>('PROGRAMADO', 'Programados'),
    OpcionSelector<String>('PUBLICADO', 'Publicados'),
    OpcionSelector<String>('ARCHIVADO', 'Archivados'),
  ];

  String _audiencia(Comunicado c) {
    switch (c.audiencia) {
      case 'ROL':
        return 'Rol: ${c.rolDestinoCodigo ?? ''}';
      case 'USUARIOS':
        return '${c.destinatarios.length} destinatario(s)';
      default:
        return 'Todos';
    }
  }

  void _refrescar(WidgetRef ref) => ref.read(comunicadosAdminProvider.notifier).recargar();

  Future<void> _editar(BuildContext context, WidgetRef ref, Comunicado c) async {
    List<CategoriaComunicado> categorias;
    try {
      categorias = await ref.read(categoriasProvider.future);
    } catch (_) {
      if (context.mounted) mostrarMensaje(context, 'No se pudieron cargar las categorías.', error: true);
      return;
    }
    if (!context.mounted) return;
    final datos = await showDialog<Map<String, dynamic>>(
        context: context, builder: (_) => ComunicadoFormDialog(categorias: categorias, existente: c));
    if (datos == null || !context.mounted) return;
    final ok = await ejecutarSimple(
        context, () => ref.read(comunicadosServiceProvider).guardarComunicado(id: c.id, datos: datos),
        exito: 'Comunicado actualizado');
    if (ok) _refrescar(ref);
  }

  Future<void> _publicar(BuildContext context, WidgetRef ref, Comunicado c) async {
    final ok = await confirmar(context,
        titulo: 'Publicar comunicado',
        mensaje: '«${c.titulo}» será visible de inmediato y se notificará a su audiencia.',
        textoConfirmar: 'Publicar');
    if (!ok || !context.mounted) return;
    final hecho = await ejecutarSimple(context, () => ref.read(comunicadosServiceProvider).publicar(c.id),
        exito: 'Comunicado publicado');
    if (hecho) _refrescar(ref);
  }

  Future<void> _programar(BuildContext context, WidgetRef ref, Comunicado c) async {
    final fecha = await showDialog<DateTime>(context: context, builder: (_) => ProgramarDialog(actual: c.fechaProgramada));
    if (fecha == null || !context.mounted) return;
    final hecho = await ejecutarSimple(context, () => ref.read(comunicadosServiceProvider).programar(c.id, fecha),
        exito: 'Publicación programada');
    if (hecho) _refrescar(ref);
  }

  Future<void> _archivar(BuildContext context, WidgetRef ref, Comunicado c) async {
    final ok = await confirmar(context,
        titulo: 'Archivar comunicado',
        mensaje: 'Dejará de mostrarse a los residentes y ya no podrá editarse.',
        textoConfirmar: 'Archivar',
        peligro: true);
    if (!ok || !context.mounted) return;
    final hecho = await ejecutarSimple(context, () => ref.read(comunicadosServiceProvider).archivar(c.id),
        exito: 'Comunicado archivado');
    if (hecho) _refrescar(ref);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(comunicadosAdminProvider);
    final notifier = ref.read(comunicadosAdminProvider.notifier);
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
      ListaPaginada<Comunicado>(
        estado: estado,
        onReintentar: notifier.recargar,
        onMas: notifier.masResultados,
        vacio: const EmptyState(
          icon: Icons.campaign_outlined,
          titulo: 'Sin comunicados',
          detalle: 'Crea el primer comunicado para tus residentes.',
        ),
        itemBuilder: (context, c) => AppCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  EstadoChip(nombreEstado(c.estado), color: colorEstado(c.estado)),
                  if (c.categoriaNombre != null) EstadoChip(c.categoriaNombre!, color: c.colorCategoria),
                  Text(_audiencia(c), style: const TextStyle(color: Colors.black54, fontSize: 12.5)),
                ]),
              ),
              PopupMenuButton<String>(
                tooltip: 'Acciones',
                onSelected: (a) {
                  switch (a) {
                    case 'editar':
                      _editar(context, ref, c);
                    case 'publicar':
                      _publicar(context, ref, c);
                    case 'programar':
                      _programar(context, ref, c);
                    case 'archivar':
                      _archivar(context, ref, c);
                    case 'historial':
                      showDialog<void>(context: context, builder: (_) => HistorialDialog(comunicado: c));
                    case 'ver':
                      showDialog<void>(context: context, builder: (_) => _VistaPreviaDialog(c: c));
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'ver', child: Text('Ver contenido')),
                  if (c.estado != 'ARCHIVADO') const PopupMenuItem(value: 'editar', child: Text('Editar')),
                  if (c.estado == 'BORRADOR' || c.estado == 'PROGRAMADO')
                    const PopupMenuItem(value: 'publicar', child: Text('Publicar ahora')),
                  if (c.estado == 'BORRADOR' || c.estado == 'PROGRAMADO')
                    PopupMenuItem(value: 'programar', child: Text(c.estado == 'PROGRAMADO' ? 'Reprogramar' : 'Programar')),
                  const PopupMenuItem(value: 'historial', child: Text('Historial de cambios')),
                  if (c.estado != 'ARCHIVADO') const PopupMenuItem(value: 'archivar', child: Text('Archivar')),
                ],
              ),
            ]),
            const SizedBox(height: 8),
            Text(c.titulo,
                style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            const SizedBox(height: 4),
            Text(c.contenido, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
            const SizedBox(height: 8),
            Text(_fechas(c), style: const TextStyle(color: Colors.black45, fontSize: 12)),
          ]),
        ),
      ),
    ]);
  }

  String _fechas(Comunicado c) {
    final partes = <String>[];
    if (c.fechaPublicacion != null) partes.add('Publicado: ${fechaHora(c.fechaPublicacion!)}');
    if (c.estado == 'PROGRAMADO' && c.fechaProgramada != null) partes.add('Sale el ${fechaHora(c.fechaProgramada!)}');
    if (c.fechaExpiracion != null) partes.add('Expira: ${fechaHora(c.fechaExpiracion!)}');
    if (partes.isEmpty && c.createdAt != null) partes.add('Creado: ${fechaHora(c.createdAt!)}');
    return partes.join('  ·  ');
  }
}

class _VistaPreviaDialog extends StatelessWidget {
  const _VistaPreviaDialog({required this.c});

  final Comunicado c;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(c.titulo),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: SelectableText(c.contenido))),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
}

// -------------------------------------------------------------------------- categorías
class _CategoriasVista extends ConsumerWidget {
  const _CategoriasVista();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final datos = ref.watch(categoriasProvider);
    return datos.when(
      loading: () => const CargandoCaja(),
      error: (e, _) => ErrorCaja(mensaje: e.toString(), onReintentar: () => ref.invalidate(categoriasProvider)),
      data: (lista) => lista.isEmpty
          ? const EmptyState(icon: Icons.label_outline_rounded, titulo: 'Sin categorías', detalle: 'Crea una para clasificar tus avisos.')
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              for (final c in lista) ...[
                AppCard(
                  child: Row(children: [
                    CircleAvatar(radius: 14, backgroundColor: c.colorUi),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Flexible(
                            child: Text(c.nombre,
                                style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.textDark)),
                          ),
                          if (!c.activa) ...[
                            const SizedBox(width: 8),
                            const EstadoChip('Inactiva', color: Colors.grey),
                          ],
                        ]),
                        if (c.descripcion != null && c.descripcion!.isNotEmpty)
                          Text(c.descripcion!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
                      ]),
                    ),
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit_rounded),
                      onPressed: () async {
                        final d = await showDialog<Map<String, dynamic>>(
                            context: context, builder: (_) => CategoriaFormDialog(existente: c));
                        if (d == null || !context.mounted) return;
                        final ok = await ejecutarSimple(
                            context, () => ref.read(comunicadosServiceProvider).guardarCategoria(id: c.id, datos: d),
                            exito: 'Categoría actualizada');
                        if (ok) ref.invalidate(categoriasProvider);
                      },
                    ),
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline_rounded, color: colorAlerta),
                      onPressed: () async {
                        final ok = await confirmar(context,
                            titulo: 'Eliminar categoría',
                            mensaje: 'Los comunicados que la usan quedarán sin categoría. Si solo quieres ocultarla, edítala y desactívala.',
                            textoConfirmar: 'Eliminar',
                            peligro: true);
                        if (!ok || !context.mounted) return;
                        final hecho = await ejecutarSimple(
                            context, () => ref.read(comunicadosServiceProvider).eliminarCategoria(c.id),
                            exito: 'Categoría eliminada');
                        if (hecho) ref.invalidate(categoriasProvider);
                      },
                    ),
                  ]),
                ),
                const SizedBox(height: 12),
              ],
            ]),
    );
  }
}

// ------------------------------------------------------------------------------ diálogos
const _paleta = ['#1E40AF', '#3B82F6', '#16A34A', '#D97706', '#E4572E', '#7C3AED', '#0F766E', '#64748B'];

class CategoriaFormDialog extends StatefulWidget {
  const CategoriaFormDialog({super.key, this.existente});

  final CategoriaComunicado? existente;

  @override
  State<CategoriaFormDialog> createState() => _CategoriaFormDialogState();
}

class _CategoriaFormDialogState extends State<CategoriaFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _nombre;
  late final TextEditingController _descripcion;
  late String _color;
  late bool _activa;

  @override
  void initState() {
    super.initState();
    final c = widget.existente;
    _nombre = TextEditingController(text: c?.nombre ?? '');
    _descripcion = TextEditingController(text: c?.descripcion ?? '');
    _color = (c?.color != null && c!.color!.length == 7) ? c.color!.toUpperCase() : _paleta.first;
    _activa = c?.activa ?? true;
  }

  @override
  void dispose() {
    _nombre.dispose();
    _descripcion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.existente == null ? 'Nueva categoría' : 'Editar categoría'),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
                TextFormField(
                  controller: _nombre,
                  maxLength: 80,
                  decoration: const InputDecoration(labelText: 'Nombre', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un nombre' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _descripcion,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Descripción (opcional)', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 8),
                const Text('Color', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final hex in _paleta)
                    InkWell(
                      onTap: () => setState(() => _color = hex),
                      customBorder: const CircleBorder(),
                      child: CircleAvatar(
                        radius: 16,
                        backgroundColor: colorDesdeHex(hex, Colors.blue),
                        child: _color == hex ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                      ),
                    ),
                ]),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Activa'),
                  value: _activa,
                  onChanged: (v) => setState(() => _activa = v),
                ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (!_form.currentState!.validate()) return;
              Navigator.pop(context, <String, dynamic>{
                'nombre': _nombre.text.trim(),
                'descripcion': _descripcion.text.trim(),
                'color': _color,
                'activa': _activa,
              });
            },
            child: const Text('Guardar'),
          ),
        ],
      );
}

class ProgramarDialog extends StatefulWidget {
  const ProgramarDialog({super.key, this.actual});

  final DateTime? actual;

  @override
  State<ProgramarDialog> createState() => _ProgramarDialogState();
}

class _ProgramarDialogState extends State<ProgramarDialog> {
  DateTime? _fecha;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fecha = widget.actual;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Programar publicación'),
        content: SizedBox(
          width: 420,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('El comunicado se publicará solo en la fecha elegida y se notificará a su audiencia.'),
            const SizedBox(height: 14),
            SelectorFechaHora(etiqueta: 'Publicar el', valor: _fecha, onCambio: (d) => setState(() => _fecha = d)),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!, style: const TextStyle(color: colorAlerta, fontSize: 12.5)),
              ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              if (_fecha == null || !_fecha!.isAfter(DateTime.now())) {
                setState(() => _error = 'Elige una fecha y hora futuras.');
                return;
              }
              Navigator.pop(context, _fecha);
            },
            child: const Text('Programar'),
          ),
        ],
      );
}

class HistorialDialog extends ConsumerWidget {
  const HistorialDialog({super.key, required this.comunicado});

  final Comunicado comunicado;

  @override
  Widget build(BuildContext context, WidgetRef ref) => AlertDialog(
        title: Text('Historial: ${comunicado.titulo}'),
        content: SizedBox(
          width: 560,
          child: FutureBuilder<List<VersionComunicado>>(
            future: ref.read(comunicadosServiceProvider).historial(comunicado.id),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) return const CargandoCaja();
              if (snap.hasError) return ErrorCaja(mensaje: snap.error.toString());
              final versiones = snap.data ?? const [];
              if (versiones.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(16), child: Text('Este comunicado aún no tiene cambios registrados.'));
              }
              return SingleChildScrollView(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final v in versiones)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                          border: Border.all(color: Colors.black12), borderRadius: BorderRadius.circular(12)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                            '${v.fecha != null ? fechaHora(v.fecha!) : ''}  ·  ${v.usuarioNombre ?? 'Sistema'}'
                            '${v.estadoAnterior != null ? '  ·  estaba ${nombreEstado(v.estadoAnterior!)}' : ''}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54)),
                        const SizedBox(height: 6),
                        Text(v.tituloAnterior ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(v.contenidoAnterior ?? '', style: const TextStyle(color: Colors.black87)),
                      ]),
                    ),
                ]),
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
}

class ComunicadoFormDialog extends ConsumerStatefulWidget {
  const ComunicadoFormDialog({super.key, required this.categorias, this.existente});

  final List<CategoriaComunicado> categorias;
  final Comunicado? existente;

  @override
  ConsumerState<ComunicadoFormDialog> createState() => _ComunicadoFormDialogState();
}

class _ComunicadoFormDialogState extends ConsumerState<ComunicadoFormDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _titulo;
  late final TextEditingController _contenido;
  int _categoria = 0; // 0 = sin categoría
  String _audiencia = 'TODOS';
  int _rol = 0;
  DateTime? _expira;
  List<OpcionRol> _roles = const [];
  List<OpcionUsuario> _destinatarios = [];
  String? _error;

  bool get _edita => widget.existente != null;

  @override
  void initState() {
    super.initState();
    final c = widget.existente;
    _titulo = TextEditingController(text: c?.titulo ?? '');
    _contenido = TextEditingController(text: c?.contenido ?? '');
    _categoria = c?.categoriaId ?? 0;
    _audiencia = c?.audiencia ?? 'TODOS';
    _rol = c?.rolDestinoId ?? 0;
    _expira = c?.fechaExpiracion;
    Future.microtask(_cargarOpciones);
  }

  Future<void> _cargarOpciones() async {
    final servicio = ref.read(comunicadosServiceProvider);
    try {
      final roles = await servicio.roles();
      final c = widget.existente;
      final dest = c != null && c.destinatarios.isNotEmpty ? await servicio.usuariosPorIds(c.destinatarios) : <OpcionUsuario>[];
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _destinatarios = dest;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    }
  }

  @override
  void dispose() {
    _titulo.dispose();
    _contenido.dispose();
    super.dispose();
  }

  Future<void> _elegirDestinatarios() async {
    final r = await showDialog<List<OpcionUsuario>>(
        context: context, builder: (_) => SelectorDestinatariosDialog(seleccion: _destinatarios));
    if (r != null) setState(() => _destinatarios = r);
  }

  void _guardar() {
    final valido = _form.currentState!.validate();
    String? error;
    if (_audiencia == 'ROL' && _rol == 0) error = 'Selecciona el rol destinatario.';
    if (_audiencia == 'USUARIOS' && _destinatarios.isEmpty) error = 'Selecciona al menos un destinatario.';
    if (_expira != null && !_expira!.isAfter(DateTime.now())) error = 'La expiración debe ser futura.';
    setState(() => _error = error);
    if (!valido || error != null) return;
    Navigator.pop(context, <String, dynamic>{
      'titulo': _titulo.text.trim(),
      'contenido': _contenido.text.trim(),
      'categoria': _categoria == 0 ? null : _categoria,
      'audiencia': _audiencia,
      'rol_destino': _audiencia == 'ROL' ? _rol : null,
      if (_audiencia == 'USUARIOS') 'destinatarios': [for (final u in _destinatarios) u.id],
      'fecha_expiracion': _expira == null ? null : fechaParaApi(_expira!),
    });
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(_edita ? 'Editar comunicado' : 'Nuevo comunicado'),
        content: SizedBox(
          width: 580,
          child: SingleChildScrollView(
            child: Form(
              key: _form,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 4),
                TextFormField(
                  controller: _titulo,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: 'Título', border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe un título' : null,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _contenido,
                  maxLines: 6,
                  decoration: const InputDecoration(
                      labelText: 'Contenido', alignLabelWithHint: true, border: OutlineInputBorder()),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Escribe el contenido del aviso' : null,
                ),
                const SizedBox(height: 14),
                CampoSelector<int>(
                  etiqueta: 'Categoría',
                  valor: _categoria,
                  opciones: [
                    const OpcionSelector<int>(0, 'Sin categoría'),
                    for (final c in widget.categorias.where((c) => c.activa || c.id == _categoria))
                      OpcionSelector<int>(c.id, c.nombre),
                  ],
                  onCambio: (v) => setState(() => _categoria = v),
                ),
                const SizedBox(height: 14),
                CampoSelector<String>(
                  etiqueta: 'Dirigido a',
                  valor: _audiencia,
                  opciones: const [
                    OpcionSelector<String>('TODOS', 'Todos los residentes'),
                    OpcionSelector<String>('ROL', 'Un rol'),
                    OpcionSelector<String>('USUARIOS', 'Usuarios específicos'),
                  ],
                  onCambio: (v) => setState(() => _audiencia = v),
                ),
                if (_audiencia == 'ROL') ...[
                  const SizedBox(height: 14),
                  CampoSelector<int>(
                    etiqueta: 'Rol destinatario',
                    valor: _rol,
                    opciones: [
                      if (_rol == 0) const OpcionSelector<int>(0, 'Selecciona un rol'),
                      for (final r in _roles) OpcionSelector<int>(r.id, r.nombre),
                    ],
                    onCambio: (v) => setState(() => _rol = v),
                  ),
                ],
                if (_audiencia == 'USUARIOS') ...[
                  const SizedBox(height: 14),
                  OutlinedButton.icon(
                    onPressed: _elegirDestinatarios,
                    icon: const Icon(Icons.group_add_rounded),
                    label: Text(_destinatarios.isEmpty
                        ? 'Elegir destinatarios'
                        : '${_destinatarios.length} destinatario(s) · cambiar'),
                  ),
                  if (_destinatarios.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final u in _destinatarios) Chip(label: Text(u.nombre, style: const TextStyle(fontSize: 12))),
                      ]),
                    ),
                ],
                const SizedBox(height: 14),
                SelectorFechaHora(
                    etiqueta: 'Expira el (opcional)', valor: _expira, opcional: true, onCambio: (d) => setState(() => _expira = d)),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(_error!, style: const TextStyle(color: colorAlerta, fontSize: 12.5)),
                  ),
              ]),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _guardar, child: Text(_edita ? 'Guardar cambios' : 'Guardar borrador')),
        ],
      );
}

class SelectorDestinatariosDialog extends ConsumerStatefulWidget {
  const SelectorDestinatariosDialog({super.key, required this.seleccion});

  final List<OpcionUsuario> seleccion;

  @override
  ConsumerState<SelectorDestinatariosDialog> createState() => _SelectorDestinatariosDialogState();
}

class _SelectorDestinatariosDialogState extends ConsumerState<SelectorDestinatariosDialog> {
  final _buscar = TextEditingController();
  late final Map<int, OpcionUsuario> _elegidos = {for (final u in widget.seleccion) u.id: u};
  List<OpcionUsuario> _resultados = const [];
  bool _cargando = false;
  String? _error;
  Timer? _espera;

  @override
  void initState() {
    super.initState();
    _consultar('');
  }

  @override
  void dispose() {
    _espera?.cancel();
    _buscar.dispose();
    super.dispose();
  }

  Future<void> _consultar(String texto) async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final r = await ref.read(comunicadosServiceProvider).buscarUsuarios(texto.trim());
      if (mounted) setState(() => _resultados = r);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.mensaje);
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Elegir destinatarios'),
        content: SizedBox(
          width: 480,
          height: 420,
          child: Column(children: [
            TextField(
              controller: _buscar,
              decoration: const InputDecoration(
                  hintText: 'Buscar por nombre, usuario o correo', prefixIcon: Icon(Icons.search_rounded), border: OutlineInputBorder()),
              onChanged: (t) {
                _espera?.cancel();
                _espera = Timer(const Duration(milliseconds: 350), () => _consultar(t));
              },
            ),
            const SizedBox(height: 8),
            if (_cargando) const LinearProgressIndicator(),
            if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: colorAlerta))),
            Expanded(
              child: ListView(children: [
                for (final u in _resultados)
                  CheckboxListTile(
                    dense: true,
                    value: _elegidos.containsKey(u.id),
                    title: Text(u.nombre),
                    subtitle: Text('@${u.username}'),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _elegidos[u.id] = u;
                      } else {
                        _elegidos.remove(u.id);
                      }
                    }),
                  ),
              ]),
            ),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _elegidos.values.toList()),
              child: Text('Aceptar (${_elegidos.length})')),
        ],
      );
}
