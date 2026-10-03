import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/data/tenant_invite.dart';
import 'package:rental_app/features/tenant_access/presentation/widgets/temporary_password_dialog.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// On the tenancy page (owners/managers): get the tenant into the app.
///
/// * Not linked yet: create an invite code to give them, see/copy/cancel it.
/// * Linked: reset their password, or disconnect the account.
class TenantAppAccessCard extends ConsumerWidget {
  const TenantAppAccessCard({
    super.key,
    required this.propertyId,
    required this.tenant,
    required this.onChanged,
  });

  final String propertyId;
  final Tenant tenant;

  /// Called after linking changed, so the page reloads the tenant.
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return tenant.hasAccount ? _linked(context, ref) : _notLinked(context, ref);
  }

  // The repository is read inside each button handler (not while building),
  // so drawing the card never needs a Supabase connection.
  TenantAccessRepository _repository(WidgetRef ref) => ref.read(tenantAccessRepositoryProvider);

  Widget _linked(BuildContext context, WidgetRef ref) {
    return Card(
      color: AppColors.solidSoft(context, AppColors.primary),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Title(icon: Icons.phone_android_rounded, text: 'Uses the app'),
            const SizedBox(height: 4),
            Text('${tenant.fullName} can see their rent and receipts in the app.'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => resetPasswordFlow(
                    context,
                    personName: tenant.fullName,
                    reset: () => _repository(ref).resetPassword(
                      propertyId: propertyId,
                      userId: tenant.userId!,
                    ),
                  ),
                  icon: const Icon(Icons.key_rounded),
                  label: const Text('Reset password'),
                ),
                TextButton(
                  onPressed: () async {
                    final confirmed = await showConfirmDialog(
                      context,
                      title: 'Disconnect the app account?',
                      message: 'Use this if the wrong person joined with the code. '
                          'They stop seeing this tenancy. You can invite again afterwards.',
                      confirmLabel: 'Disconnect',
                      destructive: true,
                    );
                    if (!confirmed) return;
                    try {
                      await _repository(ref).unlinkAccount(tenant.id);
                      onChanged();
                    } catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                  child: const Text('Disconnect'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _notLinked(BuildContext context, WidgetRef ref) {
    final invite = ref.watch(openInviteProvider(tenant.id));

    Future<void> create() async {
      try {
        await _repository(ref).createInvite(tenant.id);
        ref.invalidate(openInviteProvider(tenant.id));
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    Future<void> cancel() async {
      try {
        await _repository(ref).cancelInvite(tenant.id);
        ref.invalidate(openInviteProvider(tenant.id));
      } catch (e) {
        if (context.mounted) showError(context, e);
      }
    }

    return Card(
      color: AppColors.solidSoft(context, AppColors.accent),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _Title(icon: Icons.mobile_off_rounded, text: 'Not using the app yet'),
            const SizedBox(height: 4),
            invite.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(8),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => Text('Could not load the invite code. Pull down to refresh.',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
              data: (invite) => invite == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('Invite ${tenant.fullName}: they sign up with a username, '
                            'then enter the code you give them.'),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.accent),
                          onPressed: create,
                          icon: const Icon(Icons.qr_code_2_rounded),
                          label: const Text('Create invite code'),
                        ),
                      ],
                    )
                  : _OpenInvite(invite: invite, onNewCode: create, onCancel: cancel),
            ),
          ],
        ),
      ),
    );
  }
}

class _OpenInvite extends StatelessWidget {
  const _OpenInvite({required this.invite, required this.onNewCode, required this.onCancel});

  final TenantInvite invite;
  final VoidCallback onNewCode;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Give them this code (SMS, WhatsApp or on paper):'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: SelectableText(
            invite.code,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.accent,
                ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Works once, until ${formatDate(invite.expiresAt)}.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          children: [
            TextButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: invite.code));
                if (context.mounted) showMessage(context, 'Code copied');
              },
              icon: const Icon(Icons.copy_rounded),
              label: const Text('Copy'),
            ),
            TextButton.icon(
              onPressed: onNewCode,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('New code'),
            ),
            TextButton(onPressed: onCancel, child: const Text('Cancel code')),
          ],
        ),
      ],
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    );
  }
}
