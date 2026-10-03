import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/tickets/presentation/widgets/ticket_tile.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/rent_status_pill.dart';
import 'package:rental_app/features/tenant_access/data/agreement_text.dart';
import 'package:rental_app/features/tenant_access/data/my_rental_details.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/utils/phone.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/gradient_header.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// A tenant's own rental. The first time, they must accept the tenancy
/// agreement; after that they see when rent is due, how long is left, their
/// rent and their payments.
class MyRentalPage extends ConsumerWidget {
  const MyRentalPage({super.key, required this.tenancyId});

  final String tenancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final details = ref.watch(myRentalDetailsProvider(tenancyId));
    return details.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myRentalDetailsProvider(tenancyId)),
        ),
      ),
      data: (details) => details.tenancy.agreementAcceptedAt == null
          ? _AgreementScreen(details: details)
          : _RentalScreen(details: details),
    );
  }
}

List<(String, String)> _sectionsFor(MyRentalDetails d) => agreementSections(
      propertyName: d.propertyName,
      apartmentName: d.tenancy.apartmentName,
      tenantName: d.tenantName,
      monthlyRent: d.monthlyRent,
      currency: d.currency,
      paymentIntervalMonths: d.tenancy.paymentIntervalMonths,
      startDate: d.tenancy.startDate,
      endDate: d.tenancy.endDate,
      template: d.tenancy.agreementText,
    );

// ------------------------------------------------------------- agreement

class _AgreementScreen extends ConsumerStatefulWidget {
  const _AgreementScreen({required this.details});

  final MyRentalDetails details;

  @override
  ConsumerState<_AgreementScreen> createState() => _AgreementScreenState();
}

class _AgreementScreenState extends ConsumerState<_AgreementScreen> {
  bool _agreed = false;
  bool _busy = false;

  Future<void> _accept() async {
    setState(() => _busy = true);
    try {
      final tenancyId = widget.details.tenancy.id;
      await ref.read(tenantAccessRepositoryProvider).acceptAgreement(tenancyId);
      ref.invalidate(myRentalDetailsProvider(tenancyId));
      ref.invalidate(myRentalsProvider);
      if (mounted) showMessage(context, 'Agreement accepted. Welcome home!');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tenancy agreement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          GradientHeader(
            color: AppColors.primary,
            icon: Icons.description_rounded,
            title: 'Your tenancy agreement',
            subtitle: 'Please read it and accept it to continue.',
          ),
          const SizedBox(height: 16),
          AgreementText(sections: _sectionsFor(widget.details)),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _agreed,
            onChanged: (value) => setState(() => _agreed = value ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            title: const Text('I have read and accept the tenancy agreement'),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _agreed && !_busy ? _accept : null,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: const Text('Accept agreement'),
          ),
        ],
      ),
    );
  }
}

/// The agreement's sections in a card: bold heading, then the text.
class AgreementText extends StatelessWidget {
  const AgreementText({super.key, required this.sections});

  final List<(String, String)> sections;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (heading, body) in sections) ...[
              if (heading.isNotEmpty) ...[
                Text(heading, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
              ],
              Text(body),
              const SizedBox(height: 14),
            ],
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------- details

class _RentalScreen extends ConsumerWidget {
  const _RentalScreen({required this.details});

  final MyRentalDetails details;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tenancy = details.tenancy;
    final currency = details.currency;
    final color = tenancyColor(tenancy);
    final days = daysUntil(tenancy.paidUntil);
    final overdue = days <= 0;

    return Scaffold(
      appBar: AppBar(title: const Text('My home')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(myRentalDetailsProvider(tenancy.id).future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GradientHeader(
              color: color,
              icon: Icons.home_rounded,
              title: 'Apartment ${tenancy.apartmentName}',
              subtitle: [details.propertyName, ?details.propertyAddress].join(' · '),
              trailing: HeaderBadge(label: tenancy.rentStatus?.label ?? 'Active'),
              stats: [
                HeaderStat(
                  value: overdue ? 'Overdue' : timeLeftText(tenancy.paidUntil),
                  label: overdue
                      ? 'by ${timeLeftText(tenancy.paidUntil)}'
                      : 'until rent is due',
                ),
                HeaderStat(value: formatDate(tenancy.paidUntil), label: 'Rent due on'),
              ],
            ),

            if (details.balance > 0) ...[
              const SizedBox(height: 12),
              Card(
                color: AppColors.solidSoft(context, AppColors.overdue),
                child: ListTile(
                  leading: const Icon(Icons.warning_amber_rounded, color: AppColors.overdue),
                  title: Text(
                    'Amount left to pay: ${formatMoney(details.balance, currency)}',
                    style: const TextStyle(color: AppColors.overdue, fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text('From a part payment. Pay it to your landlord.'),
                ),
              ),
            ],

            // The landlord's number, one tap from the phone's dialer.
            if (details.contactPhone case final phone? when phone.trim().isNotEmpty) ...[
              const SizedBox(height: 14),
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
                onTap: () => callNumber(context, phone),
                child: Row(
                  children: [
                    const IconBubble(icon: Icons.call_rounded, color: AppColors.paid, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Call your landlord', style: Theme.of(context).textTheme.titleSmall),
                          Text(formatPhone(phone), style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                    FilledButton(
                      style: FilledButton.styleFrom(backgroundColor: AppColors.paid),
                      onPressed: () => callNumber(context, phone),
                      child: const Text('Call'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.newTicket(tenancy.id)),
                    icon: const Icon(Icons.build_circle_outlined),
                    label: const Text('Report an issue'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.push(AppRoutes.myAnnouncements),
                    icon: const Icon(Icons.campaign_outlined),
                    label: const Text('Notices'), // "Announcements" breaks mid-word on narrow phones
                  ),
                ),
              ],
            ),

            const SectionTitle('My rent'),
            _InfoCard(rows: [
              _InfoRow(
                icon: Icons.savings_rounded,
                color: AppColors.paid,
                label: 'Monthly rent',
                value: '${formatMoney(details.monthlyRent, currency)} per month',
              ),
              _InfoRow(
                icon: Icons.notifications_active_rounded,
                color: AppColors.primary,
                label: 'I pay',
                value: [
                  PaymentInterval.label(tenancy.paymentIntervalMonths),
                  if (tenancy.paymentIntervalMonths > 1)
                    '${formatMoney(details.regularPayment, currency)} each time',
                ].join(' · '),
              ),
              _InfoRow(
                icon: Icons.event_rounded,
                color: color,
                label: 'Next payment',
                value: '${formatMoney(details.regularPayment, currency)} '
                    '${overdue ? 'was due' : 'due'} ${formatDate(tenancy.paidUntil)}',
              ),
              _InfoRow(
                icon: Icons.savings_rounded,
                color: AppColors.paid,
                label: 'Rent paid so far',
                value: formatMoney(
                  details.payments.where((p) => !p.isVoided).fold<int>(0, (sum, p) => sum + p.amount),
                  currency,
                ),
              ),
              _InfoRow(
                icon: Icons.receipt_long_rounded,
                color: AppColors.accent,
                label: 'Bills paid so far',
                value: formatMoney(
                  (ref.watch(myBillsProvider(tenancy.id)).value ?? const [])
                      .where((b) => b.paidAt != null)
                      .fold<int>(0, (sum, b) => sum + b.amount),
                  currency,
                ),
              ),
            ]),

            const SectionTitle('My lease'),
            _InfoCard(rows: [
              _InfoRow(
                icon: Icons.login_rounded,
                color: AppColors.paid,
                label: 'Moved in',
                value: formatDate(tenancy.startDate),
              ),
              _InfoRow(
                icon: Icons.hourglass_bottom_rounded,
                color: AppColors.dueSoon,
                label: 'Lease ends',
                value: tenancy.endDate == null
                    ? 'No end date'
                    : daysUntil(tenancy.endDate!) < 0
                        ? '${formatDate(tenancy.endDate!)} (ended, ask your landlord to renew)'
                        : '${formatDate(tenancy.endDate!)} (${timeLeftText(tenancy.endDate!)} left)',
              ),
              _InfoRow(
                icon: Icons.verified_rounded,
                color: AppColors.primary,
                label: 'Tenancy agreement',
                value: 'Accepted on ${formatDate(tenancy.agreementAcceptedAt!)}',
              ),
            ]),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.85,
                    builder: (context, controller) => ListView(
                      controller: controller,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      children: [AgreementText(sections: _sectionsFor(details))],
                    ),
                  ),
                ),
                icon: const Icon(Icons.description_rounded),
                label: const Text('Read the agreement'),
              ),
            ),

            // Bills, payments and issues have their own tabs at the bottom.
            const SizedBox(height: 8),
            Row(
              children: [
                for (final (icon, label, route) in [
                  (Icons.receipt_rounded, 'Bills', AppRoutes.myBills),
                  (Icons.payments_rounded, 'Payments', AppRoutes.myPayments),
                  (Icons.build_circle_rounded, 'Issues', AppRoutes.myIssues),
                ])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: TextButton.icon(
                        onPressed: () => context.go(route),
                        icon: Icon(icon, size: 18),
                        label: Text(label),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One of my payments; tap to open its receipt. A receipt I should still
/// check (within 24 hours) or one I disputed says so on the right.
class TenantPaymentTile extends ConsumerWidget {
  const TenantPaymentTile({super.key, required this.payment, required this.currency});

  final Payment payment;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final standing = ReceiptStanding.of(
      issuedAt: payment.issuedAt,
      isVoided: payment.isVoided,
      response: payment.response,
      tenantHasAccount: true,
      confirmationQueued: ref.watch(queuedConfirmationsProvider).contains(payment.id),
    );
    final (Color color, String label) = payment.isVoided
        ? (AppColors.ended, 'Cancelled')
        : payment.shortfall > 0
            ? (AppColors.overdue, 'Part paid')
            : (AppColors.paid, 'Paid');
    final Widget pill = switch (standing?.kind) {
      ReceiptStandingKind.awaiting =>
        const StatusPill(label: 'Check it', color: AppColors.dueSoon, icon: Icons.hourglass_top_rounded),
      ReceiptStandingKind.disputed =>
        const StatusPill(label: 'Disputed', color: AppColors.overdue, icon: Icons.report_problem_rounded),
      _ => StatusPill(label: label, color: color),
    };
    return Card(
      child: ListTile(
        onTap: () => context.push(AppRoutes.myReceipt(payment.tenancyId, payment.id)),
        leading: IconBubble(icon: Icons.receipt_long_rounded, color: color, size: 44),
        title: Text(
          formatMoney(payment.amount, currency),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: payment.isVoided ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${payment.receiptNumber} · ${formatDate(payment.paidOn)}\n'
          '${payment.kind == PaymentKind.rent ? 'Rent until ${formatDate(payment.periodEnd!)}' : 'Towards the amount left'}',
        ),
        isThreeLine: true,
        trailing: pill,
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.rows});

  final List<_InfoRow> rows;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(children: rows),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.color, required this.label, required this.value});

  final IconData icon;
  final Color color;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        children: [
          IconBubble(icon: icon, color: color, size: 40),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                Text(value, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The tenant's bills for this home (water, electricity, ...), with status.
class TenantBillsList extends ConsumerWidget {
  const TenantBillsList({super.key, required this.tenancyId, required this.currency});

  final String tenancyId;
  final String currency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final billsValue = ref.watch(myBillsProvider(tenancyId));
    final bills = billsValue.value;
    final text = Theme.of(context).textTheme;
    if (bills == null && billsValue.hasError) {
      return TextButton(
        onPressed: () => ref.invalidate(myBillsProvider(tenancyId)),
        child: const Text('Could not load your bills. Tap to try again.'),
      );
    }
    if (bills == null) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));
    if (bills.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.receipt_long_rounded, color: AppColors.primary),
          title: Text('No bills'),
          subtitle: Text('Water, electricity and other bills from your landlord appear here.'),
        ),
      );
    }
    return Column(
      children: [
        for (final bill in bills)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(bill.title, style: text.titleSmall),
                        Text(
                          '${formatMoney(bill.amount, currency)} · due ${formatDate(bill.dueDate)}',
                          style: text.bodySmall,
                        ),
                        if (bill.notes != null) Text(bill.notes!, style: text.bodySmall),
                        if (bill.waiveReason != null)
                          Text('You don\'t have to pay this: ${bill.waiveReason}', style: text.bodySmall),
                      ],
                    ),
                  ),
                  StatusPill(label: bill.status.label, color: bill.status.color, icon: bill.status.icon),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// The tenant's reported issues for this home.
class TenantTicketsList extends ConsumerWidget {
  const TenantTicketsList({super.key, required this.tenancyId});

  final String tenancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ticketsValue = ref.watch(tenancyTicketsProvider(tenancyId));
    // Reported offline and not sent yet come first.
    final pending = ref.watch(pendingTicketsProvider(tenancyId));
    final tickets = ticketsValue.value == null ? null : [...pending, ...ticketsValue.value!];
    if (tickets == null && ticketsValue.hasError) {
      return TextButton(
        onPressed: () => ref.invalidate(tenancyTicketsProvider(tenancyId)),
        child: const Text('Could not load your issues. Tap to try again.'),
      );
    }
    if (tickets == null) return const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()));
    if (tickets.isEmpty) {
      return const Card(
        child: ListTile(
          leading: Icon(Icons.build_circle_outlined, color: AppColors.accent),
          title: Text('No issues reported'),
          subtitle: Text('Something broken? Tap "Report" and your landlord will see it.'),
        ),
      );
    }
    return Column(
      children: [
        for (final ticket in tickets)
          Padding(padding: const EdgeInsets.only(bottom: 10), child: TicketTile(ticket: ticket)),
      ],
    );
  }
}
