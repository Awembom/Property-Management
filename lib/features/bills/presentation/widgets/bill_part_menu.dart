import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/bills/data/bills_repository.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// The "⋮" menu on one apartment's part of a bill: mark it paid (or not),
/// waive it with a reason, or undo the waiver. Only shown to staff who may
/// record payments (the database checks too). [onChanged] reloads the screen.
class BillPartMenu extends ConsumerWidget {
  const BillPartMenu({
    super.key,
    required this.assignmentId,
    required this.isPaid,
    required this.isWaived,
    required this.onChanged,
  });

  final String assignmentId;
  final bool isPaid;
  final bool isWaived;
  final VoidCallback onChanged;

  Future<void> _run(BuildContext context, WidgetRef ref, String action) async {
    final repository = ref.read(billsRepositoryProvider);
    try {
      switch (action) {
        case 'paid':
          await repository.setPaid(assignmentId, true);
        case 'unpaid':
          await repository.setPaid(assignmentId, false);
        case 'unwaive':
          await repository.setWaived(assignmentId, waived: false);
        case 'waive':
          final reason = await showDialog<String>(context: context, builder: (_) => const _WaiveDialog());
          if (reason == null) return;
          await repository.setWaived(assignmentId, waived: true, reason: reason);
      }
      onChanged();
      if (context.mounted) {
        showMessage(context, switch (action) {
          'paid' => 'Marked paid',
          'unpaid' => 'Marked not paid',
          'waive' => 'Bill waived',
          _ => 'Waiver undone',
        });
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Paid or waive',
      onSelected: (action) => _run(context, ref, action),
      itemBuilder: (_) => [
        if (isPaid)
          const PopupMenuItem(value: 'unpaid', child: Text('Mark not paid'))
        else if (isWaived)
          const PopupMenuItem(value: 'unwaive', child: Text('Undo the waiver'))
        else ...[
          const PopupMenuItem(value: 'paid', child: Text('Mark paid')),
          const PopupMenuItem(value: 'waive', child: Text('Waive (tenant doesn\'t pay)')),
        ],
      ],
    );
  }
}

/// Asks why the bill is waived; returns the reason, or null if cancelled.
class _WaiveDialog extends StatefulWidget {
  const _WaiveDialog();

  @override
  State<_WaiveDialog> createState() => _WaiveDialogState();
}

class _WaiveDialogState extends State<_WaiveDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reason = _controller.text.trim();
    return AlertDialog(
      icon: const Icon(Icons.do_not_disturb_on_rounded, color: AppColors.ended, size: 36),
      title: const Text('Waive this bill?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('The tenant won\'t have to pay it. They see the reason.'),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. The leak was our fault'),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: reason.isEmpty ? null : () => Navigator.of(context).pop(reason),
          child: const Text('Waive'),
        ),
      ],
    );
  }
}
