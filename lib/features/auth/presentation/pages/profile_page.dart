import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// Shows and edits the logged-in user's name and phone, plus Log out.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // AsyncValue has three states: loading, error, data. `.when` makes us
    // handle all three.
    final profile = ref.watch(myProfileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My profile')),
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
              ],
            ),
          ),
        ),
        data: (profile) => _ProfileForm(profile: profile),
      ),
    );
  }
}

/// A separate widget so the text fields are filled with the loaded values
/// exactly once, when the profile first arrives.
class _ProfileForm extends ConsumerStatefulWidget {
  const _ProfileForm({required this.profile});

  final Profile profile;

  @override
  ConsumerState<_ProfileForm> createState() => _ProfileFormState();
}

class _ProfileFormState extends ConsumerState<_ProfileForm> {
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
      await ref.read(myProfileProvider.notifier).save(
            fullName: _nameController.text,
            phone: _phoneController.text,
          );
      if (mounted) showMessage(context, 'Profile saved');
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _logOut() async {
    try {
      // The router notices the logout and returns to the login screen.
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = ref.read(authRepositoryProvider).currentUser?.email ?? '';

    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextFormField(
          initialValue: email,
          enabled: false,
          decoration: const InputDecoration(
            labelText: 'Email',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _nameController,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Full name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'Phone',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox.square(
                  dimension: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
        const SizedBox(height: 32),
        OutlinedButton.icon(
          onPressed: _saving ? null : _logOut,
          icon: const Icon(Icons.logout),
          label: const Text('Log out'),
        ),
      ],
    );
  }
}
