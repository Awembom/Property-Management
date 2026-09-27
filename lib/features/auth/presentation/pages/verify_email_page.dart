import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// The user types the 6-digit code from their confirmation email.
///
/// On success Supabase logs them in, and the router redirect moves them into
/// the app. We never navigate forward from here ourselves.
class VerifyEmailPage extends ConsumerStatefulWidget {
  const VerifyEmailPage({super.key, required this.email});

  /// Passed in the URL (`/verify-email?email=...`) by the signup/login screens.
  final String email;

  @override
  ConsumerState<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends ConsumerState<VerifyEmailPage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _verifying = false;
  bool _resending = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _verifying = true);
    try {
      await ref.read(authRepositoryProvider).verifySignupCode(
            email: widget.email,
            code: _codeController.text.trim(),
          );
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _resend() async {
    setState(() => _resending = true);
    try {
      await ref.read(authRepositoryProvider).resendSignupCode(widget.email);
      if (mounted) showMessage(context, 'New code sent. Check your email.');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _resending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final busy = _verifying || _resending;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm your email'),
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.mark_email_unread_outlined, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'We sent a $kSignupCodeLength-digit code to',
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      widget.email,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'It can take a minute to arrive. Check your spam folder too.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _codeController,
                      validator: validateSignupCode,
                      autofocus: true,
                      keyboardType: TextInputType.number,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      // Only digits, and no more than the code length.
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(kSignupCodeLength),
                      ],
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 28, letterSpacing: 12),
                      onFieldSubmitted: (_) => busy ? null : _verify(),
                      decoration: const InputDecoration(
                        hintText: '••••••',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _verify,
                      child: _verifying
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Confirm'),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: busy ? null : _resend,
                      child: Text(_resending ? 'Sending…' : 'Didn\'t get it? Send a new code'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
