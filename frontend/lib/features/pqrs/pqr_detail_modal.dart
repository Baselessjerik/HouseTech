import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/pqr_model.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trazabilidad.dart';

/// Abre el detalle desplazable de una PQR con su historial y respuesta.
void verDetalle(BuildContext context, Pqr p) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .8,
        minChildSize: .5,
        maxChildSize: .95,
        builder: (_, sc) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ListView(
            controller: sc,
            padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      p.radicado,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: primaryBlue,
                      ),
                    ),
                  ),
                  EstadoChip(p.estado),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${p.tipo} · ${p.fecha}',
                style: const TextStyle(color: Colors.black54, fontSize: 13),
              ),
              const SizedBox(height: 16),
              Text(
                p.asunto,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: textDark,
                ),
              ),
              if (p.descripcion.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  p.descripcion,
                  style: const TextStyle(fontSize: 14, color: Colors.black87),
                ),
              ],
              const SizedBox(height: 24),
              const Titulo('Historial de cambios'),
              for (int i = 0; i < p.historial.length; i++)
                Evento(
                  p.historial[i].$1,
                  p.historial[i].$2,
                  ultimo: i == p.historial.length - 1,
                  orden: i,
                ),
              if (p.respuesta != null) ...[
                const SizedBox(height: 8),
                Container(
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
                          style:
                              const TextStyle(fontSize: 13, color: textDark)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline, size: 16, color: Colors.black45),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Registro inalterable: cada cambio guarda fecha, hora y usuario responsable.',
                      style: TextStyle(fontSize: 12, color: Colors.black54),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

/// Representa un hito individual del historial con una entrada animada.
class Evento extends StatelessWidget {
  final PqrEstado e;
  final String fecha;
  final bool ultimo;
  final int orden;

  const Evento(
    this.e,
    this.fecha, {
    super.key,
    required this.ultimo,
    required this.orden,
  });

  /// Dibuja el marcador, la línea de continuidad y la fecha del hito.
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + orden * 120),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 10 * (1 - v)),
            child: child,
          ),
        ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Column(
                children: [
                  CircleAvatar(
                    radius: 14,
                    backgroundColor: e.color,
                    child: Icon(e.icon, size: 14, color: Colors.white),
                  ),
                  if (!ultimo)
                    Expanded(
                      child: Container(width: 2, color: Colors.black12),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        e.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: textDark,
                        ),
                      ),
                      Text(
                        fecha,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}
