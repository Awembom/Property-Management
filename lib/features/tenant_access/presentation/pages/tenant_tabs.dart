import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/receipts/providers/receipts_providers.dart';
import 'package:rental_app/features/tenant_access/data/my_rental.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/my_rental_page.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';
import 'package:rental_app/shared/widgets/section_title.dart';

// The tenant's Bills, Payments and Issues tabs. Each shows one list for all
// the homes they rent (usually one), so nothing is buried in a long page.

/// Shared frame: loads my rentals, then builds the list for each one. With
/// more than one home, each gets a heading.
class _TenantTab extends ConsumerWidget {
  const _TenantTab({
    required this.title,
    required this.forRental,
    required this.onRefresh,
    this.floatingActionButton,
  });

  final String title;
  final List<Widget> Function(MyRental rental) forRental;
  final void Function(WidgetRef ref, List<MyRental> rentals) onRefresh;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rentals = ref.watch(myRentalsProvider);
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      floatingActionButton: floatingActionButton,
      body: rentals.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myRentalsProvider),
        ),
        data: (rentals) {
          if (rentals.isEmpty) {
            return EmptyState(
              icon: Icons.vpn_key_rounded,
              color: AppColors.accent,
              title: 'Connect to your home',
              message: 'Enter the invite code from your landlord first.',
              actionLabel: 'Enter invite code',
              onAction: () => context.push(AppRoutes.joinWithCode),
            );
          }
          return RefreshIndicator(
            onRefresh: () {
              onRefresh(ref, rentals);
              return ref.refresh(myRentalsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final rental in rentals) ...[
                  if (rentals.length > 1)
                    SectionTitle(
                      'Apartment ${rental.tenancy.apartmentName} · ${rental.propertyName}',
                    ),
                  ...forRental(rental),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Bills tab: what's left to pay, then every bill.
class MyBillsTab extends StatelessWidget {
  const MyBillsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _TenantTab(
      title: 'My bills',
      onRefresh: (ref, rentals) {
        ref.invalidate(myHomeBillsProvider);
        for (final r in rentals) {
          ref.invalidate(myBillsProvider(r.tenancy.id));
        }
      },
      forRental: (rental) => [
        _BillsTotal(tenancyId: rental.tenancy.id, currency: rental.currency),
        TenantBillsList(
          tenancyId: rental.tenancy.id,
          currency: rental.currency,
        ),
      ],
    );
  }
}

/// What's left to pay and what was paid so far, above a home's bills.
class _BillsTotal extends ConsumerWidget {
  const _BillsTotal({required this.tenancyId, required this.currency});

  final String tenancyId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bills = ref.watch(myBillsProvider(tenancyId)).value ?? const [];
    if (bills.isEmpty) return const SizedBox.shrink();
    final unpaid = bills.where((b) => b.isOpen).toList();
    final toPay = unpaid.fold<int>(0, (sum, b) => sum + b.amount);
    final paid = bills.where((b) => b.paidAt != null).fold<int>(0, (sum, b) => sum + b.amount);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: TotalCard(
                label: 'To pay',
                value: formatMoney(toPay, currency),
                detail: unpaid.isEmpty ? 'All paid' : '${unpaid.length} unpaid',
                color: unpaid.isEmpty ? AppColors.paid : AppColors.dueSoon,
                icon: Icons.receipt_long_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TotalCard(
                label: 'Bills paid so far',
                value: formatMoney(paid, currency),
                color: AppColors.paid,
                icon: Icons.check_circle_rounded,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Payments tab: my payments, newest first; tap one for its receipt.
class MyPaymentsTab extends StatelessWidget {
  const MyPaymentsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return _TenantTab(
      title: 'My payments',
      onRefresh: (ref, rentals) {
        ref.invalidate(receiptsToCheckProvider);
        for (final r in rentals) {
          ref.invalidate(myRentalDetailsProvider(r.tenancy.id));
        }
      },
      forRental: (rental) => [_Payments(tenancyId: rental.tenancy.id)],
    );
  }
}

class _Payments extends ConsumerWidget {
  const _Payments({required this.tenancyId});

  final String tenancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(myRentalDetailsProvider(tenancyId));
    return details.when(
      loading: () => const SizedBox(
        height: 60,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => AsyncErrorView(
        error: error,
        onRetry: () => ref.invalidate(myRentalDetailsProvider(tenancyId)),
      ),
      data: (d) {
        final paid = d.payments.where((p) => !p.isVoided).toList();
        return Column(
          children: [
            TotalCard(
              label: 'Total rent paid',
              value: formatMoney(paid.fold<int>(0, (sum, p) => sum + p.amount), d.currency),
              detail: '${paid.length} payment${paid.length == 1 ? '' : 's'} since ${formatDate(d.tenancy.startDate)}',
              color: AppColors.paid,
              icon: Icons.savings_rounded,
            ),
            const SizedBox(height: 12),
            if (d.balance > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: AppCard(
                  color: AppColors.solidSoft(context, AppColors.overdue),
                  child: Text(
                    'Amount left to pay: ${formatMoney(d.balance, d.currency)}',
                    style: const TextStyle(color: AppColors.overdue, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            if (d.payments.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.receipt_long_rounded, color: AppColors.primary),
                  title: Text('No payments yet'),
                  subtitle: Text('Payments your landlord records appear here, with their receipts.'),
                ),
              )
            else
              for (final payment in d.payments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TenantPaymentTile(payment: payment, currency: d.currency),
                ),
          ],
        );
      },
    );
  }
}

/// Issues tab: what I reported, and a button to report something new.
class MyIssuesTab extends ConsumerWidget {
  const MyIssuesTab({super.key});

  /// One home: straight to the form. Several: ask which one first.
  Future<void> _report(BuildContext context, List<MyRental> rentals) async {
    if (rentals.isEmpty) return;
    var rental = rentals.first;
    if (rentals.length > 1) {
      final chosen = await showModalBottomSheet<MyRental>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(title: Text('Which home is it about?')),
              for (final r in rentals)
                ListTile(
                  leading: const Icon(Icons.home_rounded),
                  title: Text('Apartment ${r.tenancy.apartmentName}'),
                  subtitle: Text(r.propertyName),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ],
          ),
        ),
      );
      if (chosen == null) return;
      rental = chosen;
    }
    if (context.mounted) context.push(AppRoutes.newTicket(rental.tenancy.id));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rentals = ref.watch(myRentalsProvider).value ?? const <MyRental>[];
    return _TenantTab(
      title: 'My issues',
      floatingActionButton: rentals.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _report(context, rentals),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Report an issue'),
            ),
      onRefresh: (ref, rentals) {
        for (final r in rentals) {
          ref.invalidate(tenancyTicketsProvider(r.tenancy.id));
        }
      },
      forRental: (rental) => [TenantTicketsList(tenancyId: rental.tenancy.id)],
    );
  }
}

/// A total, e.g. "Total rent paid · XAF 450,000 · 3 payments".
class TotalCard extends StatelessWidget {
  const TotalCard({
    super.key,
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
    this.detail,
  });

  final String label;
  final String value;
  final Color color;
  final IconData icon;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          IconBubble(icon: icon, color: color, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.bodySmall),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: text.titleMedium?.copyWith(color: color, fontWeight: FontWeight.w700)),
                ),
                if (detail != null) Text(detail!, style: text.bodySmall, maxLines: 2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
