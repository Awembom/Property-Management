import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// The big colourful card at the top of a screen: an icon, a title, an
/// optional subtitle, and optional [stats] shown as a row of numbers.
class GradientHeader extends StatelessWidget {
  const GradientHeader({
    super.key,
    required this.color,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.stats = const [],
  });

  final Color color;
  final IconData icon;
  final String title;
  final String? subtitle;

  /// Shown at the top-right, e.g. a role or status label.
  final Widget? trailing;
  final List<HeaderStat> stats;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.gradientFor(color),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              const Spacer(),
              ?trailing, // "?" = only added when not null
            ],
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: text.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: text.bodyMedium?.copyWith(color: Colors.white.withValues(alpha: 0.9)),
            ),
          ],
          if (stats.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                for (final stat in stats) Expanded(child: stat),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// One number + label inside a [GradientHeader], e.g. "5 / Apartments".
class HeaderStat extends StatelessWidget {
  const HeaderStat({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: text.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        Text(
          label,
          style: text.labelMedium?.copyWith(color: Colors.white.withValues(alpha: 0.85)),
        ),
      ],
    );
  }
}

/// A white, semi-transparent label for use on top of a [GradientHeader].
class HeaderBadge extends StatelessWidget {
  const HeaderBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}
