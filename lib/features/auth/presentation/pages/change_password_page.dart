import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/features/auth/presentation/widgets/password_field.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Choose a new password.
///
/// Opened from the profile, or forced by the router after an owner/manager
/// gave this user a temporary password ([forced]): then there's no way back
/// into the app until a new password is set (only Log out).
class ChangePasswordPage extends ConsumerStatefulWidget {
  const ChangePasswordPage({super.key, this.forced = false});

  final bool forced;

  @override
  ConsumerState<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends ConsumerState<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref.read(authRepositoryProvider).changePassword(_passwordController.text);
      if (!mounted) return;
      showMessage(context, 'Password changed');
      // When forced, the router lets the user in once the flag is cleared;
      // otherwise go back to the profile.
      if (!widget.forced && context.canPop()) context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New password'),
        automaticallyImplyLeading: !widget.forced,
        actions: [
          if (widget.forced)
            TextButton(
              onPressed: () => ref.read(authRepositoryProvider).signOut(),
              child: const Text('Log out'),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            if (widget.forced) ...[
              Card(
                color: AppColors.solidSoft(context, AppColors.dueSoon),
                child: const ListTile(
                  leading: Icon(Icons.key_rounded, color: AppColors.dueSoon),
                  title: Text('You logged in with a temporary password'),
                  subtitle: Text('Choose your own password to continue.'),
                ),
              ),
              const SizedBox(height: 24),
            ],
            PasswordField(
              controller: _passwordController,
              label: 'New password',
              validator: validateNewPassword,
              isNewPassword: true,
            ),
            const SizedBox(height: 16),
            PasswordField(
              controller: _confirmController,
              label: 'Repeat new password',
              isNewPassword: true,
              validator: (value) =>
                  value != _passwordController.text ? 'The passwords don\'t match' : null,
              onSubmitted: _saving ? null : _save,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save new password'),
            ),
          ],
        ),
      ),
    );
  }
}
