import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/data/payments_repository.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/presentation/tenancy_validators.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/date_field.dart';
import 'package:rental_app/shared/widgets/gradient_header.dart';
import 'package:rental_app/shared/widgets/months_picker.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Record money a tenant paid, which creates a numbered receipt.
///
/// The landlord says how many months the tenant paid for; the screen fills in
/// the period (up to the new "paid until" date) and the full amount. The
/// amount can be changed: if it's less, the rest is "left to pay" and shows on
/// the receipt. Caretakers allowed to record payments see no rent amounts.
class RecordPaymentPage extends ConsumerWidget {
  const RecordPaymentPage({super.key, required this.propertyId, required this.tenancyId});

  final String propertyId;
  final String tenancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ids = (propertyId: propertyId, tenancyId: tenancyId);
    final property = ref.watch(myPropertyProvider(propertyId));
    final details = ref.watch(tenancyDetailsProvider(ids));

    final error = property.error ?? details.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(
          error: error,
          onRetry: () {
            ref.invalidate(myPropertyProvider(propertyId));
            ref.invalidate(tenancyDetailsProvider(ids));
          },
        ),
      );
    }
    if (!property.hasValue || !details.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _RecordPaymentForm(
      myProperty: property.requireValue,
      details: details.requireValue,
    );
  }
}

class _RecordPaymentForm extends ConsumerStatefulWidget {
  const _RecordPaymentForm({required this.myProperty, required this.details});

  final MyProperty myProperty;
  final TenancyDetails details;

  @override
  ConsumerState<_RecordPaymentForm> createState() => _RecordPaymentFormState();
}

class _RecordPaymentFormState extends ConsumerState<_RecordPaymentForm> {
  final _formKey = GlobalKey<FormState>();
  final _referenceController = TextEditingController();
  late final _amountController = TextEditingController(text: _suggestedAmountText());

  PaymentKind _kind = PaymentKind.rent;
  // Start with the tenant's usual payment interval (e.g. 3 months).
  late int _months = widget.details.overview.paymentIntervalMonths;
  DateTime _paidOn = today();
  PaymentMethod _method = PaymentMethod.cash;
  bool _saving = false;

  /// True once the landlord typed their own amount: we then stop replacing it
  /// when the number of months changes.
  bool _amountEdited = false;

  TenancyOverview get _tenancy => widget.details.overview;
  TenancyMoney? get _money => widget.details.money; // null for caretakers
  String get _currency => widget.myProperty.property.currency;

  /// What [_months] of rent costs; null if we can't see the rent.
  int? get _fullAmount => _money == null ? null : _money!.monthlyRent * _months;

  /// The amount typed, or null if empty/invalid.
  int? get _enteredAmount => parseMoney(_amountController.text, _currency);

  String _suggestedAmountText() {
    if (_money == null) return '';
    if (_kind == PaymentKind.balance) {
      return _money!.balance > 0 ? moneyToInput(_money!.balance, _currency) : '';
    }
    return moneyToInput(_money!.monthlyRent * _months, _currency);
  }

  void _refillAmount() {
    if (!_amountEdited) _amountController.text = _suggestedAmountText();
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repository = ref.read(paymentsRepositoryProvider);
    final reference = trimToNull(_referenceController.text);
    try {
      final recorded = _kind == PaymentKind.rent
          ? await repository.recordRent(
              tenancyId: _tenancy.id,
              months: _months,
              // Empty (caretakers) = the full rent; the database works it out.
              amount: _enteredAmount,
              paidOn: _paidOn,
              method: _method.value,
              reference: reference,
            )
          : await repository.recordBalance(
              tenancyId: _tenancy.id,
              amount: _enteredAmount!,
              paidOn: _paidOn,
              method: _method.value,
              reference: reference,
            );

      // Rent status, balance and history all changed: reload them.
      final propertyId = widget.myProperty.property.id;
      ref.invalidate(tenancyDetailsProvider((propertyId: propertyId, tenancyId: _tenancy.id)));
      ref.invalidate(tenancyPaymentsProvider(_tenancy.id));
      ref.invalidate(apartmentsProvider(propertyId));
      ref.invalidate(apartmentTenanciesProvider(_tenancy.apartmentId));
      if (!mounted) return;

      if (widget.myProperty.access.canSeeMoney) {
        // Show the receipt (Back returns to the tenancy).
        context.pushReplacement(AppRoutes.receipt(propertyId, recorded.paymentId));
      } else {
        // Caretakers can't open receipts (they show money); confirm and go back.
        showMessage(context, 'Payment recorded · receipt ${recorded.receiptNumber}');
        context.pop();
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSeeMoney = _money != null;
    final owes = canSeeMoney && _money!.balance > 0;
    final newPaidUntil = _tenancy.paidUntilAfter(_months);

    return Scaffold(
      appBar: AppBar(title: const Text('Record payment')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            GradientHeader(
              color: AppColors.paid,
              icon: Icons.payments_rounded,
              title: widget.details.tenant.fullName,
              subtitle: 'Apartment ${_tenancy.apartmentName}',
              stats: [
                HeaderStat(value: formatDate(_tenancy.paidUntil), label: 'Paid until now'),
                if (canSeeMoney)
                  HeaderStat(
                    value: formatMoney(_money!.balance > 0 ? _money!.balance : 0, _currency),
                    label: 'Left to pay',
                  ),
              ],
            ),

            // Only offer "balance" when something is actually owed.
            if (owes) ...[
              const SizedBox(height: 16),
              SegmentedButton<PaymentKind>(
                segments: const [
                  ButtonSegment(
                    value: PaymentKind.rent,
                    label: Text('Rent'),
                    icon: Icon(Icons.calendar_month_rounded),
                  ),
                  ButtonSegment(
                    value: PaymentKind.balance,
                    label: Text('Pay off balance'),
                    icon: Icon(Icons.price_check_rounded),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (selection) => setState(() {
                  _kind = selection.first;
                  _amountEdited = false;
                  _refillAmount();
                }),
              ),
            ],

            if (_kind == PaymentKind.rent) ...[
              const SectionTitle('How long did they pay for?'),
              MonthsPicker(
                value: _months,
                presets: const [1, 3, 6, 12],
                labelFor: PaymentInterval.monthsText,
                max: 60,
                color: AppColors.paid,
                onChanged: (months) => setState(() {
                  _months = months;
                  _refillAmount();
                }),
              ),
              const SizedBox(height: 12),
              _PeriodCard(from: _tenancy.paidUntil, to: newPaidUntil, months: _months),
            ],

            // A balance payment shares the reference code of the part
            // payment it completes; show which one.
            if (_kind == PaymentKind.balance) ...[
              const SizedBox(height: 12),
              _CompletesCard(tenancyId: _tenancy.id),
            ],

            const SectionTitle('Amount'),
            TextFormField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (_) => setState(() => _amountEdited = true),
              validator: (text) {
                // Caretakers may leave it empty: the full rent is recorded.
                if (!canSeeMoney && _kind == PaymentKind.rent && (text ?? '').trim().isEmpty) {
                  return null;
                }
                return rentAmountValidator(_currency)(text);
              },
              decoration: InputDecoration(
                labelText: 'Amount paid',
                helperText: canSeeMoney
                    ? (_kind == PaymentKind.rent
                        ? 'Full rent for ${PaymentInterval.monthsText(_months)}: '
                            '${formatMoney(_fullAmount!, _currency)}. Change it if they paid less or more.'
                        : 'Still owed: ${formatMoney(_money!.balance, _currency)}.')
                    : 'Leave empty if they paid the full rent.',
                helperMaxLines: 3,
                suffixText: _currency,
                prefixIcon: const Icon(Icons.savings_rounded),
              ),
            ),
            if (canSeeMoney) ...[
              const SizedBox(height: 12),
              _BalancePreview(
                currency: _currency,
                balanceBefore: _money!.balance,
                // What this payment adds to (or removes from) what is owed.
                change: _kind == PaymentKind.rent
                    ? _fullAmount! - (_enteredAmount ?? _fullAmount!)
                    : -(_enteredAmount ?? 0),
              ),
            ],

            const SectionTitle('Details'),
            DateField(
              label: 'Paid on',
              value: _paidOn,
              lastDate: today(),
              onChanged: (date) => setState(() => _paidOn = date),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final method in PaymentMethod.values)
                  ChoiceChip(
                    label: Text(method.label),
                    selected: _method == method,
                    selectedColor: AppColors.soft(AppColors.primary),
                    onSelected: (_) => setState(() => _method = method),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _referenceController,
              decoration: const InputDecoration(
                labelText: 'Transaction ID (optional)',
                hintText: 'e.g. mobile money transaction number',
                helperText: 'The receipt also gets its own reference code automatically.',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.paid),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.receipt_long_rounded),
              label: const Text('Record & create receipt'),
            ),
          ],
        ),
      ),
    );
  }
}

/// "1 Nov 2026 – 1 Feb 2027 (3 months)", with the new paid-until date.
class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.from, required this.to, required this.months});

  final DateTime from;
  final DateTime to;
  final int months;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Card(
      color: AppColors.solidSoft(context, AppColors.paid),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const Icon(Icons.event_available_rounded, color: AppColors.paid, size: 32),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Covers ${PaymentInterval.monthsText(months)}', style: text.labelLarge),
                  Text(
                    '${formatDate(from)} – ${formatDate(to)}',
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text('Rent will be paid until ${formatDate(to)}'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows what will be owed after this payment, in colour.
class _BalancePreview extends StatelessWidget {
  const _BalancePreview({
    required this.currency,
    required this.balanceBefore,
    required this.change,
  });

  final String currency;
  final int balanceBefore;

  /// Positive = this payment leaves money owed; negative = it pays some off.
  final int change;

  @override
  Widget build(BuildContext context) {
    final after = balanceBefore + change;
    final (Color color, IconData icon, String message) = switch (after) {
      > 0 => (
          AppColors.overdue,
          Icons.warning_amber_rounded,
          '${formatMoney(after, currency)} will be left to pay. '
              'The receipt will show it.',
        ),
      < 0 => (
          AppColors.vacant,
          Icons.savings_rounded,
          '${formatMoney(-after, currency)} paid in advance.',
        ),
      _ => (AppColors.paid, Icons.check_circle_rounded, 'Fully paid. Nothing left to pay.'),
    };
    return Card(
      color: AppColors.solidSoft(context, color),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(message),
        subtitle: balanceBefore > 0 && change > 0
            ? Text('Includes ${formatMoney(balanceBefore, currency)} owed from before.')
            : null,
      ),
    );
  }
}

/// "Completes receipt RCT-2026-0007 (PAY-7K3QX9)": the latest part-paid
/// receipt, which is the one the database links a balance payment to.
class _CompletesCard extends ConsumerWidget {
  const _CompletesCard({required this.tenancyId});

  final String tenancyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payments = ref.watch(tenancyPaymentsProvider(tenancyId)).value ?? const <Payment>[];
    // Same rule as record_payment(): newest non-voided, not fully paid rent payment.
    final partPaid = payments
        .where((p) => p.kind == PaymentKind.rent && !p.isVoided && p.shortfall > 0)
        .firstOrNull;
    if (partPaid == null) return const SizedBox.shrink();

    return Card(
      color: AppColors.solidSoft(context, AppColors.primary),
      child: ListTile(
        leading: const Icon(Icons.link_rounded, color: AppColors.primary),
        title: Text('Completes receipt ${partPaid.receiptNumber}'),
        subtitle: Text(
          'Same reference ${partPaid.referenceCode}. The new receipt\'s PDF '
          'will include that receipt as page 2.',
        ),
      ),
    );
  }
}
