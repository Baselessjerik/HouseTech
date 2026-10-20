import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config/app_colors.dart';
import '../features/auth/presentation/auth_screen.dart';
import '../features/comunicados/comunicados_menu.dart'; // MODULO-2
import '../models/user_model.dart';
import '../providers/auth_provider.dart';
import '../services/auth_service.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  static const _desktopBreakpoint = 900.0;
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const AuthScreen();

    final items = _itemsFor(user);
    final isDesktop = MediaQuery.sizeOf(context).width >= _desktopBreakpoint;
    final selected = _selected < items.length ? _selected : 0;
    final item = items[selected];

    return Scaffold(
      backgroundColor: AppColors.bgLight,
      appBar: isDesktop
          ? null
          : AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              title: const _Brand(compact: true),
              iconTheme: const IconThemeData(color: AppColors.textDark),
            ),
      drawer: isDesktop ? null : Drawer(child: _navigation(items)),
      body: Row(
        children: [
          if (isDesktop) SizedBox(width: 264, child: _navigation(items)),
          Expanded(
            child: Column(
              children: [
                if (isDesktop) _desktopHeader(item.label, user),
                Expanded(child: _content(item, user)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _desktopHeader(String title, UserModel user) {
    return Container(
      height: 76,
      padding: const EdgeInsets.symmetric(horizontal: 32),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Row(
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              )),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(user.nombreCompleto,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(user.rolesVisibles,
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
          const SizedBox(width: 12),
          _Avatar(user: user),
        ],
      ),
    );
  }

  Widget _navigation(List<_MenuItem> items) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: _Brand(),
          ),
          const SizedBox(height: 24),
          const Divider(color: Color(0xFFE2E8F0)),
          const SizedBox(height: 12),
          Expanded(
            child: ListView(
              children: [
                _sectionLabel('GENERAL'),
                for (var i = 0; i < items.length; i++) _navItem(i, items[i]),
              ],
            ),
          ),
          const Divider(color: Color(0xFFE2E8F0)),
          Material(
            color: Colors.transparent,
            child: ListTile(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              leading:
                  const Icon(Icons.logout_rounded, color: Colors.redAccent),
              title: const Text('Cerrar sesión',
                  style: TextStyle(color: Colors.redAccent)),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Text(label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1,
              color: Colors.black45,
            )),
      );

  Widget _navItem(int index, _MenuItem item) {
    final active = index == _selected;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: Colors.transparent,
        child: ListTile(
          selected: active,
          selectedTileColor: AppColors.bgLight,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          leading: Icon(item.icon,
              color: active ? AppColors.oceanBlue : Colors.black54),
          title: Text(item.label,
              style: TextStyle(
                color: active ? AppColors.oceanBlue : AppColors.textDark,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              )),
          onTap: () {
            setState(() => _selected = index);
            Navigator.of(context).maybePop();
          },
        ),
      ),
    );
  }

  Widget _content(_MenuItem item, UserModel user) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: item.builder(user),
        ),
      ),
    );
  }

  List<_MenuItem> _itemsFor(UserModel user) {
    final items = <_MenuItem>[
      _MenuItem('Inicio', Icons.home_rounded, (_) => _Dashboard(user: user)),
      _MenuItem('Mi perfil', Icons.person_rounded,
          (user) => _ProfilePanel(user: user)),
    ];
    void add(String permission, String label, IconData icon) {
      if (user.tienePermiso(permission)) {
        final paginaModulo2 = ComunicadosMenu.paginaPara(permission); // MODULO-2
        items.add(_MenuItem(label, icon,
            paginaModulo2 ?? (_) => _ModulePreview(title: label))); // MODULO-2
      }
    }

    add('inmuebles.consultar', 'Inmuebles', Icons.apartment_rounded);
    add('comunicados.ver', 'Comunicados', Icons.campaign_rounded);
    add('pqr.radicar', 'Radicar PQR', Icons.add_comment_rounded);
    add('pqr.gestionar', 'Gestionar PQR', Icons.support_agent_rounded);
    add('reservas.solicitar', 'Solicitar reserva',
        Icons.calendar_month_rounded);
    add('usuarios.gestionar', 'Usuarios', Icons.people_alt_rounded);
    add('inmuebles.gestionar', 'Administrar inmuebles',
        Icons.apartment_rounded);
    add('roles.gestionar', 'Roles y permisos',
        Icons.admin_panel_settings_rounded);
    add('configuracion.gestionar', 'Parametrización', Icons.settings_rounded);
    add('amenidades.gestionar', 'Amenidades', Icons.pool_rounded);
    add('bloqueos.gestionar', 'Bloqueos', Icons.lock_clock_rounded);
    add('comunicados.gestionar', 'Administrar comunicados',
        Icons.campaign_rounded);
    add('reportes.ver', 'Reportes', Icons.bar_chart_rounded);
    add('auditoria.ver', 'Auditoría', Icons.history_rounded);
    return items;
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Quieres cerrar tu sesión actual?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AuthService().cerrarSesion();
    if (!mounted) return;
    ref.read(authSessionProvider.notifier).clear();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const AuthScreen()),
      (_) => false,
    );
  }
}

class _Brand extends StatelessWidget {
  const _Brand({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
        children: [
          const Icon(Icons.apartment_rounded,
              color: AppColors.oceanBlue, size: 30),
          if (!compact) ...[
            const SizedBox(width: 10),
            const Flexible(
              child: Text('HouseTech',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.oceanBlue,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  )),
            ),
          ],
        ],
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) => CircleAvatar(
        backgroundColor: AppColors.oceanBlue,
        child: Text(user.iniciales,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w700)),
      );
}

class _Dashboard extends StatelessWidget {
  const _Dashboard({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hola, ${user.nombres}',
              style: const TextStyle(
                fontSize: 30,
                fontWeight: FontWeight.w800,
                color: AppColors.textDark,
              )),
          const SizedBox(height: 6),
          Text('Este es el resumen de tu cuenta en HouseTech.',
              style: TextStyle(color: Colors.blueGrey.shade700)),
          const SizedBox(height: 28),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _SummaryCard(
                  icon: Icons.verified_user_rounded,
                  title: 'Estado de cuenta',
                  value: user.activo ? 'Activa' : 'Inactiva',
                  color: Colors.green),
              _SummaryCard(
                  icon: Icons.badge_rounded,
                  title: 'Rol',
                  value: user.rolesVisibles,
                  color: AppColors.oceanBlue),
              _SummaryCard(
                  icon: Icons.lock_rounded,
                  title: 'Permisos',
                  value: '${user.permisos.length} habilitados',
                  color: Colors.orange),
            ],
          ),
          const SizedBox(height: 24),
          _WelcomeCard(user: user),
        ],
      );
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
  });
  final IconData icon;
  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 250,
        child: Card(
          elevation: 0,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                    backgroundColor: color.withAlpha(25),
                    child: Icon(icon, color: color)),
                const SizedBox(width: 14),
                Expanded(
                    child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            color: Colors.black54, fontSize: 12)),
                    const SizedBox(height: 4),
                    Text(value,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                )),
              ],
            ),
          ),
        ),
      );
}

class _WelcomeCard extends StatelessWidget {
  const _WelcomeCard({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        color: AppColors.oceanBlue,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              const Icon(Icons.waving_hand_rounded,
                  color: Colors.white, size: 42),
              const SizedBox(width: 18),
              Expanded(
                  child: Text(
                'Bienvenido, ${user.nombreCompleto}. Usa el menú para consultar las opciones disponibles para tu perfil.',
                style: const TextStyle(color: Colors.white, fontSize: 16),
              )),
            ],
          ),
        ),
      );
}

class _ModulePreview extends StatelessWidget {
  const _ModulePreview({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: SizedBox(
          height: 360,
          child: Center(
              child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.construction_rounded,
                    size: 56, color: AppColors.oceanBlue.withAlpha(90)),
                const SizedBox(height: 18),
                Text(title, style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Text(
                    'Esta sección está preparada para conectarse con el backend del Módulo 1.',
                    textAlign: TextAlign.center),
              ],
            ),
          )),
        ),
      );
}

class _ProfilePanel extends StatelessWidget {
  const _ProfilePanel({required this.user});
  final UserModel user;

  @override
  Widget build(BuildContext context) => Card(
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                _Avatar(user: user),
                const SizedBox(width: 16),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(user.nombreCompleto,
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(user.rolesVisibles,
                      style: const TextStyle(color: Colors.black54)),
                ]),
              ]),
              const Divider(height: 36),
              _detail('Usuario', user.username),
              _detail('Correo electrónico', user.email),
              _detail(
                  'Documento', '${user.tipoDocumento} ${user.numeroDocumento}'),
              _detail('Teléfono', user.telefono ?? 'No registrado'),
              _detail('Estado', user.activo ? 'Activo' : 'Inactivo'),
            ],
          ),
        ),
      );

  Widget _detail(String label, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(children: [
          SizedBox(
              width: 160,
              child:
                  Text(label, style: const TextStyle(color: Colors.black54))),
          Expanded(
              child: Text(value,
                  style: const TextStyle(fontWeight: FontWeight.w600))),
        ]),
      );
}

class _MenuItem {
  const _MenuItem(this.label, this.icon, this.builder);
  final String label;
  final IconData icon;
  final Widget Function(UserModel user) builder;
}
