import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/features/tenant_access/data/agreement_text.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/my_rental_page.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// The owner writes the tenancy agreement: for the whole property, or
/// ([apartmentId] given) a different one for one unit. Current tenants it
/// applies to must accept the new version.
class AgreementEditorPage extends ConsumerWidget {
  const AgreementEditorPage({super.key, required this.propertyId, this.apartmentId});

  final String propertyId;
  final String? apartmentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(myPropertyProvider(propertyId));
    final apartmentId = this.apartmentId;
    final apartment = apartmentId == null ? null : ref.watch(apartmentProvider(apartmentId));
    final error = property.error ?? apartment?.error;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(error: error, onRetry: () => ref.invalidate(myPropertyProvider(propertyId))),
      );
    }
    if (!property.hasValue || (apartment != null && !apartment.hasValue)) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return _Editor(
      propertyId: propertyId,
      apartmentId: apartmentId,
      unitName: apartment?.requireValue.name,
      propertyText: property.requireValue.property.agreementText,
      unitText: apartment?.requireValue.agreementText,
      canEdit: property.requireValue.access.canManageApartments,
    );
  }
}

class _Editor extends ConsumerStatefulWidget {
  const _Editor({
    required this.propertyId,
    required this.apartmentId,
    required this.unitName,
    required this.propertyText,
    required this.unitText,
    required this.canEdit,
  });

  final String propertyId;
  final String? apartmentId;
  final String? unitName;
  final String? propertyText;
  final String? unitText;
  final bool canEdit;

  @override
  ConsumerState<_Editor> createState() => _EditorState();
}

class _EditorState extends ConsumerState<_Editor> {
  bool get _forUnit => widget.apartmentId != null;

  /// For a unit: false = it uses the property's agreement.
  late bool _ownText = widget.unitText != null;

  late final _controller = TextEditingController(
    text: widget.unitText ?? widget.propertyText ?? defaultAgreementTemplate,
  );
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Puts a field like {tenant} where the cursor is.
  void _insert(String field) {
    final value = _controller.value;
    final start = value.selection.isValid ? value.selection.start : value.text.length;
    final end = value.selection.isValid ? value.selection.end : value.text.length;
    _controller.value = TextEditingValue(
      text: value.text.replaceRange(start, end, field),
      selection: TextSelection.collapsed(offset: start + field.length),
    );
  }

  void _preview() {
    final sections = agreementSections(
      propertyName: 'Sunset Court',
      apartmentName: widget.unitName ?? 'A1',
      tenantName: 'Tina Tenant',
      monthlyRent: 50000,
      currency: 'XAF',
      paymentIntervalMonths: 3,
      startDate: DateTime(2026, 1, 1),
      endDate: DateTime(2026, 12, 31),
      template: _controller.text,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        builder: (context, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Text('Preview (example tenant)', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            AgreementText(sections: sections),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    // Empty = the default: the property's text for a unit, the app's for a
    // property. Saving the app's own text unchanged also counts as default.
    final raw = _controller.text.trim();
    final text = _forUnit
        ? (_ownText ? raw : '')
        : (raw == defaultAgreementTemplate.trim() ? '' : raw);
    try {
      final count = await ref.read(propertiesRepositoryProvider).setAgreement(
            propertyId: widget.propertyId,
            apartmentId: widget.apartmentId,
            text: text,
          );
      ref.invalidate(myPropertyProvider(widget.propertyId));
      ref.invalidate(apartmentsProvider(widget.propertyId));
      if (widget.apartmentId case final id?) {
        ref.invalidate(apartmentProvider(id));
        ref.invalidate(apartmentTenanciesProvider(id));
      }
      if (!mounted) return;
      showMessage(
        context,
        count == 0
            ? 'Agreement saved'
            : 'Agreement saved. $count tenant${count == 1 ? '' : 's'} will be asked to accept the new version.',
      );
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final editable = widget.canEdit && (!_forUnit || _ownText);

    return Scaffold(
      appBar: AppBar(
        title: Text(_forUnit ? 'Agreement for ${widget.unitName}' : 'Tenancy agreement'),
        actions: [
          IconButton(tooltip: 'Preview', icon: const Icon(Icons.visibility_rounded), onPressed: _preview),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          if (_forUnit) ...[
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('Property\'s agreement')),
                ButtonSegment(value: true, label: Text('Own for this unit')),
              ],
              selected: {_ownText},
              onSelectionChanged: widget.canEdit ? (s) => setState(() => _ownText = s.first) : null,
            ),
            const SizedBox(height: 12),
          ],
          AppCard(
            color: AppColors.soft(AppColors.accent),
            child: Text(
              _forUnit && !_ownText
                  ? 'This unit uses the property\'s agreement. Choose "Own for this unit" to write a different one.'
                  : 'Tenants see this before they can use the app, after a summary of their rent and dates. '
                      'If you change it, current tenants must accept the new version. '
                      'This starting text is not legal advice: adapt it to your rules and local law.',
              style: text.bodySmall,
            ),
          ),
          const SizedBox(height: 12),
          if (editable) ...[
            Text('Tap to insert, filled in for each tenant:', style: text.bodySmall),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final MapEntry(key: field, value: label) in agreementFields.entries)
                  ActionChip(label: Text(label), onPressed: () => _insert(field)),
                ActionChip(label: const Text('Heading'), onPressed: () => _insert('\n# ')),
              ],
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            enabled: editable,
            minLines: 14,
            maxLines: null,
            textCapitalization: TextCapitalization.sentences,
            style: text.bodyMedium,
            decoration: const InputDecoration(alignLabelWithHint: true),
          ),
          if (editable && !_forUnit)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _controller.text = defaultAgreementTemplate),
                child: const Text('Start again from the app\'s text'),
              ),
            ),
          const SizedBox(height: 12),
          if (widget.canEdit)
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Save agreement'),
            ),
        ],
      ),
    );
  }
}
