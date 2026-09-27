import 'package:flutter/material.dart';

/// Asks "Are you sure?" and returns true only if the user confirms.
///
/// [destructive] colours the confirm button red for irreversible actions.
/// If [typeToConfirm] is given, the user must type that exact text before the
/// confirm button enables (used for deleting a whole property).
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
  bool destructive = false,
  String? typeToConfirm,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      destructive: destructive,
      typeToConfirm: typeToConfirm,
    ),
  );
  return confirmed ?? false; // null = dismissed by tapping outside
}

class _ConfirmDialog extends StatefulWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.destructive,
    this.typeToConfirm,
  });

  final String title;
  final String message;
  final String confirmLabel;
  final bool destructive;
  final String? typeToConfirm;

  @override
  State<_ConfirmDialog> createState() => _ConfirmDialogState();
}

class _ConfirmDialogState extends State<_ConfirmDialog> {
  String _typed = '';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final canConfirm = widget.typeToConfirm == null ||
        _typed.trim() == widget.typeToConfirm!.trim();

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          if (widget.typeToConfirm != null) ...[
            const SizedBox(height: 16),
            Text('Type "${widget.typeToConfirm}" to confirm:'),
            const SizedBox(height: 8),
            TextField(
              autofocus: true,
              onChanged: (value) => setState(() => _typed = value),
              decoration: const InputDecoration(border: OutlineInputBorder()),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: widget.destructive
              ? FilledButton.styleFrom(
                  backgroundColor: colors.error,
                  foregroundColor: colors.onError,
                )
              : null,
          onPressed: canConfirm ? () => Navigator.of(context).pop(true) : null,
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}
