import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/pqr_model.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/trazabilidad.dart';

class HomePage extends StatelessWidget {
  final List<Pqr> pqrs;
  final String? reserva;
  final int sinLeer;
  final void Function(int) onGo;
  final VoidCallback onNuevo;

  const HomePage({
    super.key,
    required this.pqrs,
    required this.reserva,
    required this.sinLeer,
    required this.onGo,
    required this.onNuevo,
  });

  @override
  Widget build(BuildContext context) {
    final abiertas = pqrs.where((p) => p.abierta).length;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text(
          'Menú principal',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: textDark),
        ),
        const Text(
          'Resumen de tu actividad en el conjunto',
          style: TextStyle(color: Colors.black54),
        ),
        const SizedBox(height: 20),
        grid([
          Stat(Icons.event_available, reserva == null ? '0' : '1', 'Reservas activas', primaryBlue, () => onGo(2)),
          Stat(Icons.support_agent, '$abiertas', 'PQRS en trámite', coralAlert, () => onGo(1)),
          Stat(Icons.campaign_outlined, '$sinLeer', 'Avisos no leídos', accentSun, () => onGo(3)),
        ], minW: 220),
        const SizedBox(height: 24),
        grid([
          Seccion('Reserva activa', Icons.bookmark_added_outlined, () => onGo(2), _reserva()),
          Seccion('Mis PQRS recientes', Icons.support_agent_outlined, () => onGo(1), _recientes()),
        ], cols: 2, minW: 340),
        const SizedBox(height: 24),
        const Titulo('Acciones rápidas'),
        grid([
          Accion('Radicar un PQR', 'Reporta daños o peticiones', Icons.add_comment_outlined, primaryBlue, onNuevo),
          Accion('Reservar zona común', 'Consulta agenda y aforo', Icons.calendar_today_outlined, primaryBlue, () => onGo(2)),
          Accion('Ver comunicados', 'Avisos oficiales del conjunto', Icons.campaign_outlined, accentSun, () => onGo(3)),
        ], minW: 250),
      ],
    );
  }

  Widget _reserva() {
    if (reserva == null) {
      return Column(
        children: [
          const Icon(Icons.event_busy, size: 34, color: Colors.black38),
          const SizedBox(height: 6),
          const Text('Sin reservas activas', style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w600)),
          TextButton(onPressed: () => onGo(2), child: const Text('Reservar ahora')),
        ],
      );
    }
    final p = reserva!.split('|');
    return Row(
      children: [
        const CircleAvatar(backgroundColor: primaryBlue, child: Icon(Icons.celebration, color: Colors.white)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(p[0], style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text(p[1], style: const TextStyle(fontSize: 13, color: Colors.black54)),
            ],
          ),
        ),
        const Chip(
          label: Text('Confirmada', style: TextStyle(color: primaryBlue, fontSize: 12, fontWeight: FontWeight.bold)),
          backgroundColor: bgLight,
          side: BorderSide.none,
        ),
      ],
    );
  }

  Widget _recientes() {
    if (pqrs.isEmpty) {
      return Column(
        children: [
          const Text('Aún no has radicado ninguna PQR', style: TextStyle(color: Colors.black54)),
          TextButton(onPressed: onNuevo, child: const Text('Radicar mi primera PQR')),
        ],
      );
    }
    return Column(
      children: [
        for (final p in pqrs.take(3))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.radicado, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: primaryBlue)),
                      Text(p.asunto, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, color: textDark)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                EstadoChip(p.estado),
              ],
            ),
          ),
      ],
    );
  }
}

class Stat extends StatelessWidget {
  final IconData icon;
  final String value, title;
  final Color color;
  final VoidCallback onTap;

  const Stat(this.icon, this.value, this.title, this.color, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        child: Row(
          children: [
            CircleAvatar(backgroundColor: color.withOpacity(.12), child: Icon(icon, color: color)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: textDark)),
                  Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black26),
          ],
        ),
      );
}

class Seccion extends StatelessWidget {
  final String titulo;
  final IconData icon;
  final VoidCallback onMas;
  final Widget child;

  const Seccion(this.titulo, this.icon, this.onMas, this.child, {super.key});

  @override
  Widget build(BuildContext context) => AppCard(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: primaryBlue, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: textDark))),
                TextButton(onPressed: onMas, child: const Text('Ver todo')),
              ],
            ),
            const Divider(height: 16),
            child,
          ],
        ),
      );
}

class Accion extends StatelessWidget {
  final String titulo, sub;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const Accion(this.titulo, this.sub, this.icon, this.color, this.onTap, {super.key});

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(.12), borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titulo, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: textDark)),
                  Text(sub, style: const TextStyle(fontSize: 11, color: Colors.black54)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.black38, size: 20),
          ],
        ),
      );
}