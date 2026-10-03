import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/shared/utils/phone.dart';
import 'package:rental_app/shared/widgets/phone_field.dart';
import 'package:rental_app/core/constants/currencies.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/features/tenancies/data/tenancies_repository.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tenancies/presentation/tenancy_validators.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/date_field.dart';
import 'package:rental_app/shared/widgets/months_picker.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Move a tenant into a vacant apartment: who, how much rent, from when.
class StartTenancyPage extends ConsumerWidget {
  const StartTenancyPage({
    super.key,
    required this.propertyId,
    required this.apartmentId,
  });

  final String propertyId;
  final String apartmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(myPropertyProvider(propertyId));
    final apartment = ref.watch(apartmentProvider(apartmentId));
    // Existing contacts are optional: if they fail to load, the form still
    // works with "New tenant".
    final tenants =
        ref.watch(propertyTenantsProvider(propertyId)).value ??
        const <Tenant>[];

    final error = property.error ?? apartment.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(
          error: error,
          onRetry: () {
            ref.invalidate(myPropertyProvider(propertyId));
            ref.invalidate(apartmentProvider(apartmentId));
          },
        ),
      );
    }
    if (!property.hasValue || !apartment.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _StartTenancyForm(
      property: property.requireValue.property,
      apartment: apartment.requireValue,
      tenants: tenants,
    );
  }
}

class _StartTenancyForm extends ConsumerStatefulWidget {
  const _StartTenancyForm({
    required this.property,
    required this.apartment,
    required this.tenants,
  });

  final Property property;
  final Apartment apartment;
  final List<Tenant> tenants;

  @override
  ConsumerState<_StartTenancyForm> createState() => _StartTenancyFormState();
}

class _StartTenancyFormState extends ConsumerState<_StartTenancyForm> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _idNumberController = TextEditingController();
  // Pre-filled with the apartment's standard monthly rent; the landlord can
  // type a different (renegotiated) amount.
  late final _rentController = TextEditingController(
    text: widget.apartment.monthlyRent == null
        ? ''
        : moneyToInput(widget.apartment.monthlyRent!, _currency),
  );
  final _notesController = TextEditingController();

  bool _useExistingTenant = false;
  String? _existingTenantId;
  int _intervalMonths = 1; // how often they pay; reminders follow this
  DateTime _startDate = today();
  DateTime? _endDate;
  bool _alreadyPaid = false;
  DateTime? _paidUntil;

  // Errors for the date fields (they aren't TextFormFields, so we check them
  // ourselves in _submit).
  String? _endDateError;
  String? _paidUntilError;
  bool _saving = false;

  String get _currency => widget.property.currency;

  /// Explains where the pre-filled amount came from.
  String _rentHelperText() {
    final monthly = widget.apartment.monthlyRent;
    if (monthly == null) return 'This apartment has no standard rent yet.';
    return 'Standard rent for ${widget.apartment.name}: '
        '${formatMoney(monthly, _currency)} per month. '
        'Change it if you agreed a different rent with this tenant.';
  }

  /// "They'll pay XAF 150,000 every 3 months", or null if no valid rent yet.
  String? _perPaymentText() {
    final monthly = parseMoney(_rentController.text, _currency);
    if (monthly == null || monthly <= 0 || _intervalMonths == 1) return null;
    return 'They\'ll pay ${formatMoney(monthly * _intervalMonths, _currency)} '
        '${PaymentInterval.label(_intervalMonths).toLowerCase()}.';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _idNumberController.dispose();
    _rentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool _validateDates() {
    setState(() {
      _endDateError = _endDate != null && _endDate!.isBefore(_startDate)
          ? 'Must be on or after the move-in date'
          : null;
      if (!_alreadyPaid) {
        _paidUntilError = null;
      } else if (_paidUntil == null) {
        _paidUntilError = 'Choose the date they have paid up to';
      } else if (_paidUntil!.isBefore(_startDate)) {
        _paidUntilError = 'Must be on or after the move-in date';
      } else {
        _paidUntilError = null;
      }
    });
    return _endDateError == null && _paidUntilError == null;
  }

  Future<void> _submit() async {
    final formOk = _formKey.currentState!.validate();
    final datesOk = _validateDates();
    if (!formOk || !datesOk) return;

    setState(() => _saving = true);
    try {
      final tenancyId = await ref
          .read(tenanciesRepositoryProvider)
          .startTenancy(
            NewTenancy(
              apartmentId: widget.apartment.id,
              monthlyRent: parseMoney(_rentController.text, _currency)!,
              paymentIntervalMonths: _intervalMonths,
              startDate: _startDate,
              existingTenantId: _useExistingTenant ? _existingTenantId : null,
              tenantName: _useExistingTenant
                  ? null
                  : _nameController.text.trim(),
              tenantPhone: _useExistingTenant
                  ? null
                  : normalizePhone(_phoneController.text),
              tenantEmail: _useExistingTenant
                  ? null
                  : trimToNull(_emailController.text),
              tenantIdNumber: _useExistingTenant
                  ? null
                  : trimToNull(_idNumberController.text),
              endDate: _endDate,
              paidUntil: _alreadyPaid ? _paidUntil : null,
              notes: trimToNull(_notesController.text),
            ),
          );

      // The apartment is now occupied: reload everything that shows it.
      ref.invalidate(apartmentsProvider(widget.property.id));
      ref.invalidate(apartmentTenanciesProvider(widget.apartment.id));
      ref.invalidate(propertyTenantsProvider(widget.property.id));
      if (!mounted) return;
      showMessage(context, 'Tenancy started');
      // Replace this form with the new tenancy (Back returns to the apartment).
      context.pushReplacement(
        AppRoutes.tenancyDetail(widget.property.id, tenancyId),
      );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTenants = widget.tenants.isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: Text('New tenant · ${widget.apartment.name}')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            // ---------------- Tenant ----------------
            const _ColorSectionTitle(
              icon: Icons.person_rounded,
              color: AppColors.primary,
              title: 'Who is moving in?',
            ),
            if (hasTenants) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    label: Text('New tenant'),
                    icon: Icon(Icons.person_add_alt_1),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Existing'),
                    icon: Icon(Icons.people_alt_rounded),
                  ),
                ],
                selected: {_useExistingTenant},
                onSelectionChanged: (selection) =>
                    setState(() => _useExistingTenant = selection.first),
              ),
              const SizedBox(height: 16),
            ],
            if (_useExistingTenant)
              DropdownButtonFormField<String>(
                initialValue: _existingTenantId,
                isExpanded: true,
                validator: (value) => value == null ? 'Choose a tenant' : null,
                onChanged: (value) => setState(() => _existingTenantId = value),
                decoration: const InputDecoration(
                  labelText: 'Tenant',
                  prefixIcon: Icon(Icons.person_search_rounded),
                ),
                items: [
                  for (final tenant in widget.tenants)
                    DropdownMenuItem(
                      value: tenant.id,
                      child: Text(
                        [
                          tenant.fullName,
                          if (tenant.phone != null) formatPhone(tenant.phone!),
                        ].join(' · '),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              )
            else ...[
              TextFormField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                validator: validateTenantName,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.badge_rounded),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _idNumberController,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'ID card number (optional)',
                  helperText: 'Only owners and managers can see it.',
                  prefixIcon: Icon(Icons.credit_card_rounded),
                ),
              ),
              const SizedBox(height: 16),
              PhoneField(controller: _phoneController),
              const SizedBox(height: 16),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                validator: validateOptionalEmail,
                decoration: const InputDecoration(
                  labelText: 'Email (optional)',
                  helperText: 'If they sign up with this email, they\'ll see their rent in the app.',
                  helperMaxLines: 2,
                  prefixIcon: Icon(Icons.alternate_email_rounded),
                ),
              ),
            ],

            // ---------------- Rent ----------------
            const _ColorSectionTitle(
              icon: Icons.payments_rounded,
              color: AppColors.paid,
              title: 'Rent',
            ),
            TextFormField(
              controller: _rentController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              validator: rentAmountValidator(_currency),
              // Rebuild so "They'll pay ..." below stays up to date.
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: 'Monthly rent',
                hintText: currencyHint(_currency),
                helperText: _rentHelperText(),
                helperMaxLines: 3,
                suffixText: _currency,
                prefixIcon: const Icon(Icons.savings_rounded),
              ),
            ),
            const SizedBox(height: 20),
            const Text('How often do they pay?'),
            const SizedBox(height: 8),
            MonthsPicker(
              value: _intervalMonths,
              presets: PaymentInterval.presets,
              labelFor: PaymentInterval.label,
              min: PaymentInterval.minMonths,
              max: PaymentInterval.maxMonths,
              color: AppColors.paid,
              onChanged: (months) => setState(() => _intervalMonths = months),
            ),
            const SizedBox(height: 8),
            Text(
              [
                ?_perPaymentText(),
                'Rent reminders will be sent on this schedule.',
              ].join(' '),
              style: Theme.of(context).textTheme.bodySmall,
            ),

            // ---------------- Dates ----------------
            const _ColorSectionTitle(
              icon: Icons.event_rounded,
              color: AppColors.dueSoon,
              title: 'Dates',
            ),
            DateField(
              label: 'Move-in date',
              value: _startDate,
              onChanged: (date) => setState(() => _startDate = date),
            ),
            const SizedBox(height: 16),
            DateField(
              label: 'Lease ends (optional)',
              value: _endDate,
              errorText: _endDateError,
              onChanged: (date) => setState(() => _endDate = date),
              onCleared: () => setState(() => _endDate = null),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('They already paid some rent'),
              subtitle: const Text(
                'For tenants who paid before you started using the app.',
              ),
              value: _alreadyPaid,
              onChanged: (value) => setState(() => _alreadyPaid = value),
            ),
            if (_alreadyPaid)
              DateField(
                label: 'Rent is paid up to',
                helperText: 'Their next payment is due on this date.',
                value: _paidUntil,
                errorText: _paidUntilError,
                onChanged: (date) => setState(() => _paidUntil = date),
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                prefixIcon: Icon(Icons.sticky_note_2_rounded),
              ),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.key_rounded),
              label: const Text('Start tenancy'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Example amount for the rent field: "e.g. 50000" (XAF) or "e.g. 450.00" (USD).
String currencyHint(String currency) {
  final example = currencyDecimals(currency) == 0 ? 50000 : 45000;
  return 'e.g. ${moneyToInput(example, currency)}';
}

/// A section heading with a coloured icon.
class _ColorSectionTitle extends StatelessWidget {
  const _ColorSectionTitle({
    required this.icon,
    required this.color,
    required this.title,
  });

  final IconData icon;
  final Color color;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SectionTitle(title, trailing: Icon(icon, color: color));
  }
}
