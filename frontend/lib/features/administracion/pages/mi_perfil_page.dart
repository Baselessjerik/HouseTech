import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../models/user_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../services/auth_service.dart';

/// Avatar reutilizable que muestra la foto de perfil en base64 (si existe)
/// o las iniciales del usuario sobre el color institucional.
class UserAvatarWidget extends StatelessWidget {
  const UserAvatarWidget({
    super.key,
    required this.user,
    this.radius = 20,
    this.fontSize,
    this.overrideBytes,
  });

  final UserModel user;
  final double radius;
  final double? fontSize;
  final Uint8List? overrideBytes;

  @override
  Widget build(BuildContext context) {
    final bytes = overrideBytes ?? user.fotoBytes;
    if (bytes != null && bytes.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.oceanBlue.withAlpha(30),
        backgroundImage: MemoryImage(bytes),
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.oceanBlue,
      child: Text(
        user.iniciales,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: fontSize ?? (radius * 0.72),
        ),
      ),
    );
  }
}

class MiPerfilPage extends ConsumerStatefulWidget {
  const MiPerfilPage({super.key, required this.user});
  final UserModel user;

  @override
  ConsumerState<MiPerfilPage> createState() => _MiPerfilPageState();
}

class _MiPerfilPageState extends ConsumerState<MiPerfilPage> {
  bool _subiendoFoto = false;

  void _mostrarMensaje(String msg, {bool esError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: esError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  Future<void> _seleccionarFoto(UserModel user) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['png', 'jpg', 'jpeg', 'webp', 'gif'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) {
        _mostrarMensaje('No se pudo leer el archivo seleccionado.', esError: true);
        return;
      }
      if (bytes.lengthInBytes > 3 * 1024 * 1024) {
        _mostrarMensaje('La imagen no debe superar los 3 MB.', esError: true);
        return;
      }
      final ext = (file.extension ?? 'png').toLowerCase();
      final mime = ext == 'jpg' ? 'jpeg' : ext;
      final dataUri = 'data:image/$mime;base64,${base64Encode(bytes)}';

      setState(() => _subiendoFoto = true);
      final res = await AuthService().actualizarPerfil(
        fotoPerfil: dataUri,
        actualizarFoto: true,
      );
      if (!mounted) return;
      setState(() => _subiendoFoto = false);
      if (res['success'] == true && res['user'] is UserModel) {
        ref.read(authSessionProvider.notifier).setUser(res['user'] as UserModel);
        _mostrarMensaje('Foto de perfil actualizada.');
      } else {
        _mostrarMensaje(
          res['message']?.toString() ?? 'No se pudo actualizar la foto.',
          esError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendoFoto = false);
      _mostrarMensaje('Error al actualizar la foto: $e', esError: true);
    }
  }

  Future<void> _quitarFoto(UserModel user) async {
    setState(() => _subiendoFoto = true);
    try {
      final res = await AuthService().actualizarPerfil(
        fotoPerfil: '',
        actualizarFoto: true,
      );
      if (!mounted) return;
      setState(() => _subiendoFoto = false);
      if (res['success'] == true && res['user'] is UserModel) {
        ref.read(authSessionProvider.notifier).setUser(res['user'] as UserModel);
        _mostrarMensaje('Foto de perfil eliminada.');
      } else {
        _mostrarMensaje(
          res['message']?.toString() ?? 'No se pudo eliminar la foto.',
          esError: true,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _subiendoFoto = false);
      _mostrarMensaje(e.toString(), esError: true);
    }
  }

  Future<void> _abrirModalEditarContacto(UserModel user) async {
    final actualizado = await showDialog<UserModel>(
      context: context,
      builder: (_) => _EditarContactoDialog(user: user),
    );
    if (actualizado != null && mounted) {
      ref.read(authSessionProvider.notifier).setUser(actualizado);
      _mostrarMensaje('Datos de contacto actualizados correctamente.');
    }
  }

  Future<void> _abrirModalCambiarPassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => const _CambiarPasswordDialog(),
    );
    if (ok == true && mounted) {
      _mostrarMensaje('Contraseña actualizada correctamente.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider) ?? widget.user;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Cabecera del perfil (ancho completo)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Wrap(
            spacing: 24,
            runSpacing: 20,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    alignment: Alignment.bottomRight,
                    children: [
                      UserAvatarWidget(user: user, radius: 46),
                      Material(
                        color: AppColors.oceanBlue,
                        shape: const CircleBorder(),
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: _subiendoFoto ? null : () => _seleccionarFoto(user),
                          child: Padding(
                            padding: const EdgeInsets.all(8),
                            child: _subiendoFoto
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.camera_alt_rounded,
                                    size: 16,
                                    color: Colors.white,
                                  ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 22),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.nombreCompleto,
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: AppColors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoBadge(
                              icon: Icons.badge_outlined,
                              label: user.rolesVisibles,
                              color: AppColors.oceanBlue,
                            ),
                            _InfoBadge(
                              icon: Icons.alternate_email_rounded,
                              label: user.username,
                              color: const Color(0xFF475569),
                            ),
                            _InfoBadge(
                              icon: Icons.verified_user_outlined,
                              label: user.activo ? 'Cuenta Activa' : 'Inactiva',
                              color: user.activo
                                  ? const Color(0xFF16A34A)
                                  : Colors.red,
                            ),
                          ],
                        ),
                        if (user.fotoBytes != null) ...[
                          const SizedBox(height: 8),
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            onPressed:
                                _subiendoFoto ? null : () => _quitarFoto(user),
                            icon: const Icon(Icons.delete_outline,
                                size: 15, color: Colors.redAccent),
                            label: const Text(
                              'Quitar foto de perfil',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.redAccent),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  OutlinedButton.icon(
                    onPressed: _abrirModalCambiarPassword,
                    icon: const Icon(Icons.lock_reset_rounded, size: 18),
                    label: const Text('Cambiar contraseña'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 18, vertical: 14),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => _abrirModalEditarContacto(user),
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    label: const Text('Editar perfil'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // 2. Grilla distribuida en 2 columnas con los datos ordenados
        LayoutBuilder(
          builder: (context, constraints) {
            final esDosColumnas = constraints.maxWidth >= 720;
            final anchoColumna = esDosColumnas
                ? (constraints.maxWidth - 20) / 2
                : constraints.maxWidth;

            return Wrap(
              spacing: 20,
              runSpacing: 20,
              children: [
                // Columna 1: Identificación Personal (Solo lectura)
                SizedBox(
                  width: anchoColumna,
                  child: _SeccionDatosCard(
                    icono: Icons.assignment_ind_outlined,
                    titulo: 'Datos de Identificación',
                    subtitulo:
                        'Información titular registrada en la copropiedad (no editable).',
                    filas: [
                      _DatoFila(
                        etiqueta: 'Nombres',
                        valor: user.nombres,
                        icono: Icons.person_outline_rounded,
                        fijo: true,
                      ),
                      _DatoFila(
                        etiqueta: 'Apellidos',
                        valor: user.apellidos,
                        icono: Icons.person_outline_rounded,
                        fijo: true,
                      ),
                      _DatoFila(
                        etiqueta: 'Tipo de documento',
                        valor: user.tipoDocumento,
                        icono: Icons.description_outlined,
                        fijo: true,
                      ),
                      _DatoFila(
                        etiqueta: 'Número de documento',
                        valor: user.numeroDocumento,
                        icono: Icons.pin_outlined,
                        fijo: true,
                      ),
                    ],
                  ),
                ),

                // Columna 2: Datos de Contacto y Acceso
                SizedBox(
                  width: anchoColumna,
                  child: _SeccionDatosCard(
                    icono: Icons.contact_mail_outlined,
                    titulo: 'Contacto y Cuenta',
                    subtitulo:
                        'Canales de notificación y credenciales de acceso.',
                    filas: [
                      _DatoFila(
                        etiqueta: 'Correo electrónico',
                        valor: user.email,
                        icono: Icons.email_outlined,
                      ),
                      _DatoFila(
                        etiqueta: 'Teléfono / Celular',
                        valor: (user.telefono != null &&
                                user.telefono!.trim().isNotEmpty)
                            ? user.telefono!
                            : 'No registrado',
                        icono: Icons.phone_outlined,
                      ),
                      _DatoFila(
                        etiqueta: 'Usuario de acceso',
                        valor: '@${user.username}',
                        icono: Icons.account_circle_outlined,
                        fijo: true,
                      ),
                      _DatoFila(
                        etiqueta: 'Contraseña',
                        valor: '••••••••••••',
                        icono: Icons.lock_outline_rounded,
                      ),
                    ],
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

class _InfoBadge extends StatelessWidget {
  const _InfoBadge({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withAlpha(20),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _DatoFila {
  const _DatoFila({
    required this.etiqueta,
    required this.valor,
    required this.icono,
    this.fijo = false,
  });

  final String etiqueta;
  final String valor;
  final IconData icono;
  final bool fijo;
}

class _SeccionDatosCard extends StatelessWidget {
  const _SeccionDatosCard({
    required this.icono,
    required this.titulo,
    required this.subtitulo,
    required this.filas,
  });

  final IconData icono;
  final String titulo;
  final String subtitulo;
  final List<_DatoFila> filas;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.oceanBlue.withAlpha(20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icono, color: AppColors.oceanBlue, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitulo,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          const SizedBox(height: 8),
          for (var i = 0; i < filas.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  Icon(filas[i].icono,
                      size: 18, color: const Color(0xFF64748B)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          filas[i].etiqueta,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          filas[i].valor,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textDark,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (filas[i].fijo)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        'Fijo',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (i < filas.length - 1)
              const Divider(height: 1, color: Color(0xFFF1F5F9)),
          ],
        ],
      ),
    );
  }
}

/// Modal para editar únicamente Correo Electrónico y Teléfono (sin cambiar nombre).
class _EditarContactoDialog extends StatefulWidget {
  const _EditarContactoDialog({required this.user});
  final UserModel user;

  @override
  State<_EditarContactoDialog> createState() => _EditarContactoDialogState();
}

class _EditarContactoDialogState extends State<_EditarContactoDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailCtrl;
  late final TextEditingController _telefonoCtrl;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.user.email);
    _telefonoCtrl = TextEditingController(text: widget.user.telefono ?? '');
  }

  @override
  void dispose() {
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
      final res = await AuthService().actualizarPerfil(
        email: _emailCtrl.text.trim(),
        telefono: _telefonoCtrl.text.trim(),
      );
      if (!mounted) return;
      if (res['success'] == true && res['user'] is UserModel) {
        Navigator.pop(context, res['user'] as UserModel);
      } else {
        setState(() {
          _error = res['message']?.toString() ?? 'No se pudo actualizar.';
          _guardando = false;
        });
      }
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
    return AlertDialog(
      title: const Text(
        'Editar datos de contacto',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Puedes actualizar tu correo electrónico y número de teléfono. El nombre titular y documento son permanentes.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: Icon(Icons.email_outlined),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Ingresa tu correo';
                  }
                  if (!v.contains('@')) return 'Correo inválido';
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _telefonoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Teléfono / Celular',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: Text(_guardando ? 'Guardando...' : 'Guardar cambios'),
        ),
      ],
    );
  }
}

/// Modal para cambiar la contraseña.
class _CambiarPasswordDialog extends StatefulWidget {
  const _CambiarPasswordDialog();

  @override
  State<_CambiarPasswordDialog> createState() => _CambiarPasswordDialogState();
}

class _CambiarPasswordDialogState extends State<_CambiarPasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confirmarCtrl = TextEditingController();
  bool _ocultarActual = true;
  bool _ocultarNueva = true;
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confirmarCtrl.dispose();
    super.dispose();
  }

  Future<void> _cambiar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final res = await AuthService().cambiarPassword(
        actual: _actualCtrl.text,
        nueva: _nuevaCtrl.text,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _error = res['message']?.toString() ?? 'No se pudo cambiar la clave.';
          _guardando = false;
        });
      }
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
    return AlertDialog(
      title: const Text(
        'Cambiar contraseña',
        style: TextStyle(fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 440,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Tu nueva contraseña debe tener mínimo 8 caracteres e incluir letras y números.',
                style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 18),
              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style: TextStyle(color: Colors.red.shade800, fontSize: 12),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextFormField(
                controller: _actualCtrl,
                obscureText: _ocultarActual,
                decoration: InputDecoration(
                  labelText: 'Contraseña actual',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    icon: Icon(_ocultarActual
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _ocultarActual = !_ocultarActual),
                  ),
                ),
                validator: (v) =>
                    (v == null || v.isEmpty) ? 'Ingresa tu clave actual' : null,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _nuevaCtrl,
                obscureText: _ocultarNueva,
                decoration: InputDecoration(
                  labelText: 'Nueva contraseña',
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(_ocultarNueva
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined),
                    onPressed: () =>
                        setState(() => _ocultarNueva = !_ocultarNueva),
                  ),
                ),
                validator: (v) {
                  if (v == null || v.length < 8) {
                    return 'Mínimo 8 caracteres';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _confirmarCtrl,
                obscureText: _ocultarNueva,
                decoration: const InputDecoration(
                  labelText: 'Confirmar nueva contraseña',
                  prefixIcon: Icon(Icons.verified_user_outlined),
                ),
                validator: (v) {
                  if (v != _nuevaCtrl.text) {
                    return 'Las contraseñas no coinciden';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _cambiar,
          child: Text(_guardando ? 'Actualizando...' : 'Actualizar contraseña'),
        ),
      ],
    );
  }
}
