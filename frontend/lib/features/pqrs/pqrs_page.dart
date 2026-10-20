import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../models/pqr_model.dart';
import '../../widgets/app_card.dart';
import '../../widgets/common_widgets.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/trazabilidad.dart';
import 'pqr_card.dart';

/// Vista de tarjetas PQR con búsqueda y filtros por estado del trámite.
class PqrsPage extends StatefulWidget {
  final List<Pqr> pqrs;
  final VoidCallback onNuevo;

  const PqrsPage({super.key, required this.pqrs, required this.onNuevo});

  @override
  State<PqrsPage> createState() => _PqrsPageState();
}

/// Conserva los criterios de búsqueda mientras se renderiza el listado.
class _PqrsPageState extends State<PqrsPage> {
  int filtro = 0;
  String q = '';

  /// Filtra las solicitudes y muestra el estado vacío adecuado para el resultado.
  @override
  Widget build(BuildContext context) {
    final todas = widget.pqrs;
    final abiertas = todas.where((p) => p.abierta).toList();
    final cerradas = todas.where((p) => !p.abierta).toList();
    final base = [todas, abiertas, cerradas][filtro];
    final lista = q.isEmpty
        ? base
        : base
            .where((p) => '${p.radicado} ${p.asunto} ${p.tipo}'
                .toLowerCase()
                .contains(q.toLowerCase()))
            .toList();
    final labels = [
      'Todas (${todas.length})',
      'En trámite (${abiertas.length})',
      'Resueltas (${cerradas.length})'
    ];

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Módulo PQRS',
                style: TextStyle(
                    fontSize: 22, fontWeight: FontWeight.bold, color: textDark),
              ),
            ),
            FilledButton.icon(
              onPressed: widget.onNuevo,
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Nuevo PQR'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        AppCard(
          padding: EdgeInsets.zero,
          child: ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: const Icon(Icons.alt_route_rounded, color: primaryBlue),
            title: const Text(
              '¿Cómo funciona el seguimiento?',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
            childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            children: const [
              Trazabilidad(PqrEstado.resuelto),
              SizedBox(height: 12),
              Text(
                'Cada PQR pasa por estos cinco estados y recibirás una notificación en cada cambio.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          onChanged: (v) => setState(() => q = v.trim()),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'Buscar por radicado, asunto o tipo',
            filled: true,
            fillColor: Colors.white,
            contentPadding: EdgeInsets.zero,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.black12),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Colors.black12),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            for (int i = 0; i < 3; i++)
              ChoiceChip(
                label: Text(labels[i]),
                selected: filtro == i,
                onSelected: (_) => setState(() => filtro = i),
              ),
          ],
        ),
        const SizedBox(height: 16),
        if (lista.isEmpty)
          todas.isEmpty
              ? EmptyState(
                  icon: Icons.mark_email_read_outlined,
                  titulo: 'No tienes ninguna PQR radicada',
                  detalle:
                      'Aquí harás seguimiento en tiempo real a tus peticiones, quejas, reclamos o sugerencias.',
                  boton: 'Radicar mi primera PQR',
                  onTap: widget.onNuevo,
                )
              : const EmptyState(
                  icon: Icons.filter_alt_off_outlined,
                  titulo: 'No hay PQRS en este filtro',
                  detalle:
                      'Prueba con otra categoría o con otras palabras de búsqueda.',
                )
        else
          grid([for (final p in lista) PqrCard(p)], cols: 2, minW: 440),
      ],
    );
  }
}
