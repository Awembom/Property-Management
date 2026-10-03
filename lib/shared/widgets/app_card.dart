import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// A white rounded card with a soft shadow, the main building block of the
/// design. Tappable when [onTap] is given.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(16),
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Background; white (or the dark surface) by default.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(20);
    return Container(
      decoration: BoxDecoration(
        // A see-through tint is mixed onto the card colour, so the background
        // shapes never show through a card.
        color: color == null
            ? Theme.of(context).colorScheme.surface
            : Color.alphaBlend(color!, Theme.of(context).colorScheme.surface),
        borderRadius: radius,
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
