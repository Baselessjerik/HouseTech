import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import '../../../services/auth_service.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _service = AuthService();
  bool _codeSent = false;
  bool _codeValidated = false;
  bool _loading = false;
  bool _newPasswordVisible = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    final email = _emailController.text.trim();
    if (!_isEmail(email)) {
      _message('Escribe un correo electrónico válido.', error: true);
      return;
    }

    setState(() => _loading = true);
    final result = await _service.solicitarRecuperacion(email);
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      setState(() {
        _codeSent = true;
        _codeValidated = false;
      });
      _message('Si el correo existe, recibirás un código para continuar.');
    } else {
      if (result['message'].toString().contains('Código inválido')) {
        setState(() => _codeValidated = false);
      }
      _message(result['message'].toString(), error: true);
    }
  }

  Future<void> _resetPassword() async {
    final code = _codeController.text.trim();
    final password = _newPasswordController.text;
    final confirmation = _confirmPasswordController.text;

    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _message('El código debe tener 6 dígitos.', error: true);
      return;
    }

    if (password.isEmpty || confirmation.isEmpty) {
      _message('Completa los campos de contraseña.', error: true);
      return;
    }
    if (password != confirmation) {
      _message('Las contraseñas no coinciden.', error: true);
      return;
    }

    setState(() => _loading = true);
    final result = await _service.restablecerPassword(
      email: _emailController.text.trim(),
      codigo: code,
      passwordNueva: password,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          icon: const Icon(
            Icons.check_circle_outline,
            color: AppColors.oceanBlue,
            size: 42,
          ),
          title: const Text('Contraseña actualizada'),
          content: const Text(
            'Ya puedes iniciar sesión con tu nueva contraseña.',
            textAlign: TextAlign.center,
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Continuar'),
            ),
          ],
        ),
      );
      if (mounted) Navigator.pop(context);
    } else {
      _message(result['message'].toString(), error: true);
    }
  }

  Future<void> _validateCode() async {
    final code = _codeController.text.trim();
    if (!RegExp(r'^\d{6}$').hasMatch(code)) {
      _message('El código debe tener 6 dígitos.', error: true);
      return;
    }

    setState(() => _loading = true);
    final result = await _service.validarCodigoRecuperacion(
      email: _emailController.text.trim(),
      codigo: code,
    );
    if (!mounted) return;
    setState(() => _loading = false);

    if (result['success'] == true) {
      setState(() => _codeValidated = true);
    } else {
      _message(result['message'].toString(), error: true);
    }
  }

  bool _isEmail(String value) {
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value);
  }

  void _message(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.redAccent : AppColors.oceanBlue,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recuperar contraseña'),
        foregroundColor: AppColors.textDark,
        backgroundColor: Colors.transparent,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 460),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: AppColors.oceanBlue.withAlpha(20),
                  blurRadius: 20,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 250),
              child: !_codeSent
                  ? _emailForm()
                  : _codeValidated
                      ? _passwordForm()
                      : _codeForm(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailForm() {
    return Column(
      key: const ValueKey('email-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.mark_email_read_outlined,
          color: AppColors.oceanBlue,
          size: 52,
        ),
        const SizedBox(height: 16),
        const Text(
          'Recupera tu acceso',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Escribe el correo asociado a tu cuenta y te enviaremos un código de recuperación.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          decoration: const InputDecoration(
            labelText: 'Correo electrónico',
            prefixIcon: Icon(Icons.email_outlined, color: AppColors.oceanBlue),
          ),
        ),
        const SizedBox(height: 20),
        _actionButton('Enviar código', _sendCode),
      ],
    );
  }

  Widget _codeForm() {
    return Column(
      key: const ValueKey('code-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.lock_reset_rounded,
          color: AppColors.oceanBlue,
          size: 52,
        ),
        const SizedBox(height: 16),
        const Text(
          'Verifica tu correo',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Revisa tu correo ${_emailController.text.trim()} e ingresa el código de 6 dígitos que recibiste.',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeController,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Código de recuperación',
            prefixIcon: Icon(Icons.pin_outlined, color: AppColors.oceanBlue),
            counterText: '',
          ),
        ),
        const SizedBox(height: 20),
        _actionButton('Validar código', _validateCode),
        TextButton(
          onPressed: _loading ? null : _sendCode,
          child: const Text('Solicitar un código nuevo'),
        ),
      ],
    );
  }

  Widget _passwordForm() {
    return Column(
      key: const ValueKey('password-form'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(
          Icons.lock_reset_rounded,
          color: AppColors.oceanBlue,
          size: 52,
        ),
        const SizedBox(height: 16),
        const Text(
          'Crea una nueva contraseña',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: AppColors.textDark,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'El código fue validado. Ahora define una contraseña segura para tu cuenta.',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.black54, height: 1.4),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _codeController,
          readOnly: true,
          decoration: const InputDecoration(
            labelText: 'Código validado',
            prefixIcon:
                Icon(Icons.verified_outlined, color: AppColors.oceanBlue),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _newPasswordController,
          obscureText: !_newPasswordVisible,
          decoration: InputDecoration(
            labelText: 'Nueva contraseña',
            prefixIcon: const Icon(
              Icons.lock_outline,
              color: AppColors.oceanBlue,
            ),
            suffixIcon: IconButton(
              icon: Icon(
                _newPasswordVisible ? Icons.visibility_off : Icons.visibility,
              ),
              onPressed: () =>
                  setState(() => _newPasswordVisible = !_newPasswordVisible),
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _confirmPasswordController,
          obscureText: true,
          decoration: const InputDecoration(
            labelText: 'Repite la nueva contraseña',
            prefixIcon: Icon(Icons.lock_outline, color: AppColors.oceanBlue),
          ),
        ),
        const SizedBox(height: 20),
        _actionButton('Guardar nueva contraseña', _resetPassword),
        TextButton(
          onPressed:
              _loading ? null : () => setState(() => _codeValidated = false),
          child: const Text('Volver a validar el código'),
        ),
        TextButton(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _codeSent = false;
                    _codeValidated = false;
                    _codeController.clear();
                    _newPasswordController.clear();
                    _confirmPasswordController.clear();
                  }),
          child: const Text('Usar otro correo'),
        ),
      ],
    );
  }

  Widget _actionButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _loading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.oceanBlue,
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
          : Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }
}
