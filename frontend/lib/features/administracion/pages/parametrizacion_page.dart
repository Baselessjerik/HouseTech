import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../services/modulo1_service.dart';

class ParametrizacionPage extends StatefulWidget {
  const ParametrizacionPage({super.key, this.service});

  final Modulo1Service? service;

  @override
  State<ParametrizacionPage> createState() => _ParametrizacionPageState();
}

class _ParametrizacionPageState extends State<ParametrizacionPage> {
  late final Modulo1Service _service = widget.service ?? Modulo1Service();

  List<Map<String, dynamic>> _copropiedades = const [];
  bool _cargando = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  Future<void> _cargar() async {
    setState(() {
      _cargando = true;
      _error = null;
    });
    try {
      final copropiedades = await _service.listarCopropiedades();
      if (!mounted) return;
      setState(() {
        _copropiedades = copropiedades;
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

  Future<void> _abrirFormCopropiedad({Map<String, dynamic>? actual}) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _CopropiedadFormDialog(
        service: _service,
        copropiedad: actual,
      ),
    );
    if (ok == true) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(actual == null
              ? 'Nuevo conjunto residencial registrado.'
              : 'Datos del conjunto residencial actualizados.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
      await _cargar();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cargando) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(40),
          child: CircularProgressIndicator(),
        ),
      );
    }
    if (_error != null) {
      return Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.redAccent),
              const SizedBox(width: 12),
              Expanded(child: Text(_error!)),
              TextButton(onPressed: _cargar, child: const Text('Reintentar')),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 16,
                  runSpacing: 12,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Parametrización de Conjuntos Residenciales',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Administra los datos institucionales (NIT, dirección, ciudad y contacto) de los conjuntos residenciales.',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: () => _abrirFormCopropiedad(),
                      icon: const Icon(Icons.domain_add_rounded),
                      label: const Text('Nuevo conjunto'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                if (_copropiedades.isEmpty)
                  const Text('No hay copropiedades registradas.')
                else
                  for (final c in _copropiedades)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            backgroundColor: AppColors.oceanBlue.withAlpha(25),
                            child: const Icon(Icons.apartment_rounded,
                                color: AppColors.oceanBlue),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c['nombre']?.toString() ?? '',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'NIT: ${c['nit'] ?? 'No registrado'} · '
                                  '${c['ciudad'] ?? 'Ciudad'} · '
                                  '${c['direccion'] ?? 'Sin dirección'} · '
                                  '${c['total_inmuebles'] ?? 0} inmuebles',
                                  style: const TextStyle(
                                      color: Colors.black54, fontSize: 13),
                                ),
                                if (c['email'] != null || c['telefono'] != null)
                                  Text(
                                    'Contacto: ${c['email'] ?? '-'} · Tel: ${c['telefono'] ?? '-'}',
                                    style: const TextStyle(
                                        color: Colors.black54, fontSize: 12),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Editar conjunto',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () =>
                                _abrirFormCopropiedad(actual: c),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CopropiedadFormDialog extends StatefulWidget {
  const _CopropiedadFormDialog({
    required this.service,
    this.copropiedad,
  });

  final Modulo1Service service;
  final Map<String, dynamic>? copropiedad;

  @override
  State<_CopropiedadFormDialog> createState() => _CopropiedadFormDialogState();
}

class _CopropiedadFormDialogState extends State<_CopropiedadFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombreCtrl;
  late final TextEditingController _nitCtrl;
  late final TextEditingController _dirCtrl;
  late final TextEditingController _ciudadCtrl;
  late final TextEditingController _telCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _descCtrl;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final c = widget.copropiedad;
    _nombreCtrl = TextEditingController(text: c?['nombre']?.toString() ?? '');
    _nitCtrl = TextEditingController(text: c?['nit']?.toString() ?? '');
    _dirCtrl = TextEditingController(text: c?['direccion']?.toString() ?? '');
    _ciudadCtrl = TextEditingController(
        text: c?['ciudad']?.toString() ?? 'San José de Cúcuta');
    _telCtrl = TextEditingController(text: c?['telefono']?.toString() ?? '');
    _emailCtrl = TextEditingController(text: c?['email']?.toString() ?? '');
    _descCtrl =
        TextEditingController(text: c?['descripcion']?.toString() ?? '');
  }

  @override
  void dispose() {
    _nombreCtrl.dispose();
    _nitCtrl.dispose();
    _dirCtrl.dispose();
    _ciudadCtrl.dispose();
    _telCtrl.dispose();
    _emailCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.guardarCopropiedad(
        id: widget.copropiedad?['id'] as int?,
        datos: {
          'nombre': _nombreCtrl.text.trim(),
          'nit': _nitCtrl.text.trim().isEmpty ? null : _nitCtrl.text.trim(),
          'direccion': _dirCtrl.text.trim(),
          'ciudad': _ciudadCtrl.text.trim(),
          'telefono': _telCtrl.text.trim(),
          'email': _emailCtrl.text.trim(),
          'descripcion': _descCtrl.text.trim(),
        },
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
      title: Text(widget.copropiedad == null
          ? 'Registrar nuevo conjunto residencial'
          : 'Editar conjunto residencial'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nombreCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nombre del conjunto / copropiedad',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? 'Requerido' : null,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nitCtrl,
                        decoration: const InputDecoration(
                          labelText: 'NIT',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _ciudadCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Ciudad',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _dirCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Dirección',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _telCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Correo electrónico',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Descripción / Observaciones',
                    border: OutlineInputBorder(),
                  ),
                ),
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

