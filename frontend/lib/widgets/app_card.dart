import 'package:flutter/material.dart';

class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color color, borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.color = Colors.white,
    this.borderColor = Colors.black12,
  });

  @override
  Widget build(BuildContext context) => Material(
        color: color,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: borderColor),
        ),
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}