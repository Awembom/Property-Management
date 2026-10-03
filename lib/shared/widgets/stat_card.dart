import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/shared/widgets/app_card.dart';

/// A small summary tile: coloured icon in a circle, a label and a big value,
/// e.g. "Occupied 8/10". With [highlight] it's filled with the colour (the
/// first tile of an overview grid).
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    this.color = AppColors.primary,
    this.highlight = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final bool highlight;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final foreground = highlight ? Colors.white : null;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: highlight ? Colors.white.withValues(alpha: 0.22) : AppColors.soft(color),
          ),
          child: Icon(icon, size: 20, color: highlight ? Colors.white : color),
        ),
        const SizedBox(height: 14),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodySmall?.copyWith(
            color: highlight ? Colors.white.withValues(alpha: 0.85) : null,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: text.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: foreground),
          ),
        ),
      ],
    );

    if (!highlight) return AppCard(onTap: onTap, child: content);
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.gradientFor(color),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 8)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: const EdgeInsets.all(16), child: content),
        ),
      ),
    );
  }
}

/// Lays out stat cards two per row.
class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      rows.add(Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: children[i]),
          const SizedBox(width: 12),
          Expanded(child: i + 1 < children.length ? children[i + 1] : const SizedBox()),
        ],
      ));
      if (i + 2 < children.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}
