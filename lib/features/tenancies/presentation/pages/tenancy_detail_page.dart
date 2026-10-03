import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/rent_status_pill.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/tenancy_sheets.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/features/tenant_access/presentation/widgets/tenant_app_access_card.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';
import 'package:rental_app/shared/widgets/user_avatar.dart';

/// One tenancy: rent status, payments and receipts, the tenant's details and
/// the lease. Owners and managers can record payments, renew, edit or end it.
/// Caretakers see everything except money (the database doesn't send it).
class TenancyDetailPage extends ConsumerWidget {
  const TenancyDetailPage({super.key, required this.propertyId, required this.tenancyId});

  final String propertyId;
  final String tenancyId;

  ({String propertyId, String tenancyId}) get _ids =>
      (propertyId: propertyId, tenancyId: tenancyId);

  /// Reloads this tenancy and the screens that show it.
  void _refreshAfterChange(WidgetRef ref, TenancyDetails details) {
    ref.invalidate(tenancyDetailsProvider(_ids));
    ref.invalidate(tenancyPaymentsProvider(tenancyId));
    ref.invalidate(apartmentsProvider(propertyId));
    ref.invalidate(apartmentTenanciesProvider(details.overview.apartmentId));
    ref.invalidate(propertyTenantsProvider(propertyId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId)).value;
    final detailsValue = ref.watch(tenancyDetailsProvider(_ids));

    return Scaffold(
      appBar: AppBar(title: const Text('Tenancy')),
      body: detailsValue.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(tenancyDetailsProvider(_ids)),
        ),
        data: (details) {
          final tenancy = details.overview;
          final tenant = details.tenant;
          final money = details.money; // null for caretakers
          final access = myProperty?.access ??
              const PropertyAccess(role: MembershipRole.caretaker, canRecordPaymentsFlag: false);
          final currency = myProperty?.property.currency ?? '';
          final canManage = access.canManageTenancies && tenancy.isActive;
          final color = tenancyColor(tenancy);

          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(tenancyPaymentsProvider(tenancyId));
              return ref.refresh(tenancyDetailsProvider(_ids).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                _TenantHeaderCard(
                  name: tenant.fullName,
                  unit: tenancy.apartmentName,
                  phone: tenant.phone,
                  email: tenant.email,
                  status: tenancy.isActive ? null : 'Ended',
                ),
                const SizedBox(height: 12),
                _RentStatusCard(
                  tenancy: tenancy,
                  dueAmount: money == null
                      ? null
                      : formatMoney(money.monthlyRent * tenancy.paymentIntervalMonths, currency),
                  leftToPay: money != null && money.balance > 0
                      ? formatMoney(money.balance, currency)
                      : null,
                ),

                if (tenancy.leaseExpired) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: AppColors.solidSoft(context, AppColors.dueSoon),
                    child: ListTile(
                      leading: const Icon(Icons.event_busy_rounded, color: AppColors.dueSoon),
                      title: Text('The lease ended on ${formatDate(tenancy.endDate!)}'),
                      subtitle: Text(canManage
                          ? 'Renew it to continue the tenancy, or end the tenancy.'
                          : 'An owner or manager can renew or end it.'),
                    ),
                  ),
                ],

                if (tenancy.isActive && access.canRecordPayments) ...[
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: AppColors.paid),
                    onPressed: () => context.push(AppRoutes.recordPayment(propertyId, tenancyId)),
                    icon: const Icon(Icons.add_card_rounded),
                    label: const Text('Record payment'),
                  ),
                ],

                // ---------------- Rent ----------------
                const SectionTitle('Rent'),
                _InfoCard(rows: [
                  if (money != null) ...[
                    _InfoRow(
                      icon: Icons.savings_rounded,
                      color: AppColors.paid,
                      label: 'Monthly rent',
                      value: '${formatMoney(money.monthlyRent, currency)} per month',
                    ),
                    if (money.differsFromStandard)
                      _InfoRow(
                        icon: Icons.handshake_rounded,
                        color: AppColors.accent,
                        label: 'Negotiated rent',
                        value: 'This apartment\'s standard rent is '
                            '${formatMoney(money.standardMonthlyRent!, currency)} per month',
                      ),
                  ] else
                    const _InfoRow(
                      icon: Icons.lock_rounded,
                      color: AppColors.ended,
                      label: 'Rent',
                      value: 'Rent amounts are only shown to owners and managers.',
                    ),
                  _InfoRow(
                    icon: Icons.notifications_active_rounded,
                    color: AppColors.primary,
                    label: 'Pays',
                    value: [
                      PaymentInterval.label(tenancy.paymentIntervalMonths),
                      if (money != null && tenancy.paymentIntervalMonths > 1)
                        '${formatMoney(money.monthlyRent * tenancy.paymentIntervalMonths, currency)} each time',
                    ].join(' · '),
                  ),
                  if (money != null && money.balance != 0)
                    _InfoRow(
                      icon: money.balance > 0 ? Icons.warning_amber_rounded : Icons.savings_rounded,
                      color: money.balance > 0 ? AppColors.overdue : AppColors.vacant,
                      label: money.balance > 0 ? 'Left to pay' : 'Paid in advance',
                      value: formatMoney(money.balance.abs(), currency),
                    ),
                  if (tenancy.isActive)
                    _InfoRow(
                      icon: Icons.event_rounded,
                      color: color,
                      label: 'Status',
                      value: rentDueText(tenancy),
                    ),
                ]),

                // ---------------- Payments ----------------
                if (money != null) _PaymentsSection(propertyId: propertyId, tenancyId: tenancyId),

                // ---------------- Tenant ----------------
                SectionTitle(
                  'Tenant',
                  trailing: access.canManageTenancies
                      ? TextButton.icon(
                          onPressed: () async {
                            final saved = await showEditTenantSheet(
                              context,
                              tenant: tenant,
                              canEditIdNumber: access.canSeeMoney,
                            );
                            if (saved && context.mounted) {
                              _refreshAfterChange(ref, details);
                              showMessage(context, 'Tenant updated');
                            }
                          },
                          icon: const Icon(Icons.edit_rounded, size: 18),
                          label: const Text('Edit'),
                        )
                      : null,
                ),
                _InfoCard(rows: [
                  if (access.canSeeMoney)
                    _InfoRow(
                      icon: Icons.credit_card_rounded,
                      color: AppColors.accent,
                      label: 'ID card number',
                      value: tenant.idNumber ?? 'Not given',
                    ),
                  _InfoRow(
                    icon: Icons.phone_rounded,
                    color: AppColors.paid,
                    label: 'Phone',
                    value: tenant.phone ?? 'Not given',
                  ),
                  _InfoRow(
                    icon: Icons.alternate_email_rounded,
                    color: AppColors.vacant,
                    label: 'Email',
                    value: tenant.email ?? 'Not given',
                  ),
                  _InfoRow(
                    icon: tenant.hasAccount ? Icons.phone_android_rounded : Icons.mobile_off_rounded,
                    color: tenant.hasAccount ? AppColors.primary : AppColors.ended,
                    label: 'App',
                    value: tenant.hasAccount ? 'Uses the app' : 'Not using the app yet',
                  ),
                ]),

                // Invite code / password reset (owners and managers).
                if (access.canManageTenancies && tenancy.isActive) ...[
                  const SizedBox(height: 10),
                  TenantAppAccessCard(
                    propertyId: propertyId,
                    tenant: tenant,
                    onChanged: () => _refreshAfterChange(ref, details),
                  ),
                ],

                // ---------------- Lease ----------------
                const SectionTitle('Lease'),
                _InfoCard(rows: [
                  _InfoRow(
                    icon: Icons.login_rounded,
                    color: AppColors.paid,
                    label: 'Moved in',
                    value: formatDate(tenancy.startDate),
                  ),
                  _InfoRow(
                    icon: Icons.logout_rounded,
                    color: AppColors.overdue,
                    label: tenancy.isActive ? 'Lease ends' : 'Moved out',
                    value: tenancy.endDate == null ? 'No end date' : formatDate(tenancy.endDate!),
                  ),
                  _InfoRow(
                    icon: Icons.verified_rounded,
                    color: tenancy.agreementAcceptedAt == null ? AppColors.ended : AppColors.primary,
                    label: 'Tenancy agreement',
                    value: tenancy.agreementAcceptedAt != null
                        ? 'Accepted in the app on ${formatDate(tenancy.agreementAcceptedAt!)}'
                        : tenant.hasAccount
                            ? 'Not accepted yet'
                            : 'Accepted when the tenant joins the app',
                  ),
                  if (money?.notes != null)
                    _InfoRow(
                      icon: Icons.sticky_note_2_rounded,
                      color: AppColors.dueSoon,
                      label: 'Notes',
                      value: money!.notes!,
                    ),
                ]),
                if (money != null && money.renewals.isNotEmpty) ...[
                  SectionTitle('Renewals (${money.renewals.length})'),
                  for (final renewal in money.renewals)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _RenewalCard(renewal: renewal, currency: currency),
                    ),
                ],

                // ---------------- Actions ----------------
                if (canManage && money != null) ...[
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () async {
                      final saved =
                          await showRenewSheet(context, details: details, currency: currency);
                      if (saved && context.mounted) {
                        _refreshAfterChange(ref, details);
                        showMessage(context, 'Tenancy renewed');
                      }
                    },
                    icon: const Icon(Icons.autorenew_rounded),
                    label: const Text('Renew (continue tenancy)'),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.tonalIcon(
                    onPressed: () async {
                      final saved = await showEditTermsSheet(context, details: details);
                      if (saved && context.mounted) {
                        _refreshAfterChange(ref, details);
                        showMessage(context, 'Tenancy updated');
                      }
                    },
                    icon: const Icon(Icons.edit_note_rounded),
                    label: const Text('Edit payment schedule & notes'),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.overdue,
                      side: const BorderSide(color: AppColors.overdue),
                    ),
                    onPressed: () async {
                      final ended = await showEndTenancyDialog(context, tenancy: tenancy);
                      if (ended && context.mounted) {
                        _refreshAfterChange(ref, details);
                        showMessage(context, '${tenancy.apartmentName} is now vacant');
                      }
                    },
                    icon: const Icon(Icons.logout_rounded),
                    label: const Text('End tenancy (move out)'),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// The tenancy's payments, newest first; tap one to open its receipt.
class _PaymentsSection extends ConsumerWidget {
  const _PaymentsSection({required this.propertyId, required this.tenancyId});

  final String propertyId;
  final String tenancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(tenancyPaymentsProvider(tenancyId));
    final currency = ref.watch(myPropertyProvider(propertyId)).value?.property.currency ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionTitle('Payments & receipts'),
        payments.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => AsyncErrorView(
            error: error,
            onRetry: () => ref.invalidate(tenancyPaymentsProvider(tenancyId)),
          ),
          data: (payments) => payments.isEmpty
              ? const Card(
                  child: ListTile(
                    leading: Icon(Icons.receipt_long_rounded, color: AppColors.primary),
                    title: Text('No payments yet'),
                    subtitle: Text('Recorded payments and their receipts appear here.'),
                  ),
                )
              : Column(
                  children: [
                    for (final payment in payments)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _PaymentCard(
                          payment: payment,
                          currency: currency,
                          onTap: () => context.push(AppRoutes.receipt(propertyId, payment.id)),
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.payment, required this.currency, required this.onTap});

  final Payment payment;
  final String currency;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final response = payment.response;
    // A receipt the tenant disputed (and that isn't sorted out) stands out.
    final disputed = !payment.isVoided &&
        response != null &&
        !response.confirmed &&
        response.ticketStatus != TicketStatus.resolved;
    final (Color color, String label) = payment.isVoided
        ? (AppColors.ended, 'Void')
        : disputed
            ? (AppColors.overdue, 'Disputed')
            : payment.shortfall > 0
                ? (AppColors.overdue, 'Part paid')
                : (AppColors.paid, 'Paid');
    final what = payment.kind == PaymentKind.rent
        ? '${PaymentInterval.monthsText(payment.months!)} · until ${formatDate(payment.periodEnd!)}'
        : 'Towards balance';

    return Card(
      child: ListTile(
        onTap: onTap,
        leading: IconBubble(icon: Icons.receipt_long_rounded, color: color, size: 44),
        title: Text(
          formatMoney(payment.amount, currency),
          style: TextStyle(
            fontWeight: FontWeight.w700,
            decoration: payment.isVoided ? TextDecoration.lineThrough : null,
          ),
        ),
        subtitle: Text(
          '${payment.receiptNumber} · ${formatDate(payment.paidOn)}\n$what · ${payment.referenceCode}',
        ),
        isThreeLine: true,
        trailing: StatusPill(
          label: label,
          color: color,
          icon: disputed ? Icons.report_problem_rounded : (response?.confirmed ?? false) ? Icons.verified_rounded : null,
        ),
      ),
    );
  }
}

class _RenewalCard extends StatelessWidget {
  const _RenewalCard({required this.renewal, required this.currency});

  final TenancyRenewal renewal;
  final String currency;

  @override
  Widget build(BuildContext context) {
    final rentChanged = renewal.oldMonthlyRent != renewal.newMonthlyRent;
    return Card(
      child: ListTile(
        leading: const IconBubble(icon: Icons.autorenew_rounded, color: AppColors.primary, size: 44),
        title: Text('Renewed ${formatDate(renewal.createdAt)}'),
        subtitle: Text([
          'Lease: ${renewal.oldEndDate == null ? 'no end' : formatDate(renewal.oldEndDate!)}'
              ' – ${formatDate(renewal.newEndDate)}',
          if (rentChanged)
            'Rent: ${formatMoney(renewal.oldMonthlyRent, currency)} – '
                '${formatMoney(renewal.newMonthlyRent, currency)} / month',
          if (renewal.notes != null) renewal.notes!,
        ].join('\n')),
      ),
    );
  }
}

/// A card holding a few [_InfoRow]s.
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

/// Coloured icon, small grey label, value underneath.
class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

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
                Text(
                  label,
                  style: text.labelMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(value, style: text.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Tenant details" card: avatar, name and unit, status, phone and email.
class _TenantHeaderCard extends StatelessWidget {
  const _TenantHeaderCard({
    required this.name,
    required this.unit,
    this.phone,
    this.email,
    this.status,
  });

  final String name;
  final String unit;
  final String? phone;
  final String? email;

  /// null = Active.
  final String? status;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              UserAvatar(name: name, size: 64),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$name - Unit $unit', style: text.titleMedium?.copyWith(fontSize: 17)),
                    const SizedBox(height: 4),
                    StatusPill(
                      label: status ?? 'Active',
                      color: status == null ? AppColors.paid : AppColors.ended,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (phone != null || email != null) ...[
            const SizedBox(height: 14),
            Wrap(
              spacing: 18,
              runSpacing: 6,
              children: [
                if (phone != null) _Contact(icon: Icons.phone_rounded, text: phone!),
                if (email != null) _Contact(icon: Icons.mail_rounded, text: email!),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _Contact extends StatelessWidget {
  const _Contact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: AppColors.primary),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.bodyMedium),
      ],
    );
  }
}

/// "Rent payment status": due date, status (e.g. Overdue 15 days), next
/// payment amount (owners/managers), amount left (in red).
class _RentStatusCard extends StatelessWidget {
  const _RentStatusCard({required this.tenancy, this.dueAmount, this.leftToPay});

  final TenancyOverview tenancy;
  final String? dueAmount;
  final String? leftToPay;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final days = daysUntil(tenancy.paidUntil);
    final status = tenancy.rentStatus;
    final statusText = !tenancy.isActive
        ? 'Ended'
        : status == null
            ? 'Active'
            : days <= 0
                ? '${status.label} (${days == 0 ? 'today' : '${-days} day${days == -1 ? '' : 's'}'})'
                : '${status.label} (${timeLeftText(tenancy.paidUntil)} left)';

    Widget row(String label, Widget value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(
            children: [
              Expanded(child: Text(label, style: text.bodyMedium?.copyWith(color: AppColors.muted))),
              value,
            ],
          ),
        );

    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Rent payment status', style: text.titleSmall),
          const SizedBox(height: 4),
          row('Rent paid until', Text(formatDate(tenancy.paidUntil), style: text.titleSmall)),
          row(
            'Payment status',
            StatusPill(label: statusText, color: tenancyColor(tenancy)),
          ),
          if (dueAmount != null && tenancy.isActive)
            row('Next payment', Text(dueAmount!, style: text.titleSmall)),
          if (leftToPay != null)
            row(
              'Amount left',
              Text(leftToPay!, style: text.titleSmall?.copyWith(color: AppColors.overdue)),
            ),
        ],
      ),
    );
  }
}
