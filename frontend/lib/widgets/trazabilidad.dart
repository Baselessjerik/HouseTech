import 'package:flutter/material.dart';
import '../config/app_theme.dart';
import '../models/pqr_model.dart';

class EstadoChip extends StatelessWidget {
  final PqrEstado e;
  const EstadoChip(this.e, {super.key});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: e.color.withOpacity(.14),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          e.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: e.color,
          ),
        ),
      );
}

class Trazabilidad extends StatelessWidget {
  final PqrEstado estado;
  const Trazabilidad(this.estado, {super.key});

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in PqrEstado.values)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      _linea(e.index > 0 && e.index <= estado.index),
                      CircleAvatar(
                        radius: 14,
                        backgroundColor:
                            e.index <= estado.index ? primaryBlue : Colors.black12,
                        child: Icon(
                          e.icon,
                          size: 14,
                          color: e.index <= estado.index
                              ? Colors.white
                              : Colors.black38,
                        ),
                      ),
                      _linea(e.index < estado.index),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    e.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: e == estado
                          ? FontWeight.w900
                          : FontWeight.normal,
                      color: e.index <= estado.index
                          ? primaryBlue
                          : Colors.black38,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );

  Widget _linea(bool activa) => Expanded(
        child: Container(
          height: 2,
          color: activa ? primaryBlue : Colors.black12,
        ),
      );
}