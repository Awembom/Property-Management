import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/data/apartments_repository.dart';
import 'package:rental_app/features/tenancies/presentation/tenancy_validators.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// What the apartment sheet did (null = closed without changes).
enum ApartmentSheetResult { saved, deleted }

/// Opens the bottom sheet to add an apartment ([existing] == null) or to
/// edit/delete one.
Future<ApartmentSheetResult?> showApartmentSheet(
  BuildContext context, {
  required String propertyId,
  required String currency,
  Apartment? existing,
}) {
  return showModalBottomSheet<ApartmentSheetResult>(
    context: context,
    isScrollControlled: true, // lets the sheet move up above the keyboard
    builder: (_) => _ApartmentSheet(
      propertyId: propertyId,
      currency: currency,
      existing: existing,
    ),
  );
}

class _ApartmentSheet extends ConsumerStatefulWidget {
  const _ApartmentSheet({
    required this.propertyId,
    required this.currency,
    this.existing,
  });

  final String propertyId;

  /// The property's currency, e.g. 'XAF'.
  final String currency;
  final Apartment? existing;

  @override
  ConsumerState<_ApartmentSheet> createState() => _ApartmentSheetState();
}

class _ApartmentSheetState extends ConsumerState<_ApartmentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(
    text: widget.existing?.name,
  );
  late final _descriptionController = TextEditingController(
    text: widget.existing?.description,
  );
  late final _rentController = TextEditingController(
    text: widget.existing?.monthlyRent == null
        ? null
        : moneyToInput(widget.existing!.monthlyRent!, widget.currency),
  );
  bool _busy = false;

  bool get _isAdding => widget.existing == null;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _rentController.dispose();
    super.dispose();
  }

  /// Runs [action]; closes the sheet with [result] on success, shows the
  /// error otherwise (e.g. "An apartment with this name already exists").
  Future<void> _run(
    Future<void> Function() action,
    ApartmentSheetResult result,
  ) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = ref.read(apartmentsRepositoryProvider);
    final name = _nameController.text.trim();
    final description = _descriptionController.text.trim().isEmpty
        ? null
        : _descriptionController.text.trim();

    await _run(
      () => repository.saveApartment(
        propertyId: widget.propertyId,
        apartmentId: widget.existing?.id, // null = add a new one
        name: name,
        description: description,
        monthlyRent: parseMoney(_rentController.text, widget.currency)!,
      ),
      ApartmentSheetResult.saved,
    );
  }

  Future<void> _delete() async {
    final apartment = widget.existing!;
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete ${apartment.name}?',
      message:
          'This removes the apartment. Apartments that ever had a tenant '
          'can\'t be deleted, so their rent history stays safe.',
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      () =>
          ref.read(apartmentsRepositoryProvider).deleteApartment(apartment.id),
      ApartmentSheetResult.deleted,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keep the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isAdding ? 'New apartment' : 'Edit ${widget.existing!.name}',
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _nameController,
                  autofocus: _isAdding,
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) => (value?.trim() ?? '').isEmpty
                      ? 'Enter a name or number'
                      : null,
                  decoration: const InputDecoration(
                    labelText: 'Name or number',
                    hintText: 'e.g. A1, Flat 3, Studio 2B',
                    prefixIcon: Icon(Icons.door_front_door_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _rentController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: rentAmountValidator(widget.currency),
                  decoration: InputDecoration(
                    labelText: 'Monthly rent',
                    helperText:
                        'The usual rent. You can change it for each tenant.',
                    suffixText: widget.currency,
                    prefixIcon: const Icon(Icons.savings_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _descriptionController,
                  textCapitalization: TextCapitalization.sentences,
                  maxLines: 3,
                  minLines: 1,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'e.g. 2 bedrooms, ground floor',
                    prefixIcon: Icon(Icons.notes_rounded),
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isAdding ? 'Add apartment' : 'Save'),
                ),
                if (!_isAdding) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _busy ? null : _delete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    label: const Text('Delete apartment'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
