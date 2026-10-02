import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import 'app_card.dart';

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String titulo, detalle, boton;
  final VoidCallback? onTap;

  const EmptyState({
    super.key,
    required this.icon,
    required this.titulo,
    required this.detalle,
    this.boton = '',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            children: [
              CircleAvatar(
                radius: 36,
                backgroundColor: bgLight,
                child: Icon(icon, size: 36, color: primaryBlue),
              ),
              const SizedBox(height: 16),
              Text(
                titulo,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                detalle,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.black54),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: onTap,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(boton),
                ),
              ],
            ],
          ),
        ),
      );
}