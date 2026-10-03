import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Asks "Reset X's password?", runs [reset] (which returns the temporary
/// password), then shows that password so it can be passed on.
Future<void> resetPasswordFlow(
  BuildContext context, {
  required String personName,
  required Future<String> Function() reset,
}) async {
  final confirmed = await showConfirmDialog(
    context,
    title: 'Reset $personName\'s password?',
    message: 'You\'ll get a temporary password to give them. Their old password '
        'stops working, and they must choose a new one when they log in.',
    confirmLabel: 'Reset password',
  );
  if (!confirmed || !context.mounted) return;

  try {
    final password = await reset();
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _TemporaryPasswordDialog(personName: personName, password: password),
    );
  } catch (e) {
    if (context.mounted) showError(context, e);
  }
}

class _TemporaryPasswordDialog extends StatelessWidget {
  const _TemporaryPasswordDialog({required this.personName, required this.password});

  final String personName;
  final String password;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.key_rounded, color: AppColors.primary, size: 36),
      title: const Text('Temporary password'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Give this to $personName. It is shown only once.'),
          const SizedBox(height: 16),
          SelectableText(
            password,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
          ),
        ],
      ),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: password));
            if (context.mounted) showMessage(context, 'Copied');
          },
          icon: const Icon(Icons.copy_rounded),
          label: const Text('Copy'),
        ),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done')),
      ],
    );
  }
}
