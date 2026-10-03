import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/data/receipts_repository.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// The tenant says what's wrong with a receipt. This opens a ticket about
/// the receipt that the landlord (and caretakers who may see money) answer.
/// Needs a connection: the database checks the 24 hours when it arrives.
class ReportReceiptProblemPage extends ConsumerStatefulWidget {
  const ReportReceiptProblemPage({super.key, required this.tenancyId, required this.paymentId});

  final String tenancyId;
  final String paymentId;

  @override
  ConsumerState<ReportReceiptProblemPage> createState() => _ReportReceiptProblemPageState();
}

class _ReportReceiptProblemPageState extends ConsumerState<ReportReceiptProblemPage> {
  final _detailsController = TextEditingController();
  ReceiptProblem? _problem;
  bool _busy = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  bool get _ready => _problem != null && _detailsController.text.trim().isNotEmpty;

  Future<void> _submit() async {
    setState(() => _busy = true);
    try {
      final ticketId = await ref.read(receiptsRepositoryProvider).reportProblem(
            paymentId: widget.paymentId,
            problem: _problem!,
            details: _detailsController.text.trim(),
          );
      ref.invalidate(myRentalDetailsProvider(widget.tenancyId));
      ref.invalidate(tenancyTicketsProvider(widget.tenancyId));
      if (!mounted) return;
      showMessage(context, 'Problem reported. Your landlord will answer in the ticket.');
      // Straight to the conversation about it (instead of this form).
      context.pushReplacement(AppRoutes.ticket(ticketId));
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Report a problem')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('What is wrong with this receipt?', style: text.titleMedium),
          const SizedBox(height: 12),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: RadioGroup<ReceiptProblem>(
              groupValue: _problem,
              onChanged: (value) => setState(() => _problem = value),
              child: Column(
                children: [
                  for (final problem in ReceiptProblem.values)
                    RadioListTile<ReceiptProblem>(value: problem, title: Text(problem.label)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _detailsController,
            minLines: 3,
            maxLines: 6,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Explain',
              hintText: 'e.g. I paid 120,000 by mobile money on 1 Oct, not 100,000.',
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Your landlord sees this as a ticket and can answer you there. If the receipt '
            'was wrong, they cancel it and give you a corrected one.',
            style: text.bodySmall,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.overdue),
            onPressed: _ready && !_busy ? _submit : null,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Send to my landlord'),
          ),
        ],
      ),
    );
  }
}
