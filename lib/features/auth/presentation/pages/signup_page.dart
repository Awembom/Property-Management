import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/features/auth/presentation/widgets/password_field.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Create an account. Supabase then emails a 6-digit code, which the user
/// enters on the next screen (VerifyEmailPage).
class SignupPage extends ConsumerStatefulWidget {
  const SignupPage({super.key});

  @override
  ConsumerState<SignupPage> createState() => _SignupPageState();
}

class _SignupPageState extends ConsumerState<SignupPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailController.text.trim();

    try {
      final needsCode = await ref.read(authRepositoryProvider).signUp(
            email: email,
            password: _passwordController.text,
            fullName: _nameController.text.trim(),
          );
      // If no code is needed, the user is already logged in and the router
      // takes them into the app by itself.
      if (needsCode && mounted) {
        context.go(AppRoutes.verifyEmailFor(email));
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create account'),
        leading: BackButton(onPressed: () => context.go(AppRoutes.login)),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _nameController,
                        validator: validateFullName,
                        textCapitalization: TextCapitalization.words,
                        autofillHints: const [AutofillHints.name],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Full name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _emailController,
                        validator: validateEmail,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      PasswordField(
                        controller: _passwordController,
                        validator: validateNewPassword,
                        isNewPassword: true,
                        onSubmitted: _loading ? null : _signUp,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _signUp,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
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
          ),
        ),
      ),
    );
  }
}
