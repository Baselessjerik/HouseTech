import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'config/app_theme.dart';
import 'features/auth/presentation/auth_screen.dart';

void main() => runApp(const ProviderScope(child: HousetechApp()));

class HousetechApp extends StatelessWidget {
  const HousetechApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Housetech - Autenticación',
      theme: appTheme,
      home: const AuthScreen(),
    );
  }
}