import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// Whether an active tenancy's rent is paid, due soon or overdue.
///
/// Computed by the database from `paid_until` and the property's grace period
/// (the `rent_status()` function, shown in the `tenancy_overview` view), never
/// stored or set by hand (CLAUDE.md, business rule 1).
enum RentStatus {
  paid,
  dueSoon,
  overdue;

  /// Database text ('paid', 'due_soon', 'overdue') -> enum.
  static RentStatus fromJson(String value) => switch (value) {
    'paid' => RentStatus.paid,
    'due_soon' => RentStatus.dueSoon,
    'overdue' => RentStatus.overdue,
    _ => throw ArgumentError('Unknown rent status: $value'),
  };

  String get label => switch (this) {
    RentStatus.paid => 'Paid',
    RentStatus.dueSoon => 'Due soon',
    RentStatus.overdue => 'Overdue',
  };

  Color get color => switch (this) {
    RentStatus.paid => AppColors.paid,
    RentStatus.dueSoon => AppColors.dueSoon,
    RentStatus.overdue => AppColors.overdue,
  };

  IconData get icon => switch (this) {
    RentStatus.paid => Icons.check_circle_rounded,
    RentStatus.dueSoon => Icons.schedule_rounded,
    RentStatus.overdue => Icons.error_rounded,
  };
}
