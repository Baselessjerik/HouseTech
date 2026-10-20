import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/app_colors.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/empty_state.dart';
import '../models/modelos.dart';
import '../providers/comunicados_providers.dart';
import '../widgets/ui.dart';

/// Pantalla del residente: avisos (RF14), notificaciones (RF8/RF16) y disponibilidad (RF6).
class ComunicadosResidentePage extends ConsumerStatefulWidget {
  const ComunicadosResidentePage({super.key});

  @override
  ConsumerState<ComunicadosResidentePage> createState() => _ComunicadosResidentePageState();
}

class _ComunicadosResidentePageState extends ConsumerState<ComunicadosResidentePage> {
  int _vista = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(avisosProvider.notifier).recargar();
      ref.read(notificacionesProvider.notifier).recargar();
      ref.invalidate(conteoNoLeidasProvider);
      ref.invalidate(categoriasProvider);
    });
  }

  @override
  Widget build(BuildContext context) {
    final noLeidas = ref.watch(conteoNoLeidasProvider).maybeWhen(data: (n) => n, orElse: () => 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Encabezado(
          titulo: 'Comunicados',
          subtitulo: 'Avisos de la administración, notificaciones y estado de las zonas comunes.',
        ),
        const SizedBox(height: 20),
        SelectorVista(
          etiquetas: ['Avisos', noLeidas > 0 ? 'Notificaciones ($noLeidas)' : 'Notificaciones', 'Disponibilidad'],
          indice: _vista,
          onCambio: (i) => setState(() => _vista = i),
        ),
        const SizedBox(height: 20),
        if (_vista == 0) const _AvisosVista(),
        if (_vista == 1) const _NotificacionesVista(),
        if (_vista == 2) const _DisponibilidadVista(),
      ],
    );
  }
}

// ------------------------------------------------------------------------------ avisos
class _AvisosVista extends ConsumerStatefulWidget {
  const _AvisosVista();

  @override
  ConsumerState<_AvisosVista> createState() => _AvisosVistaState();
}

class _AvisosVistaState extends ConsumerState<_AvisosVista> {
  final _buscar = TextEditingController();

  @override
  void dispose() {
    _buscar.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(avisosProvider);
    final notifier = ref.read(avisosProvider.notifier);
    final categorias = ref.watch(categoriasProvider).maybeWhen(data: (c) => c, orElse: () => <CategoriaComunicado>[]);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _buscar,
          textInputAction: TextInputAction.search,
          onSubmitted: (t) => notifier.filtrar(texto: t.trim()),
          decoration: InputDecoration(
            hintText: 'Buscar en los avisos',
            prefixIcon: const Icon(Icons.search_rounded),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: Colors.white,
            suffixIcon: _buscar.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _buscar.clear();
                      notifier.filtrar(texto: '');
                      setState(() {});
                    },
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (categorias.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('Todas'),
              selected: notifier.categoria == null,
              onSelected: (_) => notifier.filtrar(limpiarCategoria: true),
            ),
            for (final c in categorias)
              ChoiceChip(
                label: Text(c.nombre),
                selected: notifier.categoria == c.id,
                onSelected: (_) => notifier.filtrar(categoriaId: c.id),
              ),
          ]),
        ],
        const SizedBox(height: 16),
        ListaPaginada<Comunicado>(
          estado: estado,
          onReintentar: notifier.recargar,
          onMas: notifier.masResultados,
          vacio: const EmptyState(
            icon: Icons.campaign_outlined,
            titulo: 'No hay avisos',
            detalle: 'Cuando la administración publique un comunicado lo verás aquí.',
          ),
          itemBuilder: (context, aviso) => _AvisoCard(aviso: aviso),
        ),
      ],
    );
  }
}

class _AvisoCard extends StatelessWidget {
  const _AvisoCard({required this.aviso});

  final Comunicado aviso;

  @override
  Widget build(BuildContext context) => AppCard(
        onTap: () => showDialog<void>(context: context, builder: (_) => AvisoDetalleDialog(aviso: aviso)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (aviso.categoriaNombre != null) EstadoChip(aviso.categoriaNombre!, color: aviso.colorCategoria),
            const Spacer(),
            if (aviso.fechaPublicacion != null)
              Text(fechaCorta(aviso.fechaPublicacion!), style: const TextStyle(color: Colors.black54, fontSize: 12)),
          ]),
          const SizedBox(height: 10),
          Text(aviso.titulo,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textDark)),
          const SizedBox(height: 6),
          Text(aviso.contenido, maxLines: 3, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
        ]),
      );
}

class AvisoDetalleDialog extends StatelessWidget {
  const AvisoDetalleDialog({super.key, required this.aviso});

  final Comunicado aviso;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(aviso.titulo),
        content: SizedBox(
          width: 520,
          child: SingleChildScrollView(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (aviso.categoriaNombre != null) EstadoChip(aviso.categoriaNombre!, color: aviso.colorCategoria),
                if (aviso.fechaPublicacion != null)
                  Text('Publicado el ${fechaHora(aviso.fechaPublicacion!)}',
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ]),
              if (aviso.autorNombre != null) ...[
                const SizedBox(height: 6),
                Text('Por ${aviso.autorNombre}', style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              SelectableText(aviso.contenido),
              if (aviso.fechaExpiracion != null) ...[
                const SizedBox(height: 14),
                Text('Vigente hasta el ${fechaHora(aviso.fechaExpiracion!)}',
                    style: const TextStyle(color: Colors.black54, fontSize: 12)),
              ],
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cerrar'))],
      );
}

// ------------------------------------------------------------------------ notificaciones
class _NotificacionesVista extends ConsumerWidget {
  const _NotificacionesVista();

  IconData _icono(String tipo) {
    switch (tipo) {
      case 'COMUNICADO':
        return Icons.campaign_rounded;
      case 'MANTENIMIENTO':
        return Icons.build_circle_rounded;
      case 'BLOQUEO':
        return Icons.lock_clock_rounded;
      case 'RESERVA':
        return Icons.event_busy_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final estado = ref.watch(notificacionesProvider);
    final notifier = ref.read(notificacionesProvider.notifier);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          FilterChip(
            label: const Text('Solo no leídas'),
            selected: notifier.soloNoLeidas,
            onSelected: notifier.alternarFiltro,
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: estado.items.any((n) => !n.leida)
                ? () => ejecutarSimple(context, notifier.marcarTodas, exito: 'Todas marcadas como leídas')
                : null,
            icon: const Icon(Icons.done_all_rounded),
            label: const Text('Marcar todas como leídas'),
          ),
        ]),
        const SizedBox(height: 12),
        ListaPaginada<NotificacionApp>(
          estado: estado,
          onReintentar: notifier.recargar,
          onMas: notifier.masResultados,
          vacio: const EmptyState(
            icon: Icons.notifications_none_rounded,
            titulo: 'Sin notificaciones',
            detalle: 'Te avisaremos de nuevos comunicados, mantenimientos y bloqueos.',
          ),
          itemBuilder: (context, n) => AppCard(
            onTap: () => notifier.marcarLeida(n),
            color: n.leida ? Colors.white : AppColors.bgLight,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CircleAvatar(
                backgroundColor: AppColors.oceanBlue.withAlpha(25),
                child: Icon(_icono(n.tipo), color: AppColors.oceanBlue),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.titulo,
                      style: TextStyle(
                          fontWeight: n.leida ? FontWeight.w500 : FontWeight.w800, color: AppColors.textDark)),
                  const SizedBox(height: 4),
                  Text(n.mensaje, style: const TextStyle(color: Colors.black87)),
                  if (n.createdAt != null) ...[
                    const SizedBox(height: 6),
                    Text(fechaHora(n.createdAt!), style: const TextStyle(color: Colors.black45, fontSize: 12)),
                  ],
                ]),
              ),
              if (!n.leida)
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 4),
                  child: Icon(Icons.circle, size: 10, color: AppColors.skyBlue),
                ),
            ]),
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------- disponibilidad
class _DisponibilidadVista extends ConsumerStatefulWidget {
  const _DisponibilidadVista();

  @override
  ConsumerState<_DisponibilidadVista> createState() => _DisponibilidadVistaState();
}

class _DisponibilidadVistaState extends ConsumerState<_DisponibilidadVista> {
  DateTime? _momento; // null = ahora

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.invalidate(disponibilidadProvider));
  }

  @override
  Widget build(BuildContext context) {
    final datos = ref.watch(disponibilidadProvider(_momento));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: [
          Expanded(
            child: SelectorFechaHora(
              etiqueta: 'Consultar para',
              valor: _momento,
              opcional: true,
              onCambio: (d) => setState(() => _momento = d),
            ),
          ),
          const SizedBox(width: 12),
          IconButton.filledTonal(
            tooltip: 'Actualizar',
            onPressed: () => ref.invalidate(disponibilidadProvider(_momento)),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Text(_momento == null ? 'Mostrando el estado actual.' : 'Mostrando el estado en la fecha elegida.',
              style: const TextStyle(color: Colors.black54, fontSize: 12)),
        ),
        const SizedBox(height: 8),
        datos.when(
          loading: () => const CargandoCaja(),
          error: (e, _) => ErrorCaja(
            mensaje: e.toString(),
            onReintentar: () => ref.invalidate(disponibilidadProvider(_momento)),
          ),
          data: (lista) => lista.isEmpty
              ? const EmptyState(
                  icon: Icons.pool_outlined,
                  titulo: 'Sin amenidades',
                  detalle: 'Aún no hay zonas comunes registradas.',
                )
              : Wrap(spacing: 16, runSpacing: 16, children: [for (final a in lista) _AmenidadCard(a: a)]),
        ),
      ],
    );
  }
}

class _AmenidadCard extends StatelessWidget {
  const _AmenidadCard({required this.a});

  final DisponibilidadAmenidad a;

  @override
  Widget build(BuildContext context) {
    final color = colorEstado(a.estado);
    return SizedBox(
      width: 330,
      child: AppCard(
        borderColor: color.withAlpha(90),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(a.nombre,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: AppColors.textDark)),
            ),
            EstadoChip(nombreEstado(a.estado), color: color),
          ]),
          if (a.descripcion != null && a.descripcion!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(a.descripcion!, style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ],
          if (a.capacidad != null) ...[
            const SizedBox(height: 6),
            Text('Capacidad: ${a.capacidad} personas', style: const TextStyle(color: Colors.black54, fontSize: 13)),
          ],
          if (a.estado != 'DISPONIBLE') ...[
            const Divider(height: 22),
            if (a.motivo != null) Text('Motivo: ${a.motivo}', style: const TextStyle(fontWeight: FontWeight.w600)),
            if (a.desde != null && a.hasta != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(rangoFechas(a.desde!, a.hasta!), style: const TextStyle(fontSize: 13)),
              ),
          ],
          if (a.proximoBloqueo != null) _Proximo(icono: Icons.lock_clock_rounded, titulo: 'Próximo bloqueo', r: a.proximoBloqueo!),
          if (a.proximoMantenimiento != null)
            _Proximo(icono: Icons.build_rounded, titulo: 'Próximo mantenimiento', r: a.proximoMantenimiento!),
        ]),
      ),
    );
  }
}

class _Proximo extends StatelessWidget {
  const _Proximo({required this.icono, required this.titulo, required this.r});

  final IconData icono;
  final String titulo;
  final RangoInfo r;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icono, size: 16, color: Colors.black45),
          const SizedBox(width: 8),
          Expanded(
            child: Text('$titulo: ${rangoFechas(r.inicio, r.fin)}${r.motivo != null ? '\n${r.motivo}' : ''}',
                style: const TextStyle(fontSize: 12.5, color: Colors.black87)),
          ),
        ]),
      );
}
