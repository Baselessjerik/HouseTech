import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../models/user_model.dart';
import '../services/modulo1_service.dart';
import 'mi_perfil_page.dart';

class UsuariosAdminPage extends StatefulWidget {
  const UsuariosAdminPage({
    super.key,
    required this.currentUser,
    this.service,
  });

  final UserModel currentUser;
  final Modulo1Service? service;

  @override
  State<UsuariosAdminPage> createState() => _UsuariosAdminPageState();
}

class _UsuariosAdminPageState extends State<UsuariosAdminPage> {
  late final Modulo1Service _service = widget.service ?? Modulo1Service();
  final _searchCtrl = TextEditingController();

  List<UserModel> _usuarios = const [];
  List<Map<String, dynamic>> _rolesCatalogo = const [];
  bool _cargando = true;
  String? _error;
  bool? _filtroActivo;
  String? _filtroRol;

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
        _service.listarUsuarios(
          search: _searchCtrl.text,
          activo: _filtroActivo,
          rol: _filtroRol,
        ),
        if (_rolesCatalogo.isEmpty &&
            widget.currentUser.tienePermiso('roles.gestionar'))
          _service.listarRoles(),
      ]);
      if (!mounted) return;
      setState(() {
        _usuarios = results[0] as List<UserModel>;
        if (results.length > 1) {
          _rolesCatalogo = results[1] as List<Map<String, dynamic>>;
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

  Future<void> _abrirModalCrear() async {
    final creado = await showDialog<bool>(
      context: context,
      builder: (_) => _CrearUsuarioDialog(
        service: _service,
        rolesDisponibles: _codigosRolesDisponibles(),
      ),
    );
    if (creado == true) {
      _snack('Usuario creado exitosamente.');
      await _cargar();
    }
  }

  Future<void> _abrirModalEditar(UserModel u) async {
    final editado = await showDialog<bool>(
      context: context,
      builder: (_) => _EditarUsuarioDialog(service: _service, usuario: u),
    );
    if (editado == true) {
      _snack('Datos del usuario actualizados.');
      await _cargar();
    }
  }

  Future<void> _abrirModalRoles(UserModel u) async {
    final actualizado = await showDialog<bool>(
      context: context,
      builder: (_) => _AsignarRolesDialog(
        service: _service,
        usuario: u,
        rolesDisponibles: _codigosRolesDisponibles(),
      ),
    );
    if (actualizado == true) {
      _snack('Roles actualizados correctamente.');
      await _cargar();
    }
  }

  Future<void> _alternarEstado(UserModel u) async {
    final activar = !u.activo;
    try {
      await _service.cambiarEstadoUsuario(u.id, activar: activar);
      _snack(activar
          ? 'Usuario ${u.username} activado.'
          : 'Usuario ${u.username} desactivado.');
      await _cargar();
    } catch (e) {
      _snack(e.toString(), error: true);
    }
  }

  List<String> _codigosRolesDisponibles() {
    if (_rolesCatalogo.isNotEmpty) {
      return _rolesCatalogo
          .map((r) => r['codigo']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toList();
    }
    return const ['ADMIN', 'RESIDENTE', 'RESPONSABLE_PQR'];
  }

  @override
  Widget build(BuildContext context) {
    final puedeRoles = widget.currentUser.tienePermiso('roles.gestionar');

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
                          'Administración de Usuarios',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Gestiona cuentas de residentes, personal de PQR y administradores.',
                          style: TextStyle(color: Colors.black54, fontSize: 13),
                        ),
                      ],
                    ),
                    FilledButton.icon(
                      onPressed: _abrirModalCrear,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('Nuevo usuario'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        controller: _searchCtrl,
                        onSubmitted: (_) => _cargar(),
                        decoration: InputDecoration(
                          hintText: 'Buscar por nombre, usuario, doc o correo...',
                          prefixIcon: const Icon(Icons.search),
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    _cargar();
                                  },
                                )
                              : null,
                        ),
                      ),
                    ),
                    DropdownButton<bool?>(
                      value: _filtroActivo,
                      hint: const Text('Estado: Todos'),
                      onChanged: (v) {
                        setState(() => _filtroActivo = v);
                        _cargar();
                      },
                      items: const [
                        DropdownMenuItem(
                            value: null, child: Text('Estado: Todos')),
                        DropdownMenuItem(
                            value: true, child: Text('Solo activos')),
                        DropdownMenuItem(
                            value: false, child: Text('Solo inactivos')),
                      ],
                    ),
                    DropdownButton<String?>(
                      value: _filtroRol,
                      hint: const Text('Rol: Todos'),
                      onChanged: (v) {
                        setState(() => _filtroRol = v);
                        _cargar();
                      },
                      items: [
                        const DropdownMenuItem(
                            value: null, child: Text('Rol: Todos')),
                        for (final r in _codigosRolesDisponibles())
                          DropdownMenuItem(
                              value: r, child: Text(UserModel.nombreRol(r))),
                      ],
                    ),
                    OutlinedButton.icon(
                      onPressed: _cargar,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Actualizar'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (_cargando)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card(
            elevation: 0,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_error!)),
                  TextButton(
                      onPressed: _cargar, child: const Text('Reintentar')),
                ],
              ),
            ),
          )
        else if (_usuarios.isEmpty)
          const Card(
            elevation: 0,
            child: Padding(
              padding: EdgeInsets.all(36),
              child: Center(
                child: Text(
                    'No se encontraron usuarios con los filtros seleccionados.'),
              ),
            ),
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              final dosColumnas = constraints.maxWidth >= 760;
              final anchoCol = dosColumnas
                  ? (constraints.maxWidth - 20) / 2
                  : constraints.maxWidth;

              return Wrap(
                spacing: 20,
                runSpacing: 16,
                children: [
                  for (final u in _usuarios)
                    SizedBox(
                      width: anchoCol,
                      child: Card(
                        elevation: 0,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  UserAvatarWidget(
                                      user: u, radius: 24, fontSize: 15),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          u.nombreCompleto,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                            fontSize: 16,
                                            color: AppColors.textDark,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '@${u.username} · ${u.tipoDocumento} ${u.numeroDocumento}',
                                          style: const TextStyle(
                                            fontSize: 12,
                                            color: Color(0xFF64748B),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: u.activo
                                          ? const Color(0xFFDCFCE7)
                                          : const Color(0xFFFEE2E2),
                                      borderRadius: BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      u.activo ? 'Activo' : 'Inactivo',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: u.activo
                                            ? const Color(0xFF15803D)
                                            : const Color(0xFFB91C1C),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final r in u.roles)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 9, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: AppColors.oceanBlue.withAlpha(20),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        UserModel.nombreRol(r),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.oceanBlue,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${u.email}${u.telefono != null && u.telefono!.isNotEmpty ? " · Tel: ${u.telefono}" : ""}',
                                style: const TextStyle(
                                    fontSize: 13, color: Color(0xFF475569)),
                              ),
                              const SizedBox(height: 12),
                              const Divider(
                                  height: 1, color: Color(0xFFF1F5F9)),
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton.icon(
                                    onPressed: () => _abrirModalEditar(u),
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 16),
                                    label: const Text('Editar'),
                                  ),
                                  if (puedeRoles)
                                    TextButton.icon(
                                      onPressed: () => _abrirModalRoles(u),
                                      icon: const Icon(
                                        Icons.admin_panel_settings_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('Roles'),
                                    ),
                                  if (u.id != widget.currentUser.id)
                                    TextButton.icon(
                                      onPressed: () => _alternarEstado(u),
                                      icon: Icon(
                                        u.activo
                                            ? Icons.person_off_outlined
                                            : Icons.how_to_reg_outlined,
                                        size: 16,
                                        color: u.activo
                                            ? Colors.redAccent
                                            : Colors.green.shade700,
                                      ),
                                      label: Text(
                                        u.activo ? 'Desactivar' : 'Activar',
                                        style: TextStyle(
                                          color: u.activo
                                              ? Colors.redAccent
                                              : Colors.green.shade700,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
      ],
    );
  }
}

class _CrearUsuarioDialog extends StatefulWidget {
  const _CrearUsuarioDialog({
    required this.service,
    required this.rolesDisponibles,
  });

  final Modulo1Service service;
  final List<String> rolesDisponibles;

  @override
  State<_CrearUsuarioDialog> createState() => _CrearUsuarioDialogState();
}

class _CrearUsuarioDialogState extends State<_CrearUsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  String _tipoDoc = 'CC';
  final _numDocCtrl = TextEditingController();
  final _nombresCtrl = TextEditingController();
  final _apellidosCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _telefonoCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  final Set<String> _rolesSeleccionados = {'RESIDENTE'};
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _numDocCtrl.dispose();
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    if (_rolesSeleccionados.isEmpty) {
      setState(() => _error = 'Selecciona al menos un rol.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.crearUsuario({
        'tipo_documento': _tipoDoc,
        'numero_documento': _numDocCtrl.text.trim(),
        'nombres': _nombresCtrl.text.trim(),
        'apellidos': _apellidosCtrl.text.trim(),
        'username': _usernameCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
        'password': _passCtrl.text,
        'roles': _rolesSeleccionados.toList(),
      });
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
      title: const Text('Crear nuevo usuario'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Text(_error!,
                      style: const TextStyle(color: Colors.redAccent)),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: DropdownButtonFormField<String>(
                        initialValue: _tipoDoc,
                        decoration: const InputDecoration(
                          labelText: 'Tipo Doc.',
                          border: OutlineInputBorder(),
                        ),
                        items: const ['CC', 'CE', 'TI', 'PP', 'NIT']
                            .map((t) =>
                                DropdownMenuItem(value: t, child: Text(t)))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _tipoDoc = v ?? 'CC'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _numDocCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Número de documento',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nombresCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nombres',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _apellidosCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Apellidos',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? 'Requerido'
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _usernameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Usuario (username)',
                          border: OutlineInputBorder(),
                        ),
                        validator: (v) => (v == null || v.trim().length < 3)
                            ? 'Mínimo 3 caracteres'
                            : null,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: _telefonoCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Teléfono',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || !v.contains('@'))
                      ? 'Correo inválido'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Contraseña inicial (mín. 8 caracteres)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.length < 8)
                      ? 'Mínimo 8 caracteres'
                      : null,
                ),
                const SizedBox(height: 14),
                const Text('Roles asignados:',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final rol in widget.rolesDisponibles)
                      FilterChip(
                        label: Text(UserModel.nombreRol(rol)),
                        selected: _rolesSeleccionados.contains(rol),
                        onSelected: (sel) {
                          setState(() {
                            if (sel) {
                              _rolesSeleccionados.add(rol);
                            } else {
                              _rolesSeleccionados.remove(rol);
                            }
                          });
                        },
                      ),
                  ],
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
          child: Text(_guardando ? 'Guardando...' : 'Crear usuario'),
        ),
      ],
    );
  }
}

class _EditarUsuarioDialog extends StatefulWidget {
  const _EditarUsuarioDialog({required this.service, required this.usuario});

  final Modulo1Service service;
  final UserModel usuario;

  @override
  State<_EditarUsuarioDialog> createState() => _EditarUsuarioDialogState();
}

class _EditarUsuarioDialogState extends State<_EditarUsuarioDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nombresCtrl;
  late final TextEditingController _apellidosCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _telefonoCtrl;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nombresCtrl = TextEditingController(text: widget.usuario.nombres);
    _apellidosCtrl = TextEditingController(text: widget.usuario.apellidos);
    _emailCtrl = TextEditingController(text: widget.usuario.email);
    _telefonoCtrl = TextEditingController(text: widget.usuario.telefono ?? '');
  }

  @override
  void dispose() {
    _nombresCtrl.dispose();
    _apellidosCtrl.dispose();
    _emailCtrl.dispose();
    _telefonoCtrl.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.actualizarUsuario(widget.usuario.id, {
        'nombres': _nombresCtrl.text.trim(),
        'apellidos': _apellidosCtrl.text.trim(),
        'email': _emailCtrl.text.trim(),
        'telefono': _telefonoCtrl.text.trim(),
      });
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
      title: Text('Editar usuario @${widget.usuario.username}'),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Text(_error!, style: const TextStyle(color: Colors.redAccent)),
                const SizedBox(height: 10),
              ],
              TextFormField(
                controller: _nombresCtrl,
                decoration: const InputDecoration(
                    labelText: 'Nombres', border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apellidosCtrl,
                decoration: const InputDecoration(
                    labelText: 'Apellidos', border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                    labelText: 'Correo electrónico',
                    border: OutlineInputBorder()),
                validator: (v) =>
                    (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _telefonoCtrl,
                decoration: const InputDecoration(
                    labelText: 'Teléfono', border: OutlineInputBorder()),
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
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando...' : 'Guardar'),
        ),
      ],
    );
  }
}

class _AsignarRolesDialog extends StatefulWidget {
  const _AsignarRolesDialog({
    required this.service,
    required this.usuario,
    required this.rolesDisponibles,
  });

  final Modulo1Service service;
  final UserModel usuario;
  final List<String> rolesDisponibles;

  @override
  State<_AsignarRolesDialog> createState() => _AsignarRolesDialogState();
}

class _AsignarRolesDialogState extends State<_AsignarRolesDialog> {
  late final Set<String> _seleccionados = {...widget.usuario.roles};
  bool _guardando = false;
  String? _error;

  Future<void> _guardar() async {
    if (_seleccionados.isEmpty) {
      setState(() => _error = 'El usuario debe tener al menos un rol.');
      return;
    }
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await widget.service.asignarRolesUsuario(
        widget.usuario.id,
        _seleccionados.toList(),
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
      title: Text('Roles de ${widget.usuario.nombreCompleto}'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_error != null) ...[
              Text(_error!, style: const TextStyle(color: Colors.redAccent)),
              const SizedBox(height: 10),
            ],
            for (final rol in widget.rolesDisponibles)
              CheckboxListTile(
                value: _seleccionados.contains(rol),
                title: Text(UserModel.nombreRol(rol)),
                subtitle: Text(rol),
                onChanged: (v) {
                  setState(() {
                    if (v == true) {
                      _seleccionados.add(rol);
                    } else {
                      _seleccionados.remove(rol);
                    }
                  });
                },
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
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando...' : 'Guardar roles'),
        ),
      ],
    );
  }
}

