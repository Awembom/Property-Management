import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/features/dashboard/data/dashboard.dart';
import 'package:rental_app/features/dashboard/data/dashboard_repository.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';

/// Overview numbers for all my properties (Home and Properties tabs).
/// Reloads whenever my list of properties reloads.
final dashboardProvider = FutureProvider.autoDispose<Dashboard>((ref) async {
  final properties = await ref.watch(myPropertiesProvider.future);
  return ref.watch(dashboardRepositoryProvider).fetchDashboard(properties);
});

/// One thing on the Home tab's "Needs attention" list (besides late rent).
class AttentionItem {
  const AttentionItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.route,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  /// Where tapping it goes.
  final String route;
}

/// Receipt disputes, open issues and overdue bills across my properties,
/// most urgent first. (Late rent comes from the dashboard itself.)
final attentionItemsProvider = FutureProvider.autoDispose<List<AttentionItem>>((ref) async {
  final properties = await ref.watch(myPropertiesProvider.future);
  final disputes = <AttentionItem>[];
  final issues = <AttentionItem>[];
  final bills = <AttentionItem>[];
  for (final my in properties) {
    final id = my.property.id;
    final name = my.property.name;
    try {
      final tickets = await ref.watch(propertyTicketsProvider(id).future);
      for (final t in tickets) {
        if (t.status == TicketStatus.resolved) continue;
        if (t.category == TicketCategory.receipt) {
          disputes.add(AttentionItem(
            icon: Icons.report_problem_rounded,
            color: AppColors.overdue,
            title: 'Receipt disputed: ${t.title}',
            subtitle: [name, if (t.apartmentName != null) 'Unit ${t.apartmentName}'].join(' · '),
            route: AppRoutes.ticket(t.id),
          ));
        }
      }
      final open = tickets.where((t) => t.status != TicketStatus.resolved && t.category != TicketCategory.receipt);
      if (open.isNotEmpty) {
        issues.add(AttentionItem(
          icon: Icons.build_circle_rounded,
          color: AppColors.dueSoon,
          title: open.length == 1 ? '1 open issue: ${open.first.title}' : '${open.length} open issues',
          subtitle: name,
          route: AppRoutes.propertyTickets(id),
        ));
      }
    } catch (_) {
      // Not loaded (e.g. offline and never opened): leave it out.
    }
    try {
      for (final bill in await ref.watch(propertyBillsProvider(id).future)) {
        if (bill.status != BillStatus.overdue) continue;
        final unpaid = bill.assignments.length - bill.settledCount;
        bills.add(AttentionItem(
          icon: Icons.receipt_long_rounded,
          color: AppColors.overdue,
          title: '${bill.title}: $unpaid unit${unpaid == 1 ? '' : 's'} not paid',
          subtitle: '$name · was due ${formatDate(bill.dueDate)}',
          route: AppRoutes.bill(id, bill.id),
        ));
      }
    } catch (_) {
      // As above.
    }
  }
  return [...disputes, ...issues, ...bills];
});
