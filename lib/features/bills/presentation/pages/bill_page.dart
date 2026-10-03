import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/presentation/widgets/bill_part_menu.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/stat_card.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// One bill: totals, and each apartment's part, which can be marked paid
/// (owners, managers, caretakers allowed to record payments).
class BillPage extends ConsumerWidget {
  const BillPage({super.key, required this.propertyId, required this.billId});

  final String propertyId;
  final String billId;

  void _reload(WidgetRef ref) {
    ref.invalidate(billProvider(billId));
    ref.invalidate(propertyBillsProvider(propertyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billValue = ref.watch(billProvider(billId));
    final my = ref.watch(myPropertyProvider(propertyId)).value;
    final currency = my?.property.currency ?? '';
    final canMark = my?.access.canRecordPayments ?? false;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Bill')),
      body: billValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(error: error, onRetry: () => ref.invalidate(billProvider(billId))),
        data: (bill) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text(bill.title, style: text.headlineSmall),
            const SizedBox(height: 4),
            Text('Due ${formatDate(bill.dueDate)}', style: text.bodyMedium?.copyWith(color: AppColors.muted)),
            if (bill.notes != null) ...[const SizedBox(height: 6), Text(bill.notes!)],
            const SizedBox(height: 16),
            StatGrid(children: [
              StatCard(
                icon: Icons.check_circle_rounded,
                label: 'Paid',
                value: '${bill.paidCount}/${bill.assignments.length}',
                highlight: true,
                color: AppColors.paid,
              ),
              StatCard(
                icon: Icons.payments_rounded,
                label: 'Collected',
                value: formatMoney(bill.collected, currency),
                color: AppColors.accent,
              ),
            ]),
            const SizedBox(height: 18),
            Text('Apartments', style: text.titleSmall),
            const SizedBox(height: 8),
            for (final a in bill.assignments)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Builder(builder: (context) {
                  final status = BillStatus.of(paidAt: a.paidAt, dueDate: bill.dueDate, waivedAt: a.waivedAt);
                  return AppCard(
                    padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Unit ${a.apartmentName ?? '?'}', style: text.titleSmall),
                              Text(
                                [a.tenantName ?? '', formatMoney(a.amount, currency)].join(' · '),
                                style: text.bodySmall,
                              ),
                              if (a.waiveReason != null)
                                Text('Waived: ${a.waiveReason}', style: text.bodySmall),
                            ],
                          ),
                        ),
                        StatusPill(label: status.label, color: status.color),
                        if (canMark)
                          BillPartMenu(
                            assignmentId: a.id,
                            isPaid: a.isPaid,
                            isWaived: a.isWaived,
                            onChanged: () => _reload(ref),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            if (canMark)
              Text(
                'Use ⋮ to mark an apartment paid, or to waive its part.',
                style: text.bodySmall,
                textAlign: TextAlign.center,
              ),
          ],
        ),
      ),
    );
  }
}
