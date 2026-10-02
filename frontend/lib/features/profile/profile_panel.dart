import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../widgets/common_widgets.dart';

class ProfilePanel extends StatefulWidget {
  final void Function(String) onAction;
  const ProfilePanel({super.key, required this.onAction});

  @override
  State<ProfilePanel> createState() => _ProfilePanelState();
}

class _ProfilePanelState extends State<ProfilePanel> {
  bool notif = true;

  Widget fila(
    int i,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = textDark,
    Widget? trailing,
  }) =>
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 300 + i * 70),
        curve: Curves.easeOut,
        builder: (_, v, child) => Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - v)),
            child: child,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              children: [
                Icon(icon,
                    size: 21,
                    color: color == textDark ? primaryBlue : color),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ),
                if (trailing != null) trailing,
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) => Material(
        elevation: 12,
        shadowColor: Colors.black38,
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryBlue, Color(0xFF38BDF8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: .6, end: 1),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.elasticOut,
                    builder: (_, v, child) => Transform.scale(scale: v, child: child),
                    child: const UserAvatar(54),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lizeth Suárez',
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Residente · Torre 3 - Apto 502',
                          style: TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            fila(0, Icons.person_outline, 'Mi perfil',
                () => widget.onAction('Abriendo mi perfil…')),
            fila(1, Icons.settings_outlined, 'Configuración',
                () => widget.onAction('Abriendo configuración…')),
            fila(
              2,
              Icons.notifications_outlined,
              'Notificaciones push',
              () => setState(() => notif = !notif),
              trailing: Switch(
                value: notif,
                onChanged: (v) => setState(() => notif = v),
              ),
            ),
            fila(3, Icons.help_outline, 'Ayuda y soporte',
                () => widget.onAction('Abriendo ayuda…')),
            const Divider(height: 12),
            fila(
              4,
              Icons.logout_rounded,
              'Cerrar sesión',
              () => widget.onAction('Sesión cerrada (demo)'),
              color: coralAlert,
            ),
            const SizedBox(height: 6),
          ],
        ),
      );
}