import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// A property's bills (water, electricity, custom), newest first, with how
/// many apartments paid. "New bill"; "Bill types" for those who set them up.
class BillsPage extends ConsumerWidget {
  const BillsPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(propertyBillsProvider(propertyId));
    final my = ref.watch(myPropertyProvider(propertyId)).value;
    final currency = my?.property.currency ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bills'),
        actions: [
          if (my?.access.canManageBillTypes ?? false)
            IconButton(
              tooltip: 'Bill types',
              icon: const Icon(Icons.tune_rounded),
              onPressed: () => context.push(AppRoutes.billTypes(propertyId)),
            ),
        ],
      ),
      body: bills.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            AsyncErrorView(error: error, onRetry: () => ref.invalidate(propertyBillsProvider(propertyId))),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(propertyBillsProvider(propertyId).future),
          child: list.isEmpty
              ? ListView(children: const [
                  EmptyState(
                    icon: Icons.receipt_long_rounded,
                    color: AppColors.primary,
                    title: 'No bills yet',
                    message: 'Create a water, electricity or custom bill for all '
                        'occupied apartments or just some. Tenants see theirs in the app.',
                  ),
                ])
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: list.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final bill = list[index];
                    final text = Theme.of(context).textTheme;
                    return AppCard(
                      padding: const EdgeInsets.all(14),
                      onTap: () => context.push(AppRoutes.bill(propertyId, bill.id)),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.soft(bill.status.color),
                            ),
                            child: Icon(Icons.receipt_long_rounded, color: bill.status.color, size: 22),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(bill.title, style: text.titleSmall),
                                Text(
                                  'Due ${formatDate(bill.dueDate)} · ${bill.paidCount}/${bill.assignments.length} paid'
                                  '${bill.settledCount > bill.paidCount ? ' · ${bill.settledCount - bill.paidCount} waived' : ''}',
                                  style: text.bodySmall,
                                ),
                                Text(
                                  '${formatMoney(bill.collected, currency)} of ${formatMoney(bill.total, currency)}',
                                  style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                          StatusPill(label: bill.status.label, color: bill.status.color),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newBill(propertyId)),
        icon: const Icon(Icons.add),
        label: const Text('New bill'),
      ),
    );
  }
}
