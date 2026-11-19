import 'package:flutter/material.dart';

import '../../../../config/app_colors.dart';
import '../../../../services/auth_service.dart';

class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key, this.onRegistered});

  final VoidCallback? onRegistered;

  @override
  State<RegisterForm> createState() => _RegisterFormState();
}

class _RegisterFormState extends State<RegisterForm> {
  final _nombres = TextEditingController();
  final _apellidos = TextEditingController();
  final _username = TextEditingController();
  final _documento = TextEditingController();
  final _email = TextEditingController();
  final _telefono = TextEditingController();
  final _password = TextEditingController();
  final _service = AuthService();
  String _tipo = 'CC';
  bool _loading = false;
  bool _ocultarPassword = true;

  @override
  void dispose() {
    for (final controller in [
      _nombres,
      _apellidos,
      _username,
      _documento,
      _email,
      _telefono,
      _password,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _limpiarFormulario() {
    _nombres.clear();
    _apellidos.clear();
    _username.clear();
    _documento.clear();
    _email.clear();
    _telefono.clear();
    _password.clear();
    setState(() => _tipo = 'CC');
  }

  Future<void> _submit() async {
    final requiredFields = [
      _nombres,
      _apellidos,
      _username,
      _documento,
      _email,
      _password,
    ];
    if (requiredFields.any((controller) => controller.text.trim().isEmpty)) {
      _message('Completa los campos obligatorios', true);
      return;
    }
    final userTxt = _username.text.trim();
    if (!RegExp(r'^[A-Za-z0-9._-]{3,60}$').hasMatch(userTxt)) {
      _message(
        'Usuario inválido: usa de 3 a 60 caracteres (letras, números, punto o guion).',
        true,
      );
      return;
    }
    final emailTxt = _email.text.trim();
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(emailTxt)) {
      _message('Ingresa un correo electrónico válido.', true);
      return;
    }
    if (_password.text.length < 8) {
      _message('La contraseña debe tener mínimo 8 caracteres.', true);
      return;
    }

    setState(() => _loading = true);
    final result = await _service.registrarUsuario(
      nombres: _nombres.text.trim(),
      apellidos: _apellidos.text.trim(),
      username: userTxt,
      tipoDocumento: _tipo,
      numeroDocumento: _documento.text.trim(),
      email: emailTxt,
      telefono: _telefono.text.trim(),
      password: _password.text,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    final ok = result['success'] == true;
    _message(
      ok
          ? 'Cuenta creada exitosamente. Ahora inicia sesión.'
          : result['message'].toString(),
      !ok,
    );
    if (ok) {
      _limpiarFormulario();
      widget.onRegistered?.call();
    }
  }

  void _message(String text, bool error) =>
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: error ? Colors.redAccent : AppColors.oceanBlue,
        ),
      );

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nombres,
                  decoration: const InputDecoration(labelText: 'Nombres'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _apellidos,
                  decoration: const InputDecoration(labelText: 'Apellidos'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            decoration: const InputDecoration(labelText: 'Nombre de usuario'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: DropdownButtonFormField<String>(
                  initialValue: _tipo,
                  items: const ['CC', 'CE', 'TI', 'PP', 'NIT']
                      .map(
                        (type) =>
                            DropdownMenuItem(value: type, child: Text(type)),
                      )
                      .toList(),
                  onChanged: (value) => setState(() => _tipo = value ?? 'CC'),
                  decoration: const InputDecoration(
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _documento,
                  decoration: const InputDecoration(labelText: 'Documento'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Correo electrónico'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _telefono,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Teléfono'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: _ocultarPassword,
            decoration: InputDecoration(
              labelText: 'Crear contraseña (mín. 8 caracteres)',
              suffixIcon: IconButton(
                icon: Icon(
                  _ocultarPassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () =>
                    setState(() => _ocultarPassword = !_ocultarPassword),
              ),
            ),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _loading ? null : _submit,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.oceanBlue,
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: _loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                : const Text(
                    'Crear cuenta',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ],
      );
}
