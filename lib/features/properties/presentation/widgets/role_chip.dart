import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';

/// Small rounded label showing a role, e.g. [Owner].
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final MembershipRole role;

  @override
  Widget build(BuildContext context) {
    final color = switch (role) {
      MembershipRole.owner => AppColors.primary,
      MembershipRole.manager => AppColors.accent,
      MembershipRole.caretaker => AppColors.paid,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        role.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}
