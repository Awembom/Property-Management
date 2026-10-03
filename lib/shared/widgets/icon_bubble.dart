import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// An icon on a soft, rounded square of the same colour.
/// Used at the start of list cards so every row has a splash of colour.
class IconBubble extends StatelessWidget {
  const IconBubble({super.key, required this.icon, required this.color, this.size = 48});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.soft(color),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: size / 2),
    );
  }
}
