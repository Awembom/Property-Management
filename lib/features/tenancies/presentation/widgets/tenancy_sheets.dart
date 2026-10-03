import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/features/tenancies/data/tenancies_repository.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tenancies/presentation/tenancy_validators.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/date_field.dart';
import 'package:rental_app/shared/widgets/months_picker.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

// Bottom sheets and dialogs used on the tenancy screen. Each one returns true
// if it saved something, so the screen knows to reload.

/// Edit how often rent is paid, and the notes.
Future<bool> showEditTermsSheet(BuildContext context, {required TenancyDetails details}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditTermsSheet(details: details),
  );
  return saved ?? false;
}

/// Continue the tenancy: a new lease end date and (optionally) a new rent.
Future<bool> showRenewSheet(
  BuildContext context, {
  required TenancyDetails details,
  required String currency,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _RenewSheet(details: details, currency: currency),
  );
  return saved ?? false;
}

/// Edit the tenant contact's name, phone and email, plus the ID card number
/// if [canEditIdNumber] (owners and managers).
Future<bool> showEditTenantSheet(
  BuildContext context, {
  required Tenant tenant,
  required bool canEditIdNumber,
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditTenantSheet(tenant: tenant, canEditIdNumber: canEditIdNumber),
  );
  return saved ?? false;
}

/// Ask for the move-out date and end the tenancy.
Future<bool> showEndTenancyDialog(BuildContext context, {required TenancyOverview tenancy}) async {
  final ended = await showDialog<bool>(
    context: context,
    builder: (_) => _EndTenancyDialog(tenancy: tenancy),
  );
  return ended ?? false;
}

/// Shared layout for the sheets: title, fields, a Save button; stays above
/// the keyboard.
class _SheetFrame extends StatelessWidget {
  const _SheetFrame({
    required this.title,
    required this.formKey,
    required this.busy,
    required this.onSave,
    required this.children,
  });

  final String title;
  final GlobalKey<FormState> formKey;
  final bool busy;
  final VoidCallback onSave;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                ...children,
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: busy ? null : onSave,
                  child: const Text('Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditTermsSheet extends ConsumerStatefulWidget {
  const _EditTermsSheet({required this.details});

  final TenancyDetails details;

  @override
  ConsumerState<_EditTermsSheet> createState() => _EditTermsSheetState();
}

class _EditTermsSheetState extends ConsumerState<_EditTermsSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _notesController = TextEditingController(text: widget.details.money!.notes);
  late int _intervalMonths = widget.details.overview.paymentIntervalMonths;
  bool _busy = false;

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      await ref.read(tenanciesRepositoryProvider).updateTenancyTerms(
            tenancyId: widget.details.overview.id,
            paymentIntervalMonths: _intervalMonths,
            notes: trimToNull(_notesController.text),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Edit tenancy',
      formKey: _formKey,
      busy: _busy,
      onSave: _save,
      children: [
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
          'Rent reminders follow this. To change the rent or the lease end, use "Renew".',
          style: Theme.of(context).textTheme.bodySmall,
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
      ],
    );
  }
}

class _RenewSheet extends ConsumerStatefulWidget {
  const _RenewSheet({required this.details, required this.currency});

  final TenancyDetails details;
  final String currency;

  @override
  ConsumerState<_RenewSheet> createState() => _RenewSheetState();
}

class _RenewSheetState extends ConsumerState<_RenewSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _rentController = TextEditingController(
    text: moneyToInput(widget.details.money!.monthlyRent, widget.currency),
  );
  final _notesController = TextEditingController();

  /// Suggest one more year after the current lease end (or after today, if
  /// the lease already ended or has no end date).
  late DateTime? _newEndDate = addMonths(_later(widget.details.overview.endDate, today()), 12);
  String? _endDateError;
  bool _busy = false;

  static DateTime _later(DateTime? a, DateTime b) => a != null && a.isAfter(b) ? a : b;

  @override
  void dispose() {
    _rentController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final overview = widget.details.overview;
    final currentEnd = overview.endDate ?? overview.startDate;
    setState(() {
      if (_newEndDate == null) {
        _endDateError = 'Choose the new lease end date';
      } else if (!_newEndDate!.isAfter(currentEnd)) {
        _endDateError = 'Must be after ${formatDate(currentEnd)}';
      } else {
        _endDateError = null;
      }
    });
    if (!_formKey.currentState!.validate() || _endDateError != null) return;

    setState(() => _busy = true);
    try {
      await ref.read(tenanciesRepositoryProvider).renewTenancy(
            tenancyId: overview.id,
            newEndDate: _newEndDate!,
            newMonthlyRent: parseMoney(_rentController.text, widget.currency)!,
            notes: trimToNull(_notesController.text),
          );
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final overview = widget.details.overview;
    return _SheetFrame(
      title: 'Renew tenancy',
      formKey: _formKey,
      busy: _busy,
      onSave: _save,
      children: [
        Text(
          overview.endDate == null
              ? '${overview.tenantName} stays on. Set the lease end and the rent from now on.'
              : 'The lease currently ends ${formatDate(overview.endDate!)}. '
                  'The old end date and rent are kept in the history.',
        ),
        const SizedBox(height: 16),
        DateField(
          label: 'New lease end',
          value: _newEndDate,
          errorText: _endDateError,
          onChanged: (date) => setState(() => _newEndDate = date),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _rentController,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: rentAmountValidator(widget.currency),
          decoration: InputDecoration(
            labelText: 'Monthly rent from now on',
            helperText: 'Keep it, or enter the new rent you agreed.',
            suffixText: widget.currency,
            prefixIcon: const Icon(Icons.savings_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _notesController,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Note (optional)',
            hintText: 'e.g. Second year, rent raised by agreement',
            prefixIcon: Icon(Icons.sticky_note_2_rounded),
          ),
        ),
      ],
    );
  }
}

class _EditTenantSheet extends ConsumerStatefulWidget {
  const _EditTenantSheet({required this.tenant, required this.canEditIdNumber});

  final Tenant tenant;
  final bool canEditIdNumber;

  @override
  ConsumerState<_EditTenantSheet> createState() => _EditTenantSheetState();
}

class _EditTenantSheetState extends ConsumerState<_EditTenantSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.tenant.fullName);
  late final _phoneController = TextEditingController(text: widget.tenant.phone);
  late final _emailController = TextEditingController(text: widget.tenant.email);
  late final _idNumberController = TextEditingController(text: widget.tenant.idNumber);
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _idNumberController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final repository = ref.read(tenanciesRepositoryProvider);
      await repository.updateTenant(Tenant(
        id: widget.tenant.id,
        fullName: _nameController.text.trim(),
        phone: trimToNull(_phoneController.text),
        email: trimToNull(_emailController.text),
      ));
      // The ID number lives in its own (owners/managers only) table.
      final idNumber = trimToNull(_idNumberController.text);
      if (widget.canEditIdNumber && idNumber != widget.tenant.idNumber) {
        await repository.setTenantIdNumber(widget.tenant.id, idNumber);
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SheetFrame(
      title: 'Edit tenant',
      formKey: _formKey,
      busy: _busy,
      onSave: _save,
      children: [
        TextFormField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          validator: validateTenantName,
          decoration: const InputDecoration(
            labelText: 'Full name',
            prefixIcon: Icon(Icons.badge_rounded),
          ),
        ),
        if (widget.canEditIdNumber) ...[
          const SizedBox(height: 16),
          TextFormField(
            controller: _idNumberController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              labelText: 'ID card number (optional)',
              prefixIcon: Icon(Icons.credit_card_rounded),
            ),
          ),
        ],
        const SizedBox(height: 16),
        TextFormField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone (optional)',
            prefixIcon: Icon(Icons.phone_rounded),
          ),
        ),
        const SizedBox(height: 16),
        TextFormField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          validator: validateOptionalEmail,
          decoration: const InputDecoration(
            labelText: 'Email (optional)',
            prefixIcon: Icon(Icons.alternate_email_rounded),
          ),
        ),
      ],
    );
  }
}

class _EndTenancyDialog extends ConsumerStatefulWidget {
  const _EndTenancyDialog({required this.tenancy});

  final TenancyOverview tenancy;

  @override
  ConsumerState<_EndTenancyDialog> createState() => _EndTenancyDialogState();
}

class _EndTenancyDialogState extends ConsumerState<_EndTenancyDialog> {
  late DateTime _moveOut = today().isBefore(widget.tenancy.startDate)
      ? widget.tenancy.startDate
      : today();
  bool _busy = false;

  Future<void> _end() async {
    setState(() => _busy = true);
    try {
      await ref
          .read(tenanciesRepositoryProvider)
          .endTenancy(widget.tenancy.id, _moveOut);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(
        Icons.logout_rounded,
        color: AppColors.overdue,
        size: 36,
      ),
      title: Text('End ${widget.tenancy.tenantName}\'s tenancy?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${widget.tenancy.apartmentName} will become vacant. The tenancy and its '
            'history are kept, but it can\'t be reopened.',
          ),
          const SizedBox(height: 16),
          DateField(
            label: 'Move-out date',
            value: _moveOut,
            firstDate: widget.tenancy.startDate,
            onChanged: (date) => setState(() => _moveOut = date),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.overdue,
            foregroundColor: Colors.white,
          ),
          onPressed: _busy ? null : _end,
          child: const Text('End tenancy'),
        ),
      ],
    );
  }
}
