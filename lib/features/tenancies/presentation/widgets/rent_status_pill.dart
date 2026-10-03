import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// The colour that represents a tenancy: its rent status, or grey if ended.
Color tenancyColor(TenancyOverview tenancy) {
  if (!tenancy.isActive) return AppColors.ended;
  return tenancy.rentStatus?.color ?? AppColors.paid;
}

/// "Paid" / "Due soon" / "Overdue" in colour, or a grey "Ended".
class RentStatusPill extends StatelessWidget {
  const RentStatusPill({super.key, required this.tenancy});

  final TenancyOverview tenancy;

  @override
  Widget build(BuildContext context) {
    final status = tenancy.rentStatus;
    if (!tenancy.isActive || status == null) {
      return const StatusPill(
        label: 'Ended',
        color: AppColors.ended,
        icon: Icons.history_rounded,
      );
    }
    return StatusPill(
      label: status.label,
      color: status.color,
      icon: status.icon,
    );
  }
}

/// One line about when rent is due, e.g. "Next rent due 1 Nov 2026 (in 31 days)".
/// `paid_until` is the first day NOT covered, so it's the next due date.
String rentDueText(TenancyOverview tenancy) {
  final date = formatDate(tenancy.paidUntil);
  final when = relativeDays(tenancy.paidUntil);
  if (daysUntil(tenancy.paidUntil) <= 0) return 'Rent was due $date ($when)';
  return 'Next rent due $date ($when)';
}
