import 'package:flutter/material.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';

/// Small coloured label showing a role, e.g. [Owner].
class RoleChip extends StatelessWidget {
  const RoleChip({super.key, required this.role});

  final MembershipRole role;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final (background, foreground) = switch (role) {
      MembershipRole.owner => (colors.primaryContainer, colors.onPrimaryContainer),
      MembershipRole.manager => (colors.secondaryContainer, colors.onSecondaryContainer),
      MembershipRole.caretaker => (colors.tertiaryContainer, colors.onTertiaryContainer),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        role.label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(color: foreground),
      ),
    );
  }
}
