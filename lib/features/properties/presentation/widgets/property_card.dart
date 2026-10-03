import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/dashboard/data/dashboard.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/presentation/widgets/role_chip.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/property_photo.dart';

/// A property with its "photo", name, address and occupancy. [compact] is
/// the narrow version for the horizontal list on Home.
class PropertyCard extends StatelessWidget {
  const PropertyCard({
    super.key,
    required this.myProperty,
    required this.onTap,
    this.stats,
    this.compact = false,
  });

  final MyProperty myProperty;
  final PropertyStats? stats;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final property = myProperty.property;
    final text = Theme.of(context).textTheme;
    final s = stats;

    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PropertyPhoto(
            seed: property.id,
            height: compact ? 96 : 150,
            borderRadius: 14,
            child: Align(
              alignment: Alignment.topRight,
              child: RoleChip(role: myProperty.access.role),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  property.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(fontSize: compact ? 14 : 16),
                ),
                if (!compact) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      const Icon(Icons.place_outlined, size: 15, color: AppColors.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          property.address ?? 'No address',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                if (s != null)
                  Text.rich(
                    TextSpan(children: [
                      TextSpan(
                        text: '${s.occupancyPercent}% occupied',
                        style: const TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: compact ? '' : '  ·  ${s.occupied}/${s.apartments} units'),
                      if (!compact && s.overdue > 0)
                        TextSpan(
                          text: '  ·  ${s.overdue} overdue',
                          style: const TextStyle(color: AppColors.overdue, fontWeight: FontWeight.w600),
                        ),
                    ]),
                    style: text.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
