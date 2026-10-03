import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/repairs/data/repairs_repository.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/data/tickets_repository.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/date_field.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Log a repair on a unit: what was done, when, what it cost (staff who may
/// see money), which issue it fixed, and optionally a bill to the tenant.
/// [ticketId] pre-selects the issue (when opened from a ticket).
class NewRepairPage extends ConsumerStatefulWidget {
  const NewRepairPage({super.key, required this.propertyId, required this.apartmentId, this.ticketId});

  final String propertyId;
  final String apartmentId;
  final String? ticketId;

  @override
  ConsumerState<NewRepairPage> createState() => _NewRepairPageState();
}

class _NewRepairPageState extends ConsumerState<NewRepairPage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _detailsController = TextEditingController();
  final _costController = TextEditingController();
  final _billController = TextEditingController();
  DateTime _repairedOn = today();
  DateTime _billDue = today().add(const Duration(days: 14));
  late String? _ticketId = widget.ticketId;
  bool _billTenant = false;

  /// Opened from an issue: mark it resolved when the repair is saved.
  late bool _resolveIssue = widget.ticketId != null;
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _detailsController.dispose();
    _costController.dispose();
    _billController.dispose();
    super.dispose();
  }

  Future<void> _save(String currency) async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(repairsRepositoryProvider).add(
            apartmentId: widget.apartmentId,
            title: _titleController.text.trim(),
            details: _detailsController.text.trim().isEmpty ? null : _detailsController.text.trim(),
            repairedOn: _repairedOn,
            cost: _costController.text.trim().isEmpty ? null : parseMoney(_costController.text, currency),
            ticketId: _ticketId,
            billAmount: _billTenant ? parseMoney(_billController.text, currency) : null,
            billDue: _billTenant ? _billDue : null,
          );
      final ticketId = _ticketId;
      if (_resolveIssue && ticketId != null) {
        await ref.read(ticketsRepositoryProvider).setStatus(ticketId, TicketStatus.resolved);
        ref.invalidate(ticketProvider(ticketId));
        ref.invalidate(propertyTicketsProvider(widget.propertyId));
        ref.invalidate(unitTicketsProvider(widget.apartmentId));
      }
      ref.invalidate(unitRepairsProvider(widget.apartmentId));
      ref.invalidate(unitBillsProvider(widget.apartmentId));
      ref.invalidate(propertyBillsProvider(widget.propertyId));
      if (!mounted) return;
      showMessage(context, _billTenant ? 'Repair logged and the tenant billed' : 'Repair logged');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final myProperty = ref.watch(myPropertyProvider(widget.propertyId)).value;
    final currency = myProperty?.property.currency ?? 'XAF';
    final canSeeMoney = myProperty?.access.canSeeMoney ?? false;
    final occupied = (ref.watch(apartmentTenanciesProvider(widget.apartmentId)).value ?? const [])
        .any((t) => t.isActive);
    final issues = ref.watch(unitTicketsProvider(widget.apartmentId)).value ?? const <Ticket>[];

    String? moneyValidator(String? value, {required bool required}) {
      if ((value ?? '').trim().isEmpty) return required ? 'Enter an amount' : null;
      final amount = parseMoney(value!, currency);
      return amount == null || amount < 0 || (required && amount == 0) ? 'Enter a valid amount' : null;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Log a repair')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            TextFormField(
              controller: _titleController,
              textCapitalization: TextCapitalization.sentences,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Say what was repaired' : null,
              decoration: const InputDecoration(labelText: 'What was repaired', hintText: 'e.g. Replaced kitchen tap'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _detailsController,
              textCapitalization: TextCapitalization.sentences,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Details (optional)'),
            ),
            const SizedBox(height: 12),
            DateField(
              label: 'Repaired on',
              value: _repairedOn,
              lastDate: today(),
              onChanged: (d) => setState(() => _repairedOn = d),
            ),
            if (canSeeMoney) ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => moneyValidator(v, required: false),
                decoration: InputDecoration(labelText: 'What it cost you (optional)', suffixText: currency),
              ),
            ],
            if (issues.isNotEmpty) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                // (Only a value that is in the list, or the dropdown fails.)
                initialValue: issues.any((i) => i.id == _ticketId) ? _ticketId : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Issue it fixed (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final issue in issues)
                    DropdownMenuItem(value: issue.id, child: Text(issue.title, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (value) => setState(() {
                  _ticketId = value;
                  _resolveIssue = value != null;
                }),
              ),
              if (_ticketId != null)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _resolveIssue,
                  onChanged: (on) => setState(() => _resolveIssue = on),
                  title: const Text('Mark the issue resolved'),
                ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _billTenant,
              onChanged: occupied ? (on) => setState(() => _billTenant = on) : null,
              title: const Text('Bill the tenant for it'),
              subtitle: Text(occupied
                  ? 'Adds a "Repairs" bill to this unit. You can waive it later.'
                  : 'No one lives here, so there is no one to bill.'),
            ),
            if (_billTenant) ...[
              TextFormField(
                controller: _billController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) => moneyValidator(v, required: true),
                decoration: InputDecoration(labelText: 'Amount the tenant pays', suffixText: currency),
              ),
              const SizedBox(height: 12),
              DateField(
                label: 'Bill due on',
                value: _billDue,
                firstDate: today(),
                onChanged: (d) => setState(() => _billDue = d),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : () => _save(currency),
              child: _saving
                  ? const SizedBox.square(
                      dimension: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                    )
                  : const Text('Save repair'),
            ),
          ],
        ),
      ),
    );
  }
}
