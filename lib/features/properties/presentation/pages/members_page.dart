import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/properties/presentation/widgets/role_chip.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// The property's staff. Everyone can see the list; only owners can add,
/// change or remove members.
class MembersPage extends ConsumerWidget {
  const MembersPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId));
    final members = ref.watch(propertyMembersProvider(propertyId));
    final canManage = myProperty.value?.access.canManageMembers ?? false;
    final myUserId = ref.read(authRepositoryProvider).currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Team')),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(propertyMembersProvider(propertyId)),
        ),
        data: (members) => RefreshIndicator(
          onRefresh: () => ref.refresh(propertyMembersProvider(propertyId).future),
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: members.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final member = members[index];
              final isMe = member.userId == myUserId;
              return ListTile(
                leading: CircleAvatar(
                  child: Text(member.displayName.characters.first.toUpperCase()),
                ),
                title: Text(isMe ? '${member.displayName} (you)' : member.displayName),
                subtitle: Text([
                  if (member.email != null && member.fullName != null) member.email!,
                  if (member.role == MembershipRole.caretaker)
                    member.canRecordPayments
                        ? 'Can record payments'
                        : 'Cannot record payments',
                ].join('\n')),
                isThreeLine: member.role == MembershipRole.caretaker &&
                    member.email != null &&
                    member.fullName != null,
                trailing: RoleChip(role: member.role),
                onTap: canManage
                    ? () => _showEditMemberSheet(context, ref, member, isMe: isMe)
                    : null,
              );
            },
          ),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showAddMemberSheet(context, ref),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add member'),
            )
          : null,
    );
  }

  Future<void> _showAddMemberSheet(BuildContext context, WidgetRef ref) async {
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true, // lets the sheet move up above the keyboard
      builder: (_) => _MemberSheet(propertyId: propertyId),
    );
    if (result == _SheetResult.saved && context.mounted) {
      ref.invalidate(propertyMembersProvider(propertyId));
      showMessage(context, 'Member added');
    }
  }

  Future<void> _showEditMemberSheet(
    BuildContext context,
    WidgetRef ref,
    Member member, {
    required bool isMe,
  }) async {
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberSheet(propertyId: propertyId, existing: member, isMe: isMe),
    );
    if (result == null || !context.mounted) return;

    if (isMe && result == _SheetResult.removed) {
      // I left the property: I can't see it any more, so go back to my list.
      ref.invalidate(myPropertiesProvider);
      showMessage(context, 'You left the property');
      context.go(AppRoutes.properties);
      return;
    }
    ref.invalidate(propertyMembersProvider(propertyId));
    // My own role may have changed, which changes what I can do.
    if (isMe) ref.invalidate(myPropertyProvider(propertyId));
  }
}

/// What the member sheet did (null = closed without changes).
enum _SheetResult { saved, removed }

/// Bottom sheet to add a member (existing == null) or change/remove one.
class _MemberSheet extends ConsumerStatefulWidget {
  const _MemberSheet({required this.propertyId, this.existing, this.isMe = false});

  final String propertyId;
  final Member? existing;
  final bool isMe;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  late MembershipRole _role = widget.existing?.role ?? MembershipRole.caretaker;
  late bool _canRecordPayments = widget.existing?.canRecordPayments ?? false;
  bool _busy = false;

  bool get _isAdding => widget.existing == null;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  /// Runs [action]; closes the sheet with [result] on success, shows the
  /// error otherwise (e.g. "A property must keep at least one owner").
  Future<void> _run(Future<void> Function() action, _SheetResult result) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final repository = ref.read(propertiesRepositoryProvider);
    await _run(() {
      if (_isAdding) {
        return repository.addMember(
          propertyId: widget.propertyId,
          email: _emailController.text.trim(),
          role: _role,
          canRecordPayments: _canRecordPayments,
        );
      }
      return repository.updateMember(
        membershipId: widget.existing!.membershipId,
        role: _role,
        canRecordPayments: _canRecordPayments,
      );
    }, _SheetResult.saved);
  }

  Future<void> _remove() async {
    final member = widget.existing!;
    final confirmed = await showConfirmDialog(
      context,
      title: widget.isMe ? 'Leave this property?' : 'Remove ${member.displayName}?',
      message: widget.isMe
          ? 'You will lose access to this property.'
          : 'They will lose access to this property.',
      confirmLabel: widget.isMe ? 'Leave' : 'Remove',
      destructive: true,
    );
    if (!confirmed) return;
    await _run(
      () => ref.read(propertiesRepositoryProvider).removeMember(member.membershipId),
      _SheetResult.removed,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Keep the sheet above the on-screen keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _isAdding ? 'Add member' : widget.existing!.displayName,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 16),
                if (_isAdding) ...[
                  TextFormField(
                    controller: _emailController,
                    validator: validateEmail,
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Their email',
                      helperText: 'They must already have an account in the app.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Role'),
                const SizedBox(height: 8),
                SegmentedButton<MembershipRole>(
                  segments: [
                    for (final role in MembershipRole.values)
                      ButtonSegment(value: role, label: Text(role.label)),
                  ],
                  selected: {_role},
                  onSelectionChanged: (selection) =>
                      setState(() => _role = selection.first),
                ),
                const SizedBox(height: 8),
                Text(
                  switch (_role) {
                    MembershipRole.owner =>
                      'Full control, including deleting the property and managing the team.',
                    MembershipRole.manager =>
                      'Manages apartments, tenants and payments. Can\'t manage the team.',
                    MembershipRole.caretaker =>
                      'Handles day-to-day tasks and tickets. Never sees money amounts.',
                  },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_role == MembershipRole.caretaker)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Can record payments'),
                    subtitle: const Text('Record rent payments (still without seeing totals).'),
                    value: _canRecordPayments,
                    onChanged: (value) => setState(() => _canRecordPayments = value),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isAdding ? 'Add' : 'Save'),
                ),
                if (!_isAdding) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    onPressed: _busy ? null : _remove,
                    child: Text(widget.isMe ? 'Leave property' : 'Remove from property'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
