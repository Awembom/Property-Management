import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/constants/currencies.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Create a new property ([propertyId] == null) or edit an existing one.
class PropertyFormPage extends ConsumerWidget {
  const PropertyFormPage({super.key, this.propertyId});

  final String? propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = propertyId;

    // Creating: show an empty form straight away.
    if (id == null) {
      return const _PropertyForm(existing: null);
    }

    // Editing: load the property first, then show the form filled in.
    final property = ref.watch(myPropertyProvider(id));
    return property.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myPropertyProvider(id)),
        ),
      ),
      data: (myProperty) => _PropertyForm(existing: myProperty.property),
    );
  }
}

class _PropertyForm extends ConsumerStatefulWidget {
  const _PropertyForm({required this.existing});

  /// null when creating.
  final Property? existing;

  @override
  ConsumerState<_PropertyForm> createState() => _PropertyFormState();
}

class _PropertyFormState extends ConsumerState<_PropertyForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name);
  late final _addressController = TextEditingController(text: widget.existing?.address);
  late final _graceController =
      TextEditingController(text: '${widget.existing?.gracePeriodDays ?? 7}');
  // The number tenants tap to call. A new property starts with my own phone.
  late final _phoneController = TextEditingController(
    text: widget.existing == null ? ref.read(myProfileProvider).value?.phone : widget.existing!.contactPhone,
  );
  late String? _currency = widget.existing?.currency;
  bool _saving = false;

  bool get _isEditing => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _graceController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final repository = ref.read(propertiesRepositoryProvider);
    final name = _nameController.text.trim();
    final address = _addressController.text.trim().isEmpty ? null : _addressController.text.trim();
    final graceDays = int.parse(_graceController.text);
    final phone = _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim();

    try {
      if (_isEditing) {
        final existing = widget.existing!;
        await repository.updateProperty(Property(
          id: existing.id,
          name: name,
          address: address,
          currency: _currency!,
          gracePeriodDays: graceDays,
          contactPhone: phone,
        ));
        ref.invalidate(myPropertyProvider(existing.id));
        ref.invalidate(myPropertiesProvider);
        if (mounted) context.pop();
      } else {
        final created = await repository.createProperty(
          name: name,
          address: address,
          currency: _currency!,
          gracePeriodDays: graceDays,
        );
        if (phone != null) {
          await repository.updateProperty(Property(
            id: created.id,
            name: created.name,
            address: created.address,
            currency: created.currency,
            gracePeriodDays: created.gracePeriodDays,
            contactPhone: phone,
          ));
        }
        ref.invalidate(myPropertiesProvider);
        // Replace the form with the new property's page (Back returns to the list).
        if (mounted) context.pushReplacement(AppRoutes.propertyDetail(created.id));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? 'Edit property' : 'New property')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              validator: (value) =>
                  (value?.trim() ?? '').isEmpty ? 'Enter a name' : null,
              decoration: const InputDecoration(
                labelText: 'Property name',
                hintText: 'e.g. Sunset Apartments',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _addressController,
              textCapitalization: TextCapitalization.sentences,
              maxLines: 2,
              decoration: const InputDecoration(
                labelText: 'Address (optional)',
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Contact phone for tenants',
                hintText: 'Your number or a caretaker\'s',
                helperText: 'Tenants tap it in the app to call.',
                prefixIcon: Icon(Icons.phone_rounded),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _currency,
              isExpanded: true,
              validator: (value) => value == null ? 'Choose a currency' : null,
              onChanged: (value) => setState(() => _currency = value),
              decoration: const InputDecoration(
                labelText: 'Currency',
                helperText: 'Used for all rent and bills in this property.',
              ),
              items: [
                for (final entry in kCurrencies.entries)
                  DropdownMenuItem(
                    value: entry.key,
                    child: Text('${entry.key}: ${entry.value}'),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _graceController,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              validator: (value) {
                final days = int.tryParse(value ?? '');
                if (days == null || days < 0 || days > 60) return 'Enter 0 to 60';
                return null;
              },
              decoration: const InputDecoration(
                labelText: '"Due soon" warning (days)',
                helperText: 'Rent shows as "Due soon" this many days before it\'s due.',
              ),
            ),
            const SizedBox(height: 32),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(_isEditing ? 'Save changes' : 'Create property'),
            ),
          ],
        ),
      ),
    );
  }
}
