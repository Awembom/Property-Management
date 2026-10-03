import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/presentation/widgets/apartment_look.dart';
import 'package:rental_app/features/apartments/presentation/widgets/apartment_sheet.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/rent_status_pill.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/gradient_header.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/utils/phone.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';
import 'package:rental_app/features/bills/presentation/widgets/bill_part_menu.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/repairs/data/repair.dart';
import 'package:rental_app/features/repairs/data/repairs_repository.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/presentation/widgets/ticket_tile.dart';

/// One unit, everything in one place: who lives there, quick actions
/// (message, bill, payment, call, repair), its issues, bills and repairs, its
/// tenancy agreement, and who lived there before.
class ApartmentDetailPage extends ConsumerWidget {
  const ApartmentDetailPage({
    super.key,
    required this.propertyId,
    required this.apartmentId,
  });

  final String propertyId;
  final String apartmentId;

  void _reload(WidgetRef ref) {
    ref.invalidate(apartmentProvider(apartmentId));
    ref.invalidate(apartmentTenanciesProvider(apartmentId));
    ref.invalidate(unitTicketsProvider(apartmentId));
    ref.invalidate(unitBillsProvider(apartmentId));
    ref.invalidate(unitRepairsProvider(apartmentId));
  }

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Apartment apartment,
    String currency,
  ) async {
    final result = await showApartmentSheet(
      context,
      propertyId: propertyId,
      currency: currency,
      existing: apartment,
    );
    if (result == null || !context.mounted) return;
    ref.invalidate(apartmentsProvider(propertyId));
    if (result == ApartmentSheetResult.deleted) {
      showMessage(context, '${apartment.name} deleted');
      context.pop();
    } else {
      ref.invalidate(apartmentProvider(apartmentId));
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId)).value;
    final access = myProperty?.access;
    final currency = myProperty?.property.currency;
    final apartmentValue = ref.watch(apartmentProvider(apartmentId));
    final tenanciesValue = ref.watch(apartmentTenanciesProvider(apartmentId));

    // Show the page once both pieces of data have arrived.
    final Widget body;
    final error = apartmentValue.error ?? tenanciesValue.error;
    if (error != null) {
      body = AsyncErrorView(error: error, onRetry: () => _reload(ref));
    } else if (!apartmentValue.hasValue || !tenanciesValue.hasValue) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      final apartment = apartmentValue.requireValue;
      final tenancies = tenanciesValue.requireValue;
      final active = tenancies.where((t) => t.isActive).firstOrNull;
      final past = tenancies.where((t) => !t.isActive).toList();
      final look = apartmentLook(
        ApartmentWithTenancy(apartment: apartment, activeTenancy: active),
      );

      body = RefreshIndicator(
        onRefresh: () async {
          _reload(ref);
          await ref.read(apartmentTenanciesProvider(apartmentId).future);
        },
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GradientHeader(
              color: look.color,
              icon: Icons.door_front_door_rounded,
              title: apartment.name,
              subtitle: apartment.description,
              trailing: HeaderBadge(
                label: active == null ? 'Vacant' : 'Occupied',
              ),
              // Owners and managers see the standard rent; caretakers never
              // receive it from the database.
              stats: [
                if (currency != null && (access?.canSeeMoney ?? false)) ...[
                  HeaderStat(
                    value: apartment.monthlyRent == null
                        ? 'Not set'
                        : formatMoney(apartment.monthlyRent!, currency),
                    label: 'Standard monthly rent',
                  ),
                  // All rent the current tenant has paid (voided payments don't count).
                  if (active != null)
                    HeaderStat(
                      value: formatMoney(
                        (ref.watch(tenancyPaymentsProvider(active.id)).value ?? const [])
                            .where((p) => !p.isVoided)
                            .fold<int>(0, (sum, p) => sum + p.amount),
                        currency,
                      ),
                      label: 'Collected from ${active.tenantName.split(' ').first}',
                    ),
                ],
              ],
            ),
            const SectionTitle('Current tenant'),
            if (active != null) ...[
              _CurrentTenancyCard(
                tenancy: active,
                onTap: () => context.push(
                  AppRoutes.tenancyDetail(propertyId, active.id),
                ),
              ),
              const SizedBox(height: 12),
              _QuickActions(propertyId: propertyId, apartmentId: apartmentId, tenancy: active),
              const SizedBox(height: 4),
              _RentReminders(propertyId: propertyId, apartmentId: apartmentId, tenancy: active),
            ] else
              _VacantCard(
                canStartTenancy: access?.canManageTenancies ?? false,
                onStart: () => context.push(
                  AppRoutes.startTenancy(propertyId, apartmentId),
                ),
              ),

            _UnitIssues(apartmentId: apartmentId),
            if (currency != null)
              _UnitBills(
                propertyId: propertyId,
                apartmentId: apartmentId,
                currency: currency,
                canMark: access?.canRecordPayments ?? false,
              ),
            _UnitRepairs(
              propertyId: propertyId,
              apartmentId: apartmentId,
              currency: currency ?? '',
            ),

            const SectionTitle('Tenancy agreement'),
            Card(
              child: ListTile(
                leading: const IconBubble(icon: Icons.description_rounded, color: AppColors.primary, size: 40),
                title: Text(apartment.agreementText == null ? 'Same as the property' : 'Own agreement for this unit'),
                subtitle: Text((access?.canManageApartments ?? false) ? 'Tap to view or change' : 'Tap to view'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.unitAgreement(propertyId, apartmentId)),
              ),
            ),

            if (past.isNotEmpty) ...[
              SectionTitle('Past tenants (${past.length})'),
              for (final tenancy in past)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _PastTenancyCard(
                    tenancy: tenancy,
                    onTap: () => context.push(
                      AppRoutes.tenancyDetail(propertyId, tenancy.id),
                    ),
                  ),
                ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(apartmentValue.value?.name ?? 'Apartment'),
        actions: [
          if ((access?.canManageApartments ?? false) &&
              apartmentValue.hasValue &&
              currency != null)
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_rounded),
              onPressed: () =>
                  _edit(context, ref, apartmentValue.requireValue, currency),
            ),
        ],
      ),
      body: body,
    );
  }
}

/// Round buttons under the current tenant: message, bill, record payment,
/// call, log a repair. Each only if my permissions allow it.
class _QuickActions extends ConsumerWidget {
  const _QuickActions({required this.propertyId, required this.apartmentId, required this.tenancy});

  final String propertyId;
  final String apartmentId;
  final TenancyOverview tenancy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(myPropertyProvider(propertyId)).value?.access;
    final details = ref.watch(tenancyDetailsProvider((propertyId: propertyId, tenancyId: tenancy.id))).value;
    final phone = details?.tenant.phone;
    final late = tenancy.rentStatus == RentStatus.overdue || tenancy.rentStatus == RentStatus.dueSoon;
    final actions = [
      // Late rent: "Remind" sends a rent reminder notification now.
      if (late)
        (Icons.notifications_active_rounded, 'Remind', AppColors.overdue,
            () => sendRentReminderNow(context, ref, tenancy, details?.money,
                ref.read(myPropertyProvider(propertyId)).value?.property.currency))
      else
        (Icons.chat_rounded, 'Message', AppColors.accent,
            () => context.push(AppRoutes.messageTenant(propertyId, tenancy.tenantId))),
      (Icons.receipt_long_rounded, 'Bill', AppColors.primary,
          () => context.push(AppRoutes.billForUnit(propertyId, tenancy.id))),
      if (access?.canRecordPayments ?? false)
        (Icons.payments_rounded, 'Rent', AppColors.paid,
            () => context.push(AppRoutes.recordPayment(propertyId, tenancy.id))),
      if (phone != null && phone.trim().isNotEmpty)
        (Icons.call_rounded, 'Call', AppColors.paid, () => callNumber(context, phone)),
      (Icons.handyman_rounded, 'Repair', AppColors.dueSoon,
          () => context.push(AppRoutes.newRepair(propertyId, apartmentId))),
    ];
    final text = Theme.of(context).textTheme;
    // Equal shares of the width, so five buttons fit on small phones too.
    return Row(
      children: [
        for (final (icon, label, color, onTap) in actions)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  children: [
                    IconBubble(icon: icon, color: color, size: 46),
                    const SizedBox(height: 4),
                    Text(label, style: text.labelMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Asks, then sends the unit's tenant a rent reminder notification now.
Future<void> sendRentReminderNow(
  BuildContext context,
  WidgetRef ref,
  TenancyOverview tenancy,
  TenancyMoney? money,
  String? currency,
) async {
  final name = tenancy.tenantName.split(' ').first;
  if (!tenancy.tenantHasAccount) {
    showError(context, StateError('$name hasn\'t joined the app yet, so they can\'t get notifications. '
        'Give them their invite code, or call or message them.'));
    return;
  }
  final ok = await showConfirmDialog(
    context,
    title: 'Send $name a rent reminder?',
    message: 'They get a notification on their phone:\n\n"${rentReminderText(tenancy, money, currency)}"',
    confirmLabel: 'Send',
  );
  if (!ok || !context.mounted) return;
  try {
    await ref.read(notificationsRepositoryProvider).sendRentReminder(tenancy.id);
    if (context.mounted) showMessage(context, 'Reminder sent to $name');
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

/// Automatic rent reminders for this unit: on, or paused for a while; plus
/// "send one now".
class _RentReminders extends ConsumerWidget {
  const _RentReminders({required this.propertyId, required this.apartmentId, required this.tenancy});

  final String propertyId;
  final String apartmentId;
  final TenancyOverview tenancy;

  Future<void> _pause(BuildContext context, WidgetRef ref, int days) async {
    try {
      final until = await ref.read(notificationsRepositoryProvider).setRemindersPaused(tenancy.id, days);
      ref.invalidate(apartmentTenanciesProvider(apartmentId));
      ref.invalidate(apartmentsProvider(propertyId));
      if (context.mounted) {
        showMessage(context, until == null ? 'Rent reminders are on again' : 'Paused until ${formatDate(until)}');
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final paused = tenancy.remindersPaused;
    final (title, subtitle, color) = !tenancy.tenantHasAccount
        ? (
            'No rent reminders yet',
            '${tenancy.tenantName.split(' ').first} hasn\'t joined the app, so notifications can\'t reach them.',
            AppColors.ended,
          )
        : paused
            ? ('Rent reminders paused', 'Until ${formatDate(tenancy.remindersPausedUntil!)}.', AppColors.dueSoon)
            : (
                'Rent reminders on',
                '1 month and 5 days before, on the due date, then every 3 days.',
                AppColors.paid,
              );
    return AppCard(
      padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
      child: Row(
        children: [
          IconBubble(
            icon: paused ? Icons.notifications_paused_rounded : Icons.notifications_active_rounded,
            color: color,
            size: 40,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                Text(subtitle, style: text.bodySmall),
              ],
            ),
          ),
          if (tenancy.tenantHasAccount)
            PopupMenuButton<int>(
              tooltip: 'Rent reminders',
              onSelected: (choice) {
                if (choice < 0) {
                  final my = ref.read(myPropertyProvider(propertyId)).value;
                  final money = ref
                      .read(tenancyDetailsProvider((propertyId: propertyId, tenancyId: tenancy.id)))
                      .value
                      ?.money;
                  sendRentReminderNow(context, ref, tenancy, money, my?.property.currency);
                } else {
                  _pause(context, ref, choice);
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: -1, child: Text('Send a reminder now')),
                const PopupMenuItem(value: 7, child: Text('Pause for a week')),
                const PopupMenuItem(value: 30, child: Text('Pause for a month')),
                if (paused) const PopupMenuItem(value: 0, child: Text('Turn back on')),
              ],
            ),
        ],
      ),
    );
  }
}

/// The words of a rent reminder sent now, the same as the tenant receives
/// (rent_reminder_text in the database, 'manual'). The amount is left out
/// of the preview for staff who may not see money.
String rentReminderText(TenancyOverview tenancy, TenancyMoney? money, String? currency) {
  final amount = money == null || currency == null
      ? null
      : formatMoney(money.monthlyRent * tenancy.paymentIntervalMonths, currency);
  final days = -daysUntil(tenancy.paidUntil); // > 0: overdue by that many days
  final unit = tenancy.apartmentName;
  final due = formatDate(tenancy.paidUntil);
  if (days > 0) {
    return 'Your rent for apartment $unit was due on $due ($days day${days == 1 ? '' : 's'} ago). '
        'Please pay ${amount ?? 'it'} as soon as you can.';
  }
  if (days == 0) return 'Your rent for apartment $unit is due today${amount == null ? '' : ': $amount'}.';
  return 'Your rent for apartment $unit is due on $due${amount == null ? '' : ': $amount'}.';
}

/// Shows the first [initial] items, with "Show all (n)" for the rest, so the
/// page stays short.
class _ShortList extends StatefulWidget {
  const _ShortList({required this.children});

  final List<Widget> children;
  static const initial = 3;

  @override
  State<_ShortList> createState() => _ShortListState();
}

class _ShortListState extends State<_ShortList> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final items = widget.children;
    final shown = _all ? items : items.take(_ShortList.initial).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final item in shown) Padding(padding: const EdgeInsets.only(bottom: 10), child: item),
        if (items.length > _ShortList.initial)
          TextButton(
            onPressed: () => setState(() => _all = !_all),
            child: Text(_all ? 'Show less' : 'Show all (${items.length})'),
          ),
      ],
    );
  }
}

/// Issues the unit's tenants reported, open ones first.
class _UnitIssues extends ConsumerWidget {
  const _UnitIssues({required this.apartmentId});

  final String apartmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(unitTicketsProvider(apartmentId));
    final tickets = [...?value.value]
      ..sort((a, b) => (a.status == TicketStatus.resolved ? 1 : 0) - (b.status == TicketStatus.resolved ? 1 : 0));
    final open = tickets.where((t) => t.status != TicketStatus.resolved).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(open == 0 ? 'Issues' : 'Issues ($open open)'),
        if (value.hasError && !value.hasValue)
          TextButton(
            onPressed: () => ref.invalidate(unitTicketsProvider(apartmentId)),
            child: const Text('Could not load the issues. Tap to try again.'),
          )
        else if (tickets.isEmpty)
          _Empty(icon: Icons.build_circle_outlined, text: value.isLoading ? 'Loading…' : 'No issues reported')
        else
          _ShortList(children: [for (final t in tickets) TicketTile(ticket: t)]),
      ],
    );
  }
}

/// Every bill the unit got; staff who may record payments can mark one
/// paid or waive it right here.
class _UnitBills extends ConsumerWidget {
  const _UnitBills({
    required this.propertyId,
    required this.apartmentId,
    required this.currency,
    required this.canMark,
  });

  final String propertyId;
  final String apartmentId;
  final String currency;
  final bool canMark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(unitBillsProvider(apartmentId));
    final bills = value.value ?? const <MyBill>[];
    final open = bills.where((b) => b.isOpen).toList();
    final toPay = open.fold<int>(0, (sum, b) => sum + b.amount);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(open.isEmpty ? 'Bills' : 'Bills · ${formatMoney(toPay, currency)} to pay'),
        if (value.hasError && !value.hasValue)
          TextButton(
            onPressed: () => ref.invalidate(unitBillsProvider(apartmentId)),
            child: const Text('Could not load the bills. Tap to try again.'),
          )
        else if (bills.isEmpty)
          _Empty(icon: Icons.receipt_long_outlined, text: value.isLoading ? 'Loading…' : 'No bills yet')
        else
          _ShortList(children: [
            for (final bill in bills)
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
                onTap: bill.billId == null ? null : () => context.push(AppRoutes.bill(propertyId, bill.billId!)),
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
                          if (bill.waiveReason != null) Text('Waived: ${bill.waiveReason}', style: text.bodySmall),
                        ],
                      ),
                    ),
                    StatusPill(label: bill.status.label, color: bill.status.color),
                    if (canMark)
                      BillPartMenu(
                        assignmentId: bill.assignmentId,
                        isPaid: bill.paidAt != null,
                        isWaived: bill.waivedAt != null,
                        onChanged: () {
                          ref.invalidate(unitBillsProvider(apartmentId));
                          ref.invalidate(propertyBillsProvider(propertyId));
                        },
                      )
                    else
                      const SizedBox(width: 10),
                  ],
                ),
              ),
          ]),
      ],
    );
  }
}

/// The unit's repair history, with "Log a repair".
class _UnitRepairs extends ConsumerWidget {
  const _UnitRepairs({required this.propertyId, required this.apartmentId, required this.currency});

  final String propertyId;
  final String apartmentId;
  final String currency;

  Future<void> _delete(BuildContext context, WidgetRef ref, Repair repair) async {
    final ok = await showConfirmDialog(
      context,
      title: 'Remove this repair?',
      message: '"${repair.title}" is removed from the history. A bill made for it stays (waive it if needed).',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(repairsRepositoryProvider).delete(repair.id);
      ref.invalidate(unitRepairsProvider(apartmentId));
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(unitRepairsProvider(apartmentId));
    final repairs = value.value ?? const <Repair>[];
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionTitle(
          'Repair history',
          trailing: TextButton.icon(
            onPressed: () => context.push(AppRoutes.newRepair(propertyId, apartmentId)),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Log a repair'),
          ),
        ),
        if (value.hasError && !value.hasValue)
          TextButton(
            onPressed: () => ref.invalidate(unitRepairsProvider(apartmentId)),
            child: const Text('Could not load the repairs. Tap to try again.'),
          )
        else if (repairs.isEmpty)
          _Empty(icon: Icons.handyman_outlined, text: value.isLoading ? 'Loading…' : 'No repairs logged')
        else
          _ShortList(children: [
            for (final r in repairs)
              AppCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
                child: Row(
                  children: [
                    const IconBubble(icon: Icons.handyman_rounded, color: AppColors.dueSoon, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.title, style: text.titleSmall),
                          Text(
                            [
                              formatDate(r.repairedOn),
                              if (r.cost != null) 'cost ${formatMoney(r.cost!, currency)}',
                              if (r.billId != null) 'tenant billed',
                            ].join(' · '),
                            style: text.bodySmall,
                          ),
                          if (r.details != null) Text(r.details!, style: text.bodySmall),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      onSelected: (_) => _delete(context, ref, r),
                      itemBuilder: (_) => const [PopupMenuItem(value: 'delete', child: Text('Remove'))],
                    ),
                  ],
                ),
              ),
          ]),
      ],
    );
  }
}

/// A small grey "nothing here" line.
class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: AppColors.muted),
          const SizedBox(width: 10),
          Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _CurrentTenancyCard extends StatelessWidget {
  const _CurrentTenancyCard({required this.tenancy, required this.onTap});

  final TenancyOverview tenancy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final color = tenancyColor(tenancy);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Container(
          // A coloured stripe on the left edge shows the rent status at a glance.
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: color, width: 6)),
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconBubble(icon: Icons.person_rounded, color: color),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tenancy.tenantName,
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'Since ${formatDate(tenancy.startDate)}',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  RentStatusPill(tenancy: tenancy),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.event_rounded, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(child: Text(rentDueText(tenancy))),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VacantCard extends StatelessWidget {
  const _VacantCard({required this.canStartTenancy, required this.onStart});

  final bool canStartTenancy;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.solidSoft(context, AppColors.vacant),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(
              Icons.vpn_key_rounded,
              size: 40,
              color: AppColors.vacant,
            ),
            const SizedBox(height: 8),
            Text(
              'No one lives here right now',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              canStartTenancy
                  ? 'Start a tenancy when a new tenant moves in.'
                  : 'An owner or manager can start a tenancy.',
              textAlign: TextAlign.center,
            ),
            if (canStartTenancy) ...[
              const SizedBox(height: 16),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.vacant,
                ),
                onPressed: onStart,
                icon: const Icon(Icons.person_add_alt_1_rounded),
                label: const Text('Start tenancy'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PastTenancyCard extends StatelessWidget {
  const _PastTenancyCard({required this.tenancy, required this.onTap});

  final TenancyOverview tenancy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final end = tenancy.endDate;
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: const IconBubble(
          icon: Icons.history_rounded,
          color: AppColors.ended,
          size: 40,
        ),
        title: Text(tenancy.tenantName),
        subtitle: Text(
          '${formatDate(tenancy.startDate)} – ${end == null ? '?' : formatDate(end)}',
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
      ),
    );
  }
}
