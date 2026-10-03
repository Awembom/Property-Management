import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/pages/account_type_page.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/features/auth/presentation/widgets/password_field.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Sign-up, step 2 of 2: name, username and password, for the account type
/// chosen on the previous screen. No email: the user is logged in straight
/// away and the router takes them into the app.
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key, required this.accountType});

  final AccountType accountType;

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    try {
      await ref.read(authRepositoryProvider).signUp(
            username: _usernameController.text,
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
            accountType: widget.accountType,
          );
      // Logged in: the router moves the user into the app by itself.
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final type = widget.accountType;
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: AutofillGroup(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              children: [
                const SignupStepDots(step: 2),
                const SizedBox(height: 20),
                Text('Your details', style: text.headlineSmall),
                const SizedBox(height: 10),
                // The chosen type, with a way back to change it.
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.soft(type.color),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(type.icon, size: 16, color: type.color),
                          const SizedBox(width: 6),
                          Text(type.label,
                              style: TextStyle(color: type.color, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: _loading ? null : () => context.pop(),
                      child: const Text('Change'),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                TextFormField(
                  controller: _nameController,
                  validator: validateFullName,
                  textCapitalization: TextCapitalization.words,
                  autofillHints: const [AutofillHints.name],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Full name',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _usernameController,
                  validator: validateUsername,
                  autocorrect: false,
                  autofillHints: const [AutofillHints.newUsername],
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    helperText: 'You log in with this. Letters, numbers, dots and _',
                    helperMaxLines: 2,
                    prefixIcon: Icon(Icons.alternate_email_rounded),
                  ),
                ),
                const SizedBox(height: 14),
                PasswordField(
                  controller: _passwordController,
                  validator: validateNewPassword,
                  isNewPassword: true,
                  onSubmitted: _loading ? null : _signUp,
                ),
                const SizedBox(height: 26),
                FilledButton(
                  onPressed: _loading ? null : _signUp,
                  child: _loading
                      ? const SizedBox.square(
                          dimension: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                        )
                      : const Text('Create account'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _loading ? null : () => context.go(AppRoutes.login),
                  child: const Text('Already have an account? Log in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
