import 'package:flutter/material.dart';
import '../../config/app_theme.dart';
import '../../widgets/common_widgets.dart';

class ProfileTile extends StatefulWidget {
  final bool wide, abierto;
  final VoidCallback onTap;

  const ProfileTile({
    super.key,
    required this.wide,
    required this.abierto,
    required this.onTap,
  });

  @override
  State<ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<ProfileTile> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final activo = hover || widget.abierto;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hover = true),
      onExit: (_) => setState(() => hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: activo ? bgLight : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.abierto
                  ? primaryBlue.withOpacity(.45)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment:
                widget.wide ? MainAxisAlignment.start : MainAxisAlignment.center,
            children: [
              AnimatedScale(
                scale: activo ? 1.08 : 1,
                duration: const Duration(milliseconds: 220),
                child: const UserAvatar(40),
              ),
              if (widget.wide) ...[
                const SizedBox(width: 10),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Lizeth Suárez',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Text('Residente',
                          style: TextStyle(color: Colors.black54, fontSize: 11)),
                    ],
                  ),
                ),
                AnimatedRotation(
                  turns: widget.abierto ? .5 : 0,
                  duration: const Duration(milliseconds: 250),
                  child: const Icon(Icons.expand_more, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}