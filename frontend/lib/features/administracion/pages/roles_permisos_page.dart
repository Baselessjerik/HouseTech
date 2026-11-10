import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../services/modulo1_service.dart';

class RolesPermisosPage extends StatefulWidget {
  const RolesPermisosPage({super.key, this.service});

  final Modulo1Service? service;

  @override
  State<RolesPermisosPage> createState() => _RolesPermisosPageState();
}

class _RolesPermisosPageState extends State<RolesPermisosPage> {
  late final Modulo1Service _service = widget.service ?? Modulo1Service();

  List<Map<String, dynamic>> _roles = const [];
  List<Map<String, dynamic>> _permisos = const [];
  int _rolIndex = 0;
  Set<String> _permisosSeleccionados = {};
  bool _cargando = true;
  bool _guardando = false;
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
      final res = await Future.wait([
        _service.listarRoles(),
        _service.listarPermisos(),
      ]);
      if (!mounted) return;
      final roles = res[0];
      final permisos = res[1];
      setState(() {
        _roles = roles;
        _permisos = permisos;
        if (_roles.isNotEmpty) {
          _rolIndex = _rolIndex.clamp(0, _roles.length - 1);
          _sincronizarSeleccion();
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

  void _sincronizarSeleccion() {
    if (_roles.isEmpty) return;
    final lista = _roles[_rolIndex]['permisos'] as List? ?? const [];
    _permisosSeleccionados = lista.map((e) => e.toString()).toSet();
  }

  Future<void> _guardarPermisos() async {
    if (_roles.isEmpty) return;
    final rol = _roles[_rolIndex];
    final rolId = rol['id'] as int;
    setState(() => _guardando = true);
    try {
      final actualizado = await _service.asignarPermisosRol(
        rolId,
        _permisosSeleccionados.toList(),
      );
      if (!mounted) return;
      setState(() {
        _roles[_rolIndex] = actualizado;
        _sincronizarSeleccion();
        _guardando = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Permisos del rol ${rol['nombre']} actualizados.'),
          backgroundColor: Colors.green.shade700,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _guardando = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red.shade700,
        ),
      );
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
    if (_roles.isEmpty) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(28),
          child: Text('No hay roles configurados.'),
        ),
      );
    }

    final rolActual = _roles[_rolIndex];
    final codigoRol = rolActual['codigo']?.toString() ?? '';
    final esAdmin = codigoRol == 'ADMIN';

    final porModulo = <String, List<Map<String, dynamic>>>{};
    for (final p in _permisos) {
      final mod = p['modulo']?.toString() ?? 'general';
      porModulo.putIfAbsent(mod, () => []).add(p);
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
                const Text(
                  'Roles y Permisos del Sistema (RBAC)',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Selecciona un rol para consultar o personalizar los permisos efectivos que otorga en cada módulo.',
                  style: TextStyle(color: Colors.black54, fontSize: 13),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < _roles.length; i++)
                      ChoiceChip(
                        selected: i == _rolIndex,
                        label: Text(
                          '${_roles[i]['nombre']} (${_roles[i]['codigo']})',
                          style: TextStyle(
                            fontWeight: i == _rolIndex
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        onSelected: (_) {
                          setState(() {
                            _rolIndex = i;
                            _sincronizarSeleccion();
                          });
                        },
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${rolActual['nombre']} (${rolActual['codigo']})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          if (rolActual['descripcion'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                rolActual['descripcion'].toString(),
                                style: const TextStyle(
                                    color: Colors.black54, fontSize: 13),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (!esAdmin)
                      FilledButton.icon(
                        onPressed: _guardando ? null : _guardarPermisos,
                        icon: _guardando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save_outlined),
                        label: const Text('Guardar permisos'),
                      ),
                  ],
                ),
                if (esAdmin) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.oceanBlue.withAlpha(20),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.shield_outlined,
                            color: AppColors.oceanBlue, size: 20),
                        SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'El rol ADMIN conserva todos los permisos del sistema por seguridad y no puede restringirse.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const Divider(height: 32),
                for (final entry in porModulo.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 8),
                    child: Text(
                      'MÓDULO: ${entry.key.toUpperCase()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppColors.oceanBlue,
                      ),
                    ),
                  ),
                  for (final perm in entry.value)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _permisosSeleccionados
                          .contains(perm['codigo']?.toString()),
                      title: Text(
                        perm['codigo']?.toString() ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(perm['descripcion']?.toString() ?? ''),
                      onChanged: esAdmin
                          ? null
                          : (val) {
                              final code = perm['codigo']?.toString() ?? '';
                              setState(() {
                                if (val == true) {
                                  _permisosSeleccionados.add(code);
                                } else {
                                  _permisosSeleccionados.remove(code);
                                }
                              });
                            },
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

