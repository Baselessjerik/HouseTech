import 'package:flutter/material.dart';

import '../../../../config/app_colors.dart';

class HousetechLogo extends StatelessWidget {
  final double size;

  const HousetechLogo({super.key, this.size = 40});

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.apartment_rounded, color: AppColors.oceanBlue, size: size),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: size * .65, fontFamily: 'sans-serif'),
              children: const [
                TextSpan(text: 'House', style: TextStyle(fontWeight: FontWeight.w900, color: AppColors.oceanBlue)),
                TextSpan(text: 'tech', style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.sunYellow)),
              ],
            ),
          ),
        ],
      );
}
