import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/features/auth/presentation/widgets/password_field.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Email + password login.
///
/// On success we don't navigate ourselves: Supabase reports "signed in", and
/// the router's redirect (app_router.dart) moves the user into the app.
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _logIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _loading = true);
    final email = _emailController.text.trim();
    final auth = ref.read(authRepositoryProvider);

    try {
      await auth.signIn(email: email, password: _passwordController.text);
    } on AuthException catch (e) {
      if (!mounted) return;
      if (e.code == 'email_not_confirmed') {
        // Signed up earlier but never entered the code: send a fresh one.
        await _sendNewCodeAndGoToVerify(email);
      } else {
        showError(context, e);
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendNewCodeAndGoToVerify(String email) async {
    try {
      await ref.read(authRepositoryProvider).resendSignupCode(email);
      if (!mounted) return;
      showMessage(context, 'Your email isn\'t confirmed yet. We sent you a new code.');
    } catch (e) {
      // e.g. rate limit: a code was sent recently. They can still use it.
      if (mounted) showError(context, e);
    }
    if (mounted) context.go(AppRoutes.verifyEmailFor(email));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Form(
                key: _formKey,
                // AutofillGroup lets the phone's password manager fill both fields.
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.home_work_rounded, size: 72),
                      const SizedBox(height: 16),
                      Text(
                        'Rental App',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Manage properties, tenants, and payments in one place.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 32),
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
                        validator: validatePasswordEntered,
                        onSubmitted: _loading ? null : _logIn,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _loading ? null : _logIn,
                        child: _loading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Log in'),
                      ),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: _loading ? null : () => context.go(AppRoutes.signup),
                        child: const Text('New here? Create an account'),
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
