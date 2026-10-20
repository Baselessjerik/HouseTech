import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/pqr_model.dart';
import '../../widgets/app_card.dart';
import '../../widgets/trazabilidad.dart';
import 'pqr_detail_modal.dart';

/// Tarjeta resumida que abre el detalle de una solicitud seleccionada.
class PqrCard extends StatelessWidget {
  final Pqr p;
  const PqrCard(this.p, {super.key});

  /// Resume radicado, tipo, fecha, trazabilidad y respuesta disponible.
  @override
  Widget build(BuildContext context) {
    final c = p.esQueja ? coralAlert : primaryBlue;
    return AppCard(
      onTap: () => verDetalle(context, p),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: primaryBlue.withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p.radicado,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primaryBlue,
                    fontSize: 13,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.withOpacity(.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  p.tipo,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: c,
                  ),
                ),
              ),
              Text(
                p.fecha,
                style: const TextStyle(fontSize: 12, color: Colors.black45),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            p.asunto,
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, color: textDark),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: bgLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Trazabilidad(p.estado),
          ),
          const SizedBox(height: 8),
          const Align(
            alignment: Alignment.centerRight,
            child: Text(
              'Ver historial completo ›',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: primaryBlue,
              ),
            ),
          ),
          if (p.respuesta != null) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primaryBlue.withOpacity(.06),
                borderRadius: BorderRadius.circular(10),
                border: const Border(
                  left: BorderSide(color: primaryBlue, width: 4),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Respuesta de la administración',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: primaryBlue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(p.respuesta!,
                      style: const TextStyle(fontSize: 13, color: textDark)),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
