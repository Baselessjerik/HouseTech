import 'package:flutter/material.dart';

import '../../../../config/app_colors.dart';
import '../../../../services/auth_service.dart';
import '../forgot_password_screen.dart';

class LoginForm extends StatefulWidget {
  const LoginForm({super.key});

  @override
  State<LoginForm> createState() => _LoginFormState();
}

class _LoginFormState extends State<LoginForm> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _service = AuthService();
  bool _loading = false;
  bool _visible = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_username.text.trim().isEmpty || _password.text.isEmpty) {
      _message('Completa usuario y contraseña', true);
      return;
    }
    setState(() => _loading = true);
    final result = await _service.login(_username.text.trim(), _password.text);
    if (mounted) setState(() => _loading = false);
    if (mounted) {
      _message(
        result['success'] == true
            ? '¡Bienvenido a Housetech!'
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
      TextField(
        controller: _username,
        decoration: const InputDecoration(
          labelText: 'Usuario o correo',
          prefixIcon: Icon(Icons.person_outline, color: AppColors.oceanBlue),
        ),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _password,
        obscureText: !_visible,
        decoration: InputDecoration(
          labelText: 'Contraseña',
          prefixIcon: const Icon(
            Icons.lock_outline,
            color: AppColors.oceanBlue,
          ),
          suffixIcon: IconButton(
            icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ),
      ),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _loading
              ? null
              : () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const ForgotPasswordScreen(),
                  ),
                ),
          child: const Text(
            '¿Olvidaste tu contraseña?',
            style: TextStyle(
              color: AppColors.oceanBlue,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
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
                'Ingresar',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    ],
  );
}
