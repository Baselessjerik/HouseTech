import 'package:flutter/material.dart';

const primaryBlue = Color(0xFF0284C7);
const bgLight = Color(0xFFF0F9FF);
const accentSun = Color(0xFFF59E0B);
const coralAlert = Color(0xFFE4572E);
const okGreen = Color(0xFF16A34A);
const textDark = Color(0xFF0F172A);

ThemeData get appTheme => ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: bgLight,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryBlue,
        primary: primaryBlue,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );