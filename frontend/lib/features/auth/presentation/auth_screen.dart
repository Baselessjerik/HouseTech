import 'package:flutter/material.dart';

import '../../../config/app_colors.dart';
import 'widgets/housetech_logo.dart';
import 'widgets/login_form.dart';
import 'widgets/register_form.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 460),
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: AppColors.oceanBlue.withAlpha(20), blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: Column(
                children: [
                  const HousetechLogo(size: 42),
                  const SizedBox(height: 6),
                  const Text('Tu conjunto, en una sola página.', style: TextStyle(fontSize: 13, color: Colors.black54)),
                  const SizedBox(height: 28),
                  Row(children: [_tabButton('Iniciar sesión', 0), _tabButton('Registrarse', 1)]),
                  const SizedBox(height: 24),
                  _tab == 0 ? const LoginForm() : const RegisterForm(),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _tabButton(String label, int tab) => Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _tab = tab),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(color: _tab == tab ? AppColors.oceanBlue : AppColors.bgLight, borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: _tab == tab ? Colors.white : AppColors.textDark))),
          ),
        ),
      );
}
