import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/data/bills_repository.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/presentation/tenancy_validators.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/date_field.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Create a bill: type, title, amount per apartment, due date, and which
/// occupied apartments (all, or chosen ones).
class NewBillPage extends ConsumerStatefulWidget {
  const NewBillPage({super.key, required this.propertyId, this.tenancyId});

  final String propertyId;

  /// From a unit page: the bill starts as one for that unit only.
  final String? tenancyId;

  @override
  ConsumerState<NewBillPage> createState() => _NewBillPageState();
}

class _NewBillPageState extends ConsumerState<NewBillPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();
  BillType? _type;
  DateTime _dueDate = today().add(const Duration(days: 14));
  late bool _everyone = widget.tenancyId == null;
  late final Set<String> _chosenTenancyIds = {?widget.tenancyId};
  String? _error;
  bool _saving = false;

  /// On: each apartment gets its own amount (e.g. water by meter reading).
  bool _perUnit = false;

  /// tenancy id -> its amount field (per-unit mode).
  final _unitAmounts = <String, TextEditingController>{};

  TextEditingController _unitAmount(String tenancyId) =>
      _unitAmounts.putIfAbsent(tenancyId, () => TextEditingController(text: _amountController.text));

  @override
  void dispose() {
    _titleController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    for (final c in _unitAmounts.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _chooseType(BillType type) {
    setState(() {
      _type = type;
      // Suggest a title like "Water - October 2026".
      _titleController.text = '${type.name} - ${DateFormat('MMMM yyyy').format(today())}';
    });
  }

  Future<void> _save(String currency, List<String> targetTenancyIds) async {
    setState(() {
      _error = _type == null
          ? 'Choose the type of bill'
          : (!_everyone && _chosenTenancyIds.isEmpty ? 'Choose at least one apartment' : null);
    });
    if (!_formKey.currentState!.validate() || _error != null) return;
    setState(() => _saving = true);
    try {
      final repository = ref.read(billsRepositoryProvider);
      if (_perUnit) {
        await repository.createBillAmounts(
          propertyId: widget.propertyId,
          billTypeId: _type!.id,
          dueDate: _dueDate,
          amounts: {for (final id in targetTenancyIds) id: parseMoney(_unitAmount(id).text, currency)!},
          title: _titleController.text.trim(),
          notes: trimToNull(_notesController.text),
        );
      } else {
        await repository.createBill(
          propertyId: widget.propertyId,
          billTypeId: _type!.id,
          dueDate: _dueDate,
          amount: parseMoney(_amountController.text, currency)!,
          title: _titleController.text.trim(),
          notes: trimToNull(_notesController.text),
          tenancyIds: _everyone ? const [] : _chosenTenancyIds.toList(),
        );
      }
      ref.invalidate(propertyBillsProvider(widget.propertyId));
      if (!mounted) return;
      showMessage(context, 'Bill created. Tenants can see it.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currency = ref.watch(myPropertyProvider(widget.propertyId)).value?.property.currency ?? 'XAF';
    final types = (ref.watch(billTypesProvider(widget.propertyId)).value ?? const <BillType>[])
        .where((t) => t.enabled)
        .toList();
    final occupied = (ref.watch(apartmentsProvider(widget.propertyId)).value ?? const [])
        .where((a) => a.activeTenancy != null)
        .toList();
    final text = Theme.of(context).textTheme;
    final targets = [
      for (final item in occupied)
        if (_everyone || _chosenTenancyIds.contains(item.activeTenancy!.id)) item,
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('New bill')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            Text('Type of bill', style: text.titleSmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in types)
                  ChoiceChip(
                    avatar: Icon(type.icon, size: 18, color: _type?.id == type.id ? AppColors.primary : AppColors.muted),
                    label: Text(type.name),
                    selected: _type?.id == type.id,
                    onSelected: (_) => _chooseType(type),
                  ),
              ],
            ),
            if (types.isEmpty)
              Text('All bill types are switched off. Turn one on in Bill types.', style: text.bodySmall),
            const SizedBox(height: 18),
            TextFormField(
              controller: _titleController,
              validator: (v) => (v?.trim() ?? '').isEmpty ? 'Enter a title' : null,
              decoration: const InputDecoration(labelText: 'Title', prefixIcon: Icon(Icons.title_rounded)),
            ),
            const SizedBox(height: 14),
            if (!_perUnit)
              TextFormField(
                controller: _amountController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: rentAmountValidator(currency),
                decoration: InputDecoration(
                  labelText: 'Amount per apartment',
                  suffixText: currency,
                  prefixIcon: const Icon(Icons.payments_outlined),
                ),
              ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _perUnit,
              onChanged: (on) => setState(() => _perUnit = on),
              title: const Text('Different amount for each apartment'),
              subtitle: const Text('e.g. water or electricity by meter reading'),
            ),
            const SizedBox(height: 14),
            DateField(label: 'Due date', value: _dueDate, onChanged: (d) => setState(() => _dueDate = d)),
            const SizedBox(height: 14),
            TextFormField(
              controller: _notesController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Note (optional)', prefixIcon: Icon(Icons.notes_rounded)),
            ),
            const SizedBox(height: 20),
            Text('For', style: text.titleSmall),
            const SizedBox(height: 8),
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: true, label: Text('All occupied (${occupied.length})')),
                const ButtonSegment(value: false, label: Text('Choose')),
              ],
              selected: {_everyone},
              onSelectionChanged: (s) => setState(() => _everyone = s.first),
            ),
            if (!_everyone) ...[
              const SizedBox(height: 12),
              AppCard(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    for (final item in occupied)
                      CheckboxListTile(
                        value: _chosenTenancyIds.contains(item.activeTenancy!.id),
                        onChanged: (on) => setState(() {
                          final id = item.activeTenancy!.id;
                          on == true ? _chosenTenancyIds.add(id) : _chosenTenancyIds.remove(id);
                        }),
                        title: Text('Unit ${item.apartment.name}'),
                        subtitle: Text(item.activeTenancy!.tenantName),
                      ),
                  ],
                ),
              ),
            ],
            if (_perUnit && targets.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Amount for each apartment', style: text.titleSmall),
              const SizedBox(height: 8),
              for (final item in targets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextFormField(
                    controller: _unitAmount(item.activeTenancy!.id),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: rentAmountValidator(currency),
                    decoration: InputDecoration(
                      labelText: 'Unit ${item.apartment.name} · ${item.activeTenancy!.tenantName}',
                      suffixText: currency,
                    ),
                  ),
                ),
            ],
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _saving
                  ? null
                  : () => _save(currency, [for (final t in targets) t.activeTenancy!.id]),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Create bill'),
            ),
          ],
        ),
      ),
    );
  }
}
