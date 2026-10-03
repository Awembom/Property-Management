import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/admin/providers/admin_providers.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';
import 'package:rental_app/shared/widgets/user_avatar.dart';

/// The Profile tab: who I am, my details (name, phone), and a menu:
/// change password, admin (admins only), invite code (tenants only), log out.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AsyncValue has three states: loading, error, data. `.when` makes us
    // handle all three.
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: profile.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Could not load your profile.'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => ref.invalidate(myProfileProvider),
                  child: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                // Always offer a way out, e.g. if this account was deleted.
                TextButton.icon(
                  onPressed: () => ref.read(authRepositoryProvider).signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Log out'),
                ),
              ],
            ),
          ),
        ),
        data: (profile) => _ProfileBody(profile: profile),
      ),
    );
  }
}

/// A separate widget so the text fields are filled with the loaded values
/// exactly once, when the profile first arrives.
class _ProfileBody extends ConsumerStatefulWidget {
  const _ProfileBody({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ProfileBody> createState() => _ProfileBodyState();
}

class _ProfileBodyState extends ConsumerState<_ProfileBody> {
  late final _nameController = TextEditingController(text: widget.profile.fullName);
  late final _phoneController = TextEditingController(text: widget.profile.phone);
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final sent = await ref.read(myProfileProvider.notifier).save(
            fullName: _nameController.text,
            phone: _phoneController.text,
          );
      if (mounted) {
        showMessage(
          context,
          sent ? 'Profile saved' : 'Saved on this phone. It will sync when you\'re back online.',
        );
      }
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logOut() async {
    try {
      // The router notices the logout and returns to the welcome screen.
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    final text = Theme.of(context).textTheme;
    final name = profile.fullName ?? profile.username ?? '';
    final type = profile.accountType;
    final isAdmin = ref.watch(isAppAdminProvider).value ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              UserAvatar(name: name.isEmpty ? '?' : name, size: 76),
              const SizedBox(height: 12),
              Text(name.isEmpty ? 'No name yet' : name, style: text.titleLarge),
              if (profile.username != null) Text('@${profile.username}', style: text.bodySmall),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: [
                  if (type != null) StatusPill(label: type.label, color: type.color, icon: type.icon),
                  if (isAdmin)
                    const StatusPill(
                      label: 'App admin',
                      color: AppColors.accent,
                      icon: Icons.admin_panel_settings_rounded,
                    ),
                ],
              ),
            ],
          ),
        ),

        const SectionTitle('My details'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _nameController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Full name',
                  prefixIcon: Icon(Icons.badge_outlined),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      )
                    : const Text('Save'),
              ),
            ],
          ),
        ),

        const SectionTitle('Settings'),
        _MenuItem(
          icon: Icons.key_rounded,
          color: AppColors.primary,
          title: 'Change password',
          onTap: () => context.push(AppRoutes.changePassword),
        ),
        _MenuItem(
          icon: Icons.qr_code_scanner_rounded,
          color: AppColors.paid,
          title: 'Check a receipt',
          subtitle: 'Scan its QR code to see if it\'s genuine',
          onTap: () => context.push(AppRoutes.checkReceipt),
        ),
        // Only tenants join with invite codes.
        if (type == AccountType.tenant)
          _MenuItem(
            icon: Icons.vpn_key_rounded,
            color: AppColors.accent,
            title: 'Enter an invite code',
            onTap: () => context.push(AppRoutes.joinWithCode),
          ),
        if (isAdmin)
          _MenuItem(
            icon: Icons.admin_panel_settings_rounded,
            color: AppColors.accent,
            title: 'Admin',
            subtitle: 'Activity, properties, people',
            onTap: () => context.push(AppRoutes.admin),
          ),
        _MenuItem(
          icon: Icons.logout_rounded,
          color: AppColors.overdue,
          title: 'Log out',
          onTap: _saving ? null : _logOut,
          danger: true,
        ),
      ],
    );
  }
}

class _MenuItem extends StatelessWidget {
  const _MenuItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.danger = false,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        onTap: onTap,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.soft(color)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: danger ? AppColors.overdue : null,
                        ),
                  ),
                  if (subtitle != null) Text(subtitle!, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
            if (!danger) const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
          ],
        ),
      ),
    );
  }
}
