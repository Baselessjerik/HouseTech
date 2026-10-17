import 'package:flutter/material.dart';

import '../../../../config/app_colors.dart';
import '../../../../services/auth_service.dart';

class RegisterForm extends StatefulWidget {
  const RegisterForm({super.key});

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

  Future<void> _submit() async {
    final required = [
      _nombres,
      _apellidos,
      _username,
      _documento,
      _email,
      _password,
    ];
    if (required.any((controller) => controller.text.trim().isEmpty)) {
      _message('Completa los campos obligatorios', true);
      return;
    }
    setState(() => _loading = true);
    final result = await _service.registrarUsuario(
      nombres: _nombres.text.trim(),
      apellidos: _apellidos.text.trim(),
      username: _username.text.trim(),
      tipoDocumento: _tipo,
      numeroDocumento: _documento.text.trim(),
      email: _email.text.trim(),
      telefono: _telefono.text.trim(),
      password: _password.text,
    );
    if (mounted) setState(() => _loading = false);
    if (mounted) {
      _message(
        result['success'] == true
            ? 'Cuenta creada exitosamente.'
            : result['message'].toString(),
        result['success'] != true,
      );
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
              items: ['CC', 'CE', 'PP', 'NIT']
                  .map(
                    (type) => DropdownMenuItem(value: type, child: Text(type)),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _tipo = value!),
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
        obscureText: true,
        decoration: const InputDecoration(labelText: 'Crear contraseña'),
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
