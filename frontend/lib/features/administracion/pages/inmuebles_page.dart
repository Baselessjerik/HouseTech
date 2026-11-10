import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/user_model.dart';
import '../services/modulo1_service.dart';

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
  List<Map<String, dynamic>> _copropiedades = const [];
  bool _cargando = true;
  String? _error;
  String? _filtroTipo;

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

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _service.listarInmuebles(
          search: _searchCtrl.text,
          tipo: _filtroTipo,
          mios: !widget.modoAdmin,
        ),
        if (widget.modoAdmin && _copropiedades.isEmpty)
          _service.listarCopropiedades(),
      ]);
      if (!mounted) return;
      setState(() {
        _inmuebles = results[0];
        if (results.length > 1) {
          _copropiedades = results[1];
        }
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
    try {
      await _service.cambiarEstadoInmueble(id, activar: !activo);
      _snack(!activo ? 'Inmueble activado.' : 'Inmueble desactivado.');
      await _cargar();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  Future<void> _abrirVincular(Map<String, dynamic> inmueble) async {
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

  Future<void> _desvincular(int inmuebleId, int vinculoId) async {
    try {
      await _service.desvincularUsuarioInmueble(
        inmuebleId,
        vinculoId: vinculoId,
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
    if (tipo == 'CASA') {
      return torre.isNotEmpty ? 'Casa $numero · Manzana $torre' : 'Casa $numero';
    }
    if (tipo == 'LOCAL') {
      return 'Local $numero';
    }
    return torre.isNotEmpty
        ? 'Apartamento $numero · Torre $torre'
        : 'Apartamento $numero';
  }

  IconData _iconoPorTipo(String tipo) {
    switch (tipo.toUpperCase()) {
      case 'CASA':
        return Icons.home_work_outlined;
      case 'LOCAL':
        return Icons.storefront_outlined;
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
                            ? 'Registra casas o apartamentos y vincula residentes o propietarios.'
                            : 'Consulta las viviendas asociadas a tu cuenta.',
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
                    width: 300,
                    child: TextField(
                      controller: _searchCtrl,
                      onSubmitted: (_) => _cargar(),
                      decoration: InputDecoration(
                        hintText: 'Buscar por número o torre/manzana...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                          onPressed: _cargar,
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
                        items: const [
                          DropdownMenuItem(value: null, child: Text('Tipo: Todos')),
                          DropdownMenuItem(
                              value: 'APARTAMENTO', child: Text('Apartamentos')),
                          DropdownMenuItem(value: 'CASA', child: Text('Casas')),
                          DropdownMenuItem(value: 'LOCAL', child: Text('Locales')),
                        ],
                        onChanged: (v) {
                          setState(() => _filtroTipo = v);
                          _cargar();
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
                      : 'Aún no tienes inmuebles vinculados a tu cuenta.',
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          )
        else
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
      ],
    );
  }

  Widget _buildTarjetaInmueble(Map<String, dynamic> inm) {
    final id = inm['id'] as int;
    final activo = inm['activo'] == true;
    final tipo = (inm['tipo'] ?? 'APARTAMENTO').toString();
    final piso = inm['piso'];
    final copropiedad =
        (inm['copropiedad_nombre'] ?? 'Conjunto Residencial').toString();
    final vinculos =
        (inm['vinculos'] as List? ?? const []).whereType<Map<String, dynamic>>().toList();

    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
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
                      piso != null && tipo.toUpperCase() != 'CASA'
                          ? '$copropiedad · Piso $piso'
                          : copropiedad,
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
                            onTap: () => _desvincular(id, v['id'] as int),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 15,
                              color: Colors.redAccent,
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
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () => _abrirVincular(inm),
                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 17),
                  label: const Text('Vincular'),
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
    _tipo = i?['tipo']?.toString() ?? 'CASA';
    _copropiedadId = i?['copropiedad'] as int? ??
        (widget.copropiedades.isNotEmpty
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
      final datos = <String, dynamic>{
        'tipo': _tipo,
        'torre_bloque': _torreCtrl.text.trim().isEmpty
            ? null
            : _torreCtrl.text.trim(),
        'piso': _tipo == 'CASA'
            ? null
            : (_pisoCtrl.text.trim().isEmpty
                ? null
                : int.tryParse(_pisoCtrl.text.trim())),
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
                  items: const [
                    DropdownMenuItem(value: 'CASA', child: Text('Casa')),
                    DropdownMenuItem(
                        value: 'APARTAMENTO', child: Text('Apartamento')),
                    DropdownMenuItem(
                        value: 'LOCAL', child: Text('Local comercial')),
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
                              : 'Torre / Bloque',
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
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Piso',
                      prefixIcon: Icon(Icons.layers_outlined),
                    ),
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

  Future<void> _cargarUsuarios() async {
    try {
      final lista = await widget.service.listarUsuarios(activo: true);
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
        _error = e.toString();
        _guardando = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Vincular residente a ${widget.inmueble['numero']}',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 440,
        child: _cargando
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_error != null) ...[
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 10),
                  ],
                  DropdownButtonFormField<int>(
                    initialValue: _usuarioId,
                    decoration: const InputDecoration(
                      labelText: 'Seleccionar usuario',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    items: [
                      for (final u in _usuarios)
                        DropdownMenuItem(
                          value: u.id,
                          child: Text('${u.nombreCompleto} (@${u.username})'),
                        ),
                    ],
                    onChanged: (v) => setState(() => _usuarioId = v),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _relacion,
                    decoration: const InputDecoration(
                      labelText: 'Tipo de relación',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'PROPIETARIO', child: Text('Propietario')),
                      DropdownMenuItem(
                          value: 'ARRENDATARIO', child: Text('Arrendatario')),
                      DropdownMenuItem(
                          value: 'RESIDENTE', child: Text('Residente')),
                    ],
                    onChanged: (v) =>
                        setState(() => _relacion = v ?? 'RESIDENTE'),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: (_guardando || _cargando) ? null : _vincular,
          child: Text(_guardando ? 'Vinculando...' : 'Vincular'),
        ),
      ],
    );
  }
}
