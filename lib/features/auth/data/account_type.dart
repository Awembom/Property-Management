import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// What someone chose at sign-up: "How will you use the app?"
/// (`profiles.account_type`).
///
/// This only guides their first steps (what the empty home screen suggests).
/// What they're ALLOWED to do always comes from their connections: owner /
/// manager / caretaker of a property, or tenant via an invite code.
enum AccountType {
  landlord('landlord', 'Landlord', 'I own or rent out property',
      Icons.apartment_rounded, AppColors.primary),
  tenant('tenant', 'Tenant', 'I rent an apartment',
      Icons.home_rounded, AppColors.accent),
  team('team', 'Team member', 'I help manage a property (manager, caretaker)',
      Icons.engineering_rounded, AppColors.vacant);

  const AccountType(this.value, this.label, this.description, this.icon, this.color);

  /// What the database stores.
  final String value;
  final String label;
  final String description;
  final IconData icon;
  final Color color;

  /// Database value -> enum; null if missing or unknown.
  static AccountType? fromJson(String? value) {
    for (final type in values) {
      if (type.value == value) return type;
    }
    return null;
  }
}
