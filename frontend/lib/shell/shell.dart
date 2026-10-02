import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_theme.dart';
import '../models/aviso_model.dart';
import '../models/pqr_model.dart';
import '../providers/app_providers.dart';
import '../widgets/common_widgets.dart';
import '../features/home/home_page.dart';
import '../features/pqrs/pqrs_page.dart';
import '../features/avisos/avisos_page.dart';
import '../features/profile/profile_tile.dart';
import '../features/profile/profile_panel.dart';

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  bool perfilAbierto = false;
  String? reserva = 'Salón Social|Sáb 4 Oct · 6:00 PM a 10:00 PM';

  int get tab => ref.watch(tabProvider);
  List<Pqr> get pqrs => ref.watch(pqrsProvider);
  Set<int> get leidos => ref.watch(leidosProvider);
  int get sinLeer => avisos.length - leidos.length;
  void go(int i) => ref.read(tabProvider.notifier).set(i);

  void nuevoPqr() {
    var tipo = 'Petición';
    final asunto = TextEditingController(), detalle = TextEditingController();
    final form = GlobalKey<FormState>();
    String? req(String? v, int min) =>
        (v == null || v.trim().length < min)
            ? 'Escribe al menos $min caracteres'
            : null;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Radicar nueva PQR',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          content: SizedBox(
            width: 480,
            child: Form(
              key: form,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final t in ['Petición', 'Queja', 'Reclamo', 'Sugerencia'])
                          ChoiceChip(
                            label: Text(t),
                            selected: tipo == t,
                            onSelected: (_) => setD(() => tipo = t),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: asunto,
                      decoration: dec('Asunto', 'Ej. Reparación de bombillo en pasillo'),
                      validator: (v) => req(v, 5),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: detalle,
                      maxLines: 3,
                      decoration: dec('Descripción detallada',
                          'Describe claramente la situación'),
                      validator: (v) => req(v, 10),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: () => ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Evidencia adjunta seleccionada')),
                      ),
                      icon: const Icon(Icons.attach_file, size: 18),
                      label:
                          const Text('Adjuntar foto o evidencia (opcional)'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.send_rounded, size: 18),
              label: const Text('Radicar PQR'),
              onPressed: () {
                if (!form.currentState!.validate()) return;
                final n = (95 + ref.read(pqrsProvider).length)
                    .toString()
                    .padLeft(3, '0');
                final hora = 'Hoy · ${TimeOfDay.now().format(ctx)}';
                ref.read(pqrsProvider.notifier).agregar(
                      Pqr(
                        'PQR-2026-$n',
                        tipo,
                        asunto.text.trim(),
                        hora,
                        PqrEstado.enviado,
                        descripcion: detalle.text.trim(),
                        historial: [(PqrEstado.enviado, hora)],
                      ),
                    );
                go(1);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('PQR-2026-$n radicada con éxito')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void abrirPerfil() {
    final wide = MediaQuery.of(context).size.width >= 820;
    final left = wide ? 248.0 : 12.0;
    final w = (MediaQuery.of(context).size.width - left - 12)
        .clamp(230.0, 310.0)
        .toDouble();
    setState(() => perfilAbierto = true);
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Cerrar perfil',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (ctx, _, __) => SafeArea(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: EdgeInsets.only(left: left, top: wide ? 16 : 64),
            child: SizedBox(
              width: w,
              child: ProfilePanel(onAction: (msg) {
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(msg)));
              }),
            ),
          ),
        ),
      ),
      transitionBuilder: (ctx, anim, _, child) {
        final curved = CurvedAnimation(
            parent: anim, curve: Curves.easeOutBack, reverseCurve: Curves.easeIn);
        return FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position:
                Tween(begin: const Offset(-.08, 0), end: Offset.zero)
                    .animate(curved),
            child: ScaleTransition(
              scale: Tween(begin: .92, end: 1.0).animate(curved),
              alignment: Alignment.topLeft,
              child: child,
            ),
          ),
        );
      },
    ).then((_) {
      if (mounted) setState(() => perfilAbierto = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.of(context).size.width >= 820;
    final pages = [
      HomePage(
          pqrs: pqrs,
          reserva: reserva,
          sinLeer: sinLeer,
          onGo: go,
          onNuevo: nuevoPqr),
      PqrsPage(pqrs: pqrs, onNuevo: nuevoPqr),
      const Center(
          child: Text('Aquí va el módulo de Reservas (calendario)',
              style: TextStyle(color: Colors.black54))),
      AvisosPage(
          leidos: leidos,
          onMarcar: ref.read(leidosProvider.notifier).marcar,
          onTodos: ref.read(leidosProvider.notifier).todos),
    ];

    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide) ...[
              _sidebar(wide),
              const VerticalDivider(width: 1, color: Colors.black12)
            ],
            Expanded(
              child: Column(
                children: [
                  Container(
                    color: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 10),
                    child: Row(
                      children: [
                        if (!wide) ...[
                          GestureDetector(
                              onTap: abrirPerfil, child: const UserAvatar(38)),
                          const SizedBox(width: 12)
                        ],
                        const Expanded(
                          child: Text(
                            'Lizeth Suárez · Torre 3 - Apto 502',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: textDark),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Avisos',
                          onPressed: () => go(3),
                          icon: Badge(
                            isLabelVisible: sinLeer > 0,
                            label: Text('$sinLeer'),
                            backgroundColor: Colors.redAccent,
                            child: const Icon(Icons.notifications_outlined,
                                color: textDark, size: 28),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.black12),
                  Expanded(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1100),
                        child: pages[tab],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              backgroundColor: Colors.white,
              indicatorColor: primaryBlue.withOpacity(.15),
              onDestinationSelected: go,
              destinations: [
                const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home),
                    label: 'Principal'),
                const NavigationDestination(
                    icon: Icon(Icons.support_agent_outlined),
                    selectedIcon: Icon(Icons.support_agent),
                    label: 'PQRS'),
                const NavigationDestination(
                    icon: Icon(Icons.event_available_outlined),
                    selectedIcon: Icon(Icons.event_available),
                    label: 'Reservas'),
                NavigationDestination(
                    icon: Badge(
                        isLabelVisible: sinLeer > 0,
                        label: Text('$sinLeer'),
                        child: const Icon(Icons.campaign_outlined)),
                    selectedIcon: const Icon(Icons.campaign),
                    label: 'Avisos'),
              ],
            ),
    );
  }

  Widget _sidebar(bool wide) => Container(
        width: wide ? 240 : 80,
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment:
                  wide ? MainAxisAlignment.start : MainAxisAlignment.center,
              children: [
                SizedBox(width: wide ? 16 : 0),
                const Icon(Icons.apartment_rounded,
                    color: primaryBlue, size: 30),
                if (wide) ...[
                  const SizedBox(width: 8),
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(fontSize: 20),
                      children: [
                        TextSpan(
                            text: 'House',
                            style: TextStyle(
                                fontWeight: FontWeight.w900,
                                color: primaryBlue)),
                        TextSpan(
                            text: 'tech',
                            style: TextStyle(color: accentSun)),
                      ],
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),
            ProfileTile(wide: wide, abierto: perfilAbierto, onTap: abrirPerfil),
            const Divider(height: 24),
            _nav(0, Icons.home_outlined, 'Principal', wide),
            _nav(1, Icons.support_agent_outlined, 'PQRS', wide),
            _nav(2, Icons.event_available_outlined, 'Reservas', wide),
            _nav(3, Icons.campaign_outlined, 'Avisos', wide),
          ],
        ),
      );

  Widget _nav(int i, IconData icon, String label, bool wide) {
    final sel = tab == i;
    Widget ic = Icon(icon, color: sel ? primaryBlue : Colors.black54);
    if (i == 3) {
      ic = Badge(
          isLabelVisible: sinLeer > 0, label: Text('$sinLeer'), child: ic);
    }
    return Material(
      color: Colors.transparent,
      child: ListTile(
        selected: sel,
        selectedTileColor: bgLight,
        leading: ic,
        title: wide
            ? Text(label,
                style: TextStyle(
                    color: sel ? primaryBlue : textDark,
                    fontWeight: sel ? FontWeight.bold : FontWeight.normal))
            : null,
        onTap: () => go(i),
      ),
    );
  }
}