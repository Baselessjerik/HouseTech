import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/app_colors.dart';
import '../../../models/user_model.dart';
import '../services/modulo1_service.dart';

const List<String> _kTiposInmueble = [
  'APARTAMENTO',
  'CASA',
  'LOCAL',
  'PARQUEADERO',
  'OTRO',
];

String _etiquetaTipo(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'CASA':
      return 'Casa';
    case 'LOCAL':
      return 'Local comercial';
    case 'PARQUEADERO':
      return 'Parqueadero';
    case 'OTRO':
      return 'Otro';
    default:
      return 'Apartamento';
  }
}

class InmueblesPage extends StatefulWidget {
  const InmueblesPage({
    super.key,
    required this.modoAdmin,
    this.service,
  });

  final bool modoAdmin;
  final Modulo1Service? service;

  @override
  State<InmueblesPage> createState() => _InmueblesPageState();
}

class _InmueblesPageState extends State<InmueblesPage> {
  late final Modulo1Service _service = widget.service ?? Modulo1Service();
  final _searchCtrl = TextEditingController();

  List<Map<String, dynamic>> _inmuebles = const [];
  int _totalInmuebles = 0;
  int _pagina = 1;
  bool _tieneSiguiente = false;
  bool _tieneAnterior = false;
  List<Map<String, dynamic>> _copropiedades = const [];
  bool _cargando = true;
  String? _error;
  String? _filtroTipo;
  bool? _filtroActivo;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _cargar({bool reiniciarPagina = false}) async {
    if (reiniciarPagina) _pagina = 1;
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.listarInmueblesPaginado(
          search: _searchCtrl.text,
          tipo: _filtroTipo,
          activo: widget.modoAdmin ? _filtroActivo : null,
          mios: !widget.modoAdmin,
          page: _pagina,
        ),
        if (widget.modoAdmin) _service.listarCopropiedades(),
      ]);
      if (!mounted) return;
      final pag = results[0] as PaginaResultado<Map<String, dynamic>>;
      setState(() {
        _inmuebles = pag.items;
        _totalInmuebles = pag.total;
        _tieneSiguiente = pag.tieneSiguiente;
        _tieneAnterior = pag.tieneAnterior;
        if (results.length > 1) {
          _copropiedades = results[1] as List<Map<String, dynamic>>;
        }
        _cargando = false;
      });
    } catch (e) {
      if (!mounted) return;
      if (_pagina > 1 && !reiniciarPagina) {
        _pagina = 1;
        await _cargar(reiniciarPagina: true);
        return;
      }
      setState(() {
        _error = e.toString();
        _cargando = false;
      });
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  Future<void> _abrirFormulario({Map<String, dynamic>? inmueble}) async {
    final guardado = await showDialog<bool>(
      context: context,
      builder: (_) => _InmuebleFormDialog(
        service: _service,
        inmueble: inmueble,
        copropiedades: _copropiedades,
      ),
    );
    if (guardado == true) {
      _snack(inmueble == null
          ? 'Inmueble registrado correctamente.'
          : 'Inmueble actualizado correctamente.');
      await _cargar();
    }
  }

  Future<void> _cambiarEstado(Map<String, dynamic> inmueble) async {
    final id = inmueble['id'] as int;
    final activo = inmueble['activo'] == true;
    final vinculos = (inmueble['vinculos'] as List? ?? const []);

    if (activo) {
      final avisoVinculos = vinculos.isNotEmpty
          ? '\n\nEste inmueble tiene ${vinculos.length} residente(s) vinculado(s). Su historial se conservará intacto, pero dejará de aparecer como activo.'
          : '\n\nSu historial se conservará intacto y podrás reactivarlo cuando lo necesites.';
      final confirmar = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Desactivar inmueble'),
          content: Text(
            '¿Seguro que deseas desactivar "${_tituloInmueble(inmueble)}"?$avisoVinculos',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Desactivar'),
            ),
          ],
        ),
      );
      if (confirmar != true) return;
    }

    try {
      await _service.cambiarEstadoInmueble(id, activar: !activo);
      _snack(!activo ? 'Inmueble activado.' : 'Inmueble desactivado.');
      await _cargar();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _abrirVincular(Map<String, dynamic> inmueble) async {
    if (inmueble['activo'] != true) {
      _snack('Activa el inmueble antes de vincular nuevos residentes.',
          error: true);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _VincularResidenteDialog(
        service: _service,
        inmueble: inmueble,
      ),
    );
    if (ok == true) {
      _snack('Residente vinculado al inmueble.');
      await _cargar();
    }
  }

  Future<void> _desvincular(
    int inmuebleId,
    Map<String, dynamic> vinculo,
  ) async {
    final nombre = vinculo['usuario_nombre']?.toString() ?? 'este usuario';
    final relacion = vinculo['tipo_relacion']?.toString() ?? '';
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Finalizar vínculo'),
        content: Text(
          '¿Deseas finalizar el vínculo de $nombre ($relacion)? '
          'No se borrará el registro: quedará guardado con fecha de finalización para trazabilidad.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finalizar vínculo'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      await _service.desvincularUsuarioInmueble(
        inmuebleId,
        vinculoId: vinculo['id'] as int,
      );
      _snack('Vínculo finalizado.');
      await _cargar();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  String _tituloInmueble(Map<String, dynamic> inm) {
    final tipo = (inm['tipo'] ?? 'APARTAMENTO').toString().toUpperCase();
    final numero = (inm['numero'] ?? '').toString();
    final torre = (inm['torre_bloque'] ?? '').toString().trim();
    switch (tipo) {
      case 'CASA':
        return torre.isNotEmpty
            ? 'Casa $numero · Manzana $torre'
            : 'Casa $numero';
      case 'LOCAL':
        return torre.isNotEmpty
            ? 'Local $numero · $torre'
            : 'Local $numero';
      case 'PARQUEADERO':
        return torre.isNotEmpty
            ? 'Parqueadero $numero · $torre'
            : 'Parqueadero $numero';
      case 'OTRO':
        return torre.isNotEmpty
            ? 'Unidad $numero · $torre'
            : 'Unidad $numero';
      default:
        return torre.isNotEmpty
            ? 'Apartamento $numero · Torre $torre'
            : 'Apartamento $numero';
    }
  }

  IconData _iconoPorTipo(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'CASA':
        return Icons.home_work_outlined;
      case 'LOCAL':
        return Icons.storefront_outlined;
      case 'PARQUEADERO':
        return Icons.local_parking_rounded;
      case 'OTRO':
        return Icons.meeting_room_outlined;
      default:
        return Icons.apartment_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Cabecera blanca de ancho completo
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 12,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.modoAdmin
                            ? 'Administración de Inmuebles'
                            : 'Mis Unidades Residenciales',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.modoAdmin
                            ? 'Registra unidades, gestiona su estado (sin borrado físico) y vincula titulares.'
                            : 'Consulta las viviendas activas asociadas a tu cuenta.',
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                  if (widget.modoAdmin)
                    FilledButton.icon(
                      onPressed: () => _abrirFormulario(),
                      icon: const Icon(Icons.add_home_work_rounded, size: 18),
                      label: const Text('Nuevo inmueble'),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => setState(() {}),
                      onSubmitted: (_) => _cargar(reiniciarPagina: true),
                      decoration: InputDecoration(
                        hintText: 'Buscar por código, número o torre...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_searchCtrl.text.isNotEmpty)
                              IconButton(
                                tooltip: 'Limpiar',
                                icon: const Icon(Icons.clear_rounded, size: 18),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  _cargar(reiniciarPagina: true);
                                },
                              ),
                            IconButton(
                              tooltip: 'Buscar',
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 18),
                              onPressed: () => _cargar(reiniciarPagina: true),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFCBD5E1)),
                      ),
                      child: DropdownButton<String?>(
                        value: _filtroTipo,
                        hint: const Text('Tipo: Todos'),
                        items: [
                          const DropdownMenuItem(
                              value: null, child: Text('Tipo: Todos')),
                          for (final t in _kTiposInmueble)
                            DropdownMenuItem(
                              value: t,
                              child: Text(_etiquetaTipo(t)),
                            ),
                        ],
                        onChanged: (v) {
                          setState(() => _filtroTipo = v);
                          _cargar(reiniciarPagina: true);
                        },
                      ),
                    ),
                  ),
                  if (widget.modoAdmin)
                    DropdownButtonHideUnderline(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFCBD5E1)),
                        ),
                        child: DropdownButton<bool?>(
                          value: _filtroActivo,
                          hint: const Text('Estado: Todos'),
                          items: const [
                            DropdownMenuItem(
                                value: null, child: Text('Estado: Todos')),
                            DropdownMenuItem(
                                value: true, child: Text('Solo activos')),
                            DropdownMenuItem(
                                value: false, child: Text('Solo inactivos')),
                          ],
                          onChanged: (v) {
                            setState(() => _filtroActivo = v);
                            _cargar(reiniciarPagina: true);
                          },
                        ),
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: _cargar,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Actualizar'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // Contenido en grilla de 2 columnas
        if (_cargando)
          const Padding(
            padding: EdgeInsets.all(48),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_error != null)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent),
                const SizedBox(width: 12),
                Expanded(child: Text(_error!)),
                TextButton(onPressed: _cargar, child: const Text('Reintentar')),
              ],
            ),
          )
        else if (_inmuebles.isEmpty)
          Container(
            padding: const EdgeInsets.all(48),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              children: [
                Icon(Icons.home_work_outlined,
                    size: 48, color: AppColors.oceanBlue.withAlpha(110)),
                const SizedBox(height: 12),
                Text(
                  widget.modoAdmin
                      ? 'No se encontraron inmuebles registrados.'
                      : 'Aún no tienes inmuebles activos vinculados a tu cuenta.',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          )
        else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final dosColumnas = constraints.maxWidth >= 720;
              final anchoTarjeta = dosColumnas
                  ? (constraints.maxWidth - 20) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 20,
                runSpacing: 20,
                children: [
                  for (final inm in _inmuebles)
                    SizedBox(
                      width: anchoTarjeta,
                      child: _buildTarjetaInmueble(inm),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mostrando ${_inmuebles.length} de $_totalInmuebles inmuebles · Página $_pagina',
                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
              ),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _tieneAnterior
                        ? () {
                            setState(() => _pagina--);
                            _cargar();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_left_rounded, size: 18),
                    label: const Text('Anterior'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: _tieneSiguiente
                        ? () {
                            setState(() => _pagina++);
                            _cargar();
                          }
                        : null,
                    icon: const Icon(Icons.chevron_right_rounded, size: 18),
                    label: const Text('Siguiente'),
                  ),
                ],
              ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildTarjetaInmueble(Map<String, dynamic> inm) {
    final id = inm['id'] as int;
    final activo = inm['activo'] == true;
    final tipo = (inm['tipo'] ?? 'APARTAMENTO').toString();
    final piso = inm['piso'];
    final codigo = (inm['codigo_interno'] ?? '').toString();
    final copropiedad =
        (inm['copropiedad_nombre'] ?? 'Conjunto Residencial').toString();
    final vinculos = (inm['vinculos'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: activo ? const Color(0xFFE2E8F0) : const Color(0xFFFECACA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.oceanBlue.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _iconoPorTipo(tipo),
                  color: AppColors.oceanBlue,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _tituloInmueble(inm),
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        copropiedad,
                        if (piso != null && tipo.toUpperCase() != 'CASA')
                          'Piso $piso',
                        if (codigo.isNotEmpty) codigo,
                      ].join(' · '),
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: activo
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  activo ? 'Activo' : 'Inactivo',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: activo
                        ? const Color(0xFF15803D)
                        : const Color(0xFFB91C1C),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: Color(0xFFF1F5F9)),
          const SizedBox(height: 14),
          const Text(
            'Residentes / Titulares vinculados',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 8),
          if (vinculos.isEmpty)
            const Text(
              'Sin residentes vinculados actualmente.',
              style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final v in vinculos)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.person_outline_rounded,
                            size: 15, color: AppColors.oceanBlue),
                        const SizedBox(width: 6),
                        Text(
                          '${v['usuario_nombre']} (${v['tipo_relacion']})',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textDark,
                          ),
                        ),
                        if (widget.modoAdmin) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _desvincular(id, v),
                            child: const Tooltip(
                              message: 'Finalizar vínculo',
                              child: Icon(
                                Icons.close_rounded,
                                size: 15,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          if (widget.modoAdmin) ...[
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                Tooltip(
                  message: activo
                      ? 'Vincular usuario'
                      : 'Activa el inmueble para vincular usuarios',
                  child: TextButton.icon(
                    onPressed: activo ? () => _abrirVincular(inm) : null,
                    icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                    label: const Text('Vincular'),
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _abrirFormulario(inmueble: inm),
                  icon: const Icon(Icons.edit_outlined, size: 17),
                  label: const Text('Editar'),
                ),
                TextButton.icon(
                  onPressed: () => _cambiarEstado(inm),
                  icon: Icon(
                    activo
                        ? Icons.toggle_off_outlined
                        : Icons.toggle_on_outlined,
                    size: 18,
                    color: activo ? Colors.redAccent : Colors.green,
                  ),
                  label: Text(
                    activo ? 'Desactivar' : 'Activar',
                    style: TextStyle(
                        color: activo ? Colors.redAccent : Colors.green),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _InmuebleFormDialog extends StatefulWidget {
  const _InmuebleFormDialog({
    required this.service,
    required this.copropiedades,
    this.inmueble,
  });

  final Modulo1Service service;
  final List<Map<String, dynamic>> copropiedades;
  final Map<String, dynamic>? inmueble;

  @override
  State<_InmuebleFormDialog> createState() => _InmuebleFormDialogState();
}

class _InmuebleFormDialogState extends State<_InmuebleFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late String _tipo;
  int? _copropiedadId;
  late final TextEditingController _torreCtrl;
  late final TextEditingController _pisoCtrl;
  late final TextEditingController _numeroCtrl;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final i = widget.inmueble;
    final rawTipo = i?['tipo']?.toString().toUpperCase() ?? 'CASA';
    _tipo = _kTiposInmueble.contains(rawTipo) ? rawTipo : 'OTRO';
    final idsDisponibles =
        widget.copropiedades.map((c) => c['id'] as int).toSet();
    final rawCopropId = i?['copropiedad'] as int?;
    _copropiedadId = (rawCopropId != null && idsDisponibles.contains(rawCopropId))
        ? rawCopropId
        : (widget.copropiedades.isNotEmpty
            ? widget.copropiedades.first['id'] as int?
            : null);
    _torreCtrl =
        TextEditingController(text: i?['torre_bloque']?.toString() ?? '');
    _pisoCtrl = TextEditingController(text: i?['piso']?.toString() ?? '');
    _numeroCtrl = TextEditingController(text: i?['numero']?.toString() ?? '');
  }

  @override
  void dispose() {
    _torreCtrl.dispose();
    _pisoCtrl.dispose();
    _numeroCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final pisoTxt = _pisoCtrl.text.trim();
      final datos = <String, dynamic>{
        'tipo': _tipo,
        'torre_bloque': _torreCtrl.text.trim().isEmpty
            ? null
            : _torreCtrl.text.trim(),
        'piso': _tipo == 'CASA'
            ? null
            : (pisoTxt.isEmpty ? null : int.parse(pisoTxt)),
        'numero': _numeroCtrl.text.trim(),
        if (_copropiedadId != null) 'copropiedad': _copropiedadId,
      };
      if (widget.inmueble == null) {
        await widget.service.crearInmueble(datos);
      } else {
        await widget.service.actualizarInmueble(
          widget.inmueble!['id'] as int,
          datos,
        );
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final esCasa = _tipo == 'CASA';

    return AlertDialog(
      title: Text(
        widget.inmueble == null ? 'Registrar inmueble' : 'Editar inmueble',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 460,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Colors.red.shade800, fontSize: 12),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                if (widget.copropiedades.isNotEmpty) ...[
                  DropdownButtonFormField<int>(
                    initialValue: _copropiedadId,
                    decoration: const InputDecoration(
                      labelText: 'Conjunto Residencial',
                      prefixIcon: Icon(Icons.domain_rounded),
                    ),
                    items: [
                      for (final c in widget.copropiedades)
                        DropdownMenuItem(
                          value: c['id'] as int,
                          child: Text(c['nombre']?.toString() ?? ''),
                        ),
                    ],
                    onChanged: (v) => setState(() => _copropiedadId = v),
                  ),
                  const SizedBox(height: 14),
                ],
                DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  decoration: const InputDecoration(
                    labelText: 'Tipo de inmueble',
                    prefixIcon: Icon(Icons.home_work_outlined),
                  ),
                  items: [
                    for (final t in _kTiposInmueble)
                      DropdownMenuItem(
                        value: t,
                        child: Text(_etiquetaTipo(t)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _tipo = v ?? 'CASA'),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _torreCtrl,
                        decoration: InputDecoration(
                          labelText: esCasa
                              ? 'Manzana / Sector (opcional)'
                              : 'Torre / Bloque / Zona',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _numeroCtrl,
                        decoration: InputDecoration(
                          labelText:
                              esCasa ? 'Número de casa' : 'Número (ej. 101)',
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                  ],
                ),
                if (!esCasa) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _pisoCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      signed: true,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^-?\d*')),
                    ],
                    decoration: const InputDecoration(
                      labelText: 'Piso (opcional, ej. 1 o -1 para sótano)',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
                    validator: (v) {
                      final txt = v?.trim() ?? '';
                      if (txt.isEmpty) return null;
                      final num = int.tryParse(txt);
                      if (num == null) return 'Ingresa un número entero válido';
                      if (num < -5 || num > 200) {
                        return 'El piso debe estar entre -5 y 200';
                      }
                      return null;
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}

class _VincularResidenteDialog extends StatefulWidget {
  const _VincularResidenteDialog({
    required this.service,
    required this.inmueble,
  });

  final Modulo1Service service;
  final Map<String, dynamic> inmueble;

  @override
  State<_VincularResidenteDialog> createState() =>
      _VincularResidenteDialogState();
}

class _VincularResidenteDialogState extends State<_VincularResidenteDialog> {
  final _busquedaCtrl = TextEditingController();
  List<UserModel> _usuarios = const [];
  int? _usuarioId;
  String _relacion = 'RESIDENTE';
  bool _cargando = true;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargarUsuarios();
  }

  @override
  void dispose() {
    _busquedaCtrl.dispose();
    super.dispose();
  }

  List<UserModel> get _usuariosFiltrados {
    final q = _busquedaCtrl.text.trim().toLowerCase();
    if (q.isEmpty) return _usuarios;
    return _usuarios
        .where((u) =>
            u.nombreCompleto.toLowerCase().contains(q) ||
            u.username.toLowerCase().contains(q) ||
            u.numeroDocumento.toLowerCase().contains(q))
        .toList();
  }

  Future<void> _cargarUsuarios() async {
    try {
      final lista = await widget.service.listarUsuarios(
        activo: true,
        todasLasPaginas: true,
      );
      if (!mounted) return;
      setState(() {
        _usuarios = lista;
        if (lista.isNotEmpty) _usuarioId = lista.first.id;
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

  Future<void> _vincular() async {
    if (_usuarioId == null) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.vincularUsuarioInmueble(
        widget.inmueble['id'] as int,
        usuarioId: _usuarioId!,
        tipoRelacion: _relacion,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtrados = _usuariosFiltrados;
    final seleccionadoValido =
        filtrados.any((u) => u.id == _usuarioId) ? _usuarioId : (filtrados.isNotEmpty ? filtrados.first.id : null);
    if (seleccionadoValido != _usuarioId && !_cargando) {
      _usuarioId = seleccionadoValido;
    }

    return AlertDialog(
      title: Text(
        'Vincular residente a ${widget.inmueble['numero']}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 460,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Colors.red.shade800, fontSize: 12),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _busquedaCtrl,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText:
                            'Filtrar usuario por nombre, usuario o cédula',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      key: ValueKey('dd-${filtrados.length}-$seleccionadoValido'),
                      isExpanded: true,
                      initialValue: seleccionadoValido,
                      decoration: const InputDecoration(
                        labelText: 'Seleccionar usuario',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      items: [
                        for (final u in filtrados)
                          DropdownMenuItem(
                            value: u.id,
                            child: Text(
                              '${u.nombreCompleto} (@${u.username})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setState(() => _usuarioId = v),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: _relacion,
                      decoration: const InputDecoration(
                        labelText: 'Tipo de relación',
                        prefixIcon: Icon(Icons.badge_outlined),
                      ),
                      items: const [
                        DropdownMenuItem(
                            value: 'PROPIETARIO', child: Text('Propietario')),
                        DropdownMenuItem(
                            value: 'ARRENDATARIO',
                            child: Text('Arrendatario')),
                        DropdownMenuItem(
                            value: 'RESIDENTE', child: Text('Residente')),
                      ],
                      onChanged: (v) =>
                          setState(() => _relacion = v ?? 'RESIDENTE'),
                    ),
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed:
              (_guardando || _cargando || seleccionadoValido == null)
                  ? null
                  : _vincular,
          child: Text(_guardando ? 'Vinculando...' : 'Vincular'),
        ),
      ],
    );
  }
}
