import 'package:flutter/material.dart';
import '../config/app_theme.dart';

Widget grid(List<Widget> items, {int cols = 3, double minW = 240}) =>
    LayoutBuilder(builder: (_, b) {
      final n = (b.maxWidth / minW).floor().clamp(1, cols);
      final w = (b.maxWidth - 16 * (n - 1)) / n;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final i in items) SizedBox(width: w, child: i)
        ],
      );
    });

InputDecoration dec(String label, String hint) => InputDecoration(
      labelText: label,
      hintText: hint,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
    );

class Titulo extends StatelessWidget {
  final String t;
  const Titulo(this.t, {super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: textDark,
          ),
        ),
      );
}

class UserAvatar extends StatelessWidget {
  final double size;
  const UserAvatar(this.size, {super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [primaryBlue, Color(0xFF38BDF8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: CircleAvatar(
                backgroundColor: Colors.white,
                child: Text(
                  'LS',
                  style: TextStyle(
                    color: primaryBlue,
                    fontWeight: FontWeight.w900,
                    fontSize: size * .3,
                  ),
                ),
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: size * .28,
                height: size * .28,
                decoration: BoxDecoration(
                  color: okGreen,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
          ],
        ),
      );
}