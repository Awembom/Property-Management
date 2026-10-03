import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/shared/widgets/gradient_header.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// For tenants: enter the invite code from the landlord. This links the
/// account to their tenancy, so they can see their apartment and rent.
class JoinWithCodePage extends ConsumerStatefulWidget {
  const JoinWithCodePage({super.key});

  @override
  ConsumerState<JoinWithCodePage> createState() => _JoinWithCodePageState();
}

class _JoinWithCodePageState extends ConsumerState<JoinWithCodePage> {
  final _formKey = GlobalKey<FormState>();
  final _codeController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _busy = true);
    try {
      final result =
          await ref.read(tenantAccessRepositoryProvider).redeemInvite(_codeController.text);
      if (!mounted) return;
      if (!result.ok) {
        showError(context, StateError(result.error ?? 'That code didn\'t work.'));
        return;
      }
      ref.invalidate(myRentalsProvider);
      showMessage(context, 'Welcome! You\'re linked to ${result.propertyName}.');
      context.pop();
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join as a tenant')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const GradientHeader(
              color: AppColors.accent,
              icon: Icons.vpn_key_rounded,
              title: 'Enter your invite code',
              subtitle: 'Your landlord gives you this code. It links your account '
                  'to your apartment, so you can see your rent and receipts.',
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _codeController,
              autofocus: true,
              autocorrect: false,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(letterSpacing: 2),
              validator: (value) =>
                  (value?.trim() ?? '').length < 6 ? 'Enter the code, e.g. TEN-4K7Q9M' : null,
              onFieldSubmitted: (_) => _busy ? null : _join(),
              decoration: const InputDecoration(hintText: 'TEN-XXXXXX'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
              onPressed: _busy ? null : _join,
              icon: _busy
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.link_rounded),
              label: const Text('Join'),
            ),
          ],
        ),
      ),
    );
  }
}
