import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/properties/data/caretaker_permissions.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/properties/presentation/widgets/role_chip.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/presentation/widgets/temporary_password_dialog.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/user_avatar.dart';

/// The property's staff. Everyone can see the list; owners (and caretakers
/// given the "team" permission) add, change or remove members. Owner rows
/// can only be changed by owners.
class MembersPage extends ConsumerWidget {
  const MembersPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId));
    final members = ref.watch(propertyMembersProvider(propertyId));
    final canManage = myProperty.value?.access.canManageMembers ?? false;
    final iAmOwner = myProperty.value?.access.isOwner ?? false;
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
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: members.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final member = members[index];
              final isMe = member.userId == myUserId;
              final text = Theme.of(context).textTheme;
              return AppCard(
                padding: const EdgeInsets.all(12),
                // Only owners may touch an owner's row.
                onTap: canManage && (iAmOwner || member.role != MembershipRole.owner)
                    ? () => _showEditMemberSheet(context, ref, member, isMe: isMe, iAmOwner: iAmOwner)
                    : null,
                child: Row(
                  children: [
                    UserAvatar(name: member.displayName, size: 46),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isMe ? '${member.displayName} (you)' : member.displayName,
                            style: text.titleSmall,
                          ),
                          if (member.username != null && member.fullName != null)
                            Text('@${member.username}', style: text.bodySmall),
                          if (member.role == MembershipRole.caretaker)
                            Text(
                              member.permissions.summary,
                              style: text.bodySmall?.copyWith(
                                color: member.permissions.isFull ? AppColors.primary : null,
                                fontWeight: member.permissions.isFull ? FontWeight.w600 : null,
                              ),
                            ),
                        ],
                      ),
                    ),
                    RoleChip(role: member.role),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      floatingActionButton: canManage
          ? FloatingActionButton.extended(
              onPressed: () => _showAddMemberSheet(context, ref, iAmOwner: iAmOwner),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Add member'),
            )
          : null,
    );
  }

  Future<void> _showAddMemberSheet(BuildContext context, WidgetRef ref, {required bool iAmOwner}) async {
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true, // lets the sheet move up above the keyboard
      builder: (_) => _MemberSheet(propertyId: propertyId, iAmOwner: iAmOwner),
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
    required bool iAmOwner,
  }) async {
    final result = await showModalBottomSheet<_SheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _MemberSheet(
        propertyId: propertyId,
        existing: member,
        isMe: isMe,
        iAmOwner: iAmOwner,
      ),
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
  const _MemberSheet({
    required this.propertyId,
    required this.iAmOwner,
    this.existing,
    this.isMe = false,
  });

  final String propertyId;
  final Member? existing;
  final bool isMe;

  /// Only owners can make someone an owner.
  final bool iAmOwner;

  @override
  ConsumerState<_MemberSheet> createState() => _MemberSheetState();
}

class _MemberSheetState extends ConsumerState<_MemberSheet> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  late MembershipRole _role = widget.existing?.role ?? MembershipRole.caretaker;
  late CaretakerPermissions _permissions =
      widget.existing?.permissions ?? CaretakerPermissions.none;
  bool _busy = false;

  bool get _isAdding => widget.existing == null;

  @override
  void dispose() {
    _usernameController.dispose();
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
          username: _usernameController.text.trim(),
          role: _role,
          canRecordPayments: _permissions.recordPayments,
        ).then((membershipId) async {
          // New members start with no switches; save the chosen ones too.
          if (_role == MembershipRole.caretaker && _permissions != CaretakerPermissions.none) {
            await repository.updateMember(
              membershipId: membershipId,
              role: _role,
              permissions: _permissions,
            );
          }
        });
      }
      return repository.updateMember(
        membershipId: widget.existing!.membershipId,
        role: _role,
        permissions: _permissions,
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
                    controller: _usernameController,
                    validator: validateUsername,
                    autocorrect: false,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Their username',
                      helperText: 'They must sign up in the app first.',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                const Text('Role'),
                const SizedBox(height: 8),
                SegmentedButton<MembershipRole>(
                  segments: [
                    for (final role in MembershipRole.values)
                      if (role != MembershipRole.owner || widget.iAmOwner || _role == MembershipRole.owner)
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
                      'Handles day-to-day tasks, tickets, bills and announcements. '
                          'Choose below what else they may do.',
                  },
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                if (_role == MembershipRole.caretaker) ...[
                  const SizedBox(height: 8),
                  _PermissionSwitch(
                    title: 'Full access (same as owner)',
                    subtitle: 'Everything below. Only deleting the property and managing '
                        'owners stay with owners.',
                    value: _permissions.isFull,
                    highlight: true,
                    onChanged: (on) => setState(() =>
                        _permissions = on ? CaretakerPermissions.full : CaretakerPermissions.none),
                  ),
                  const Divider(height: 16),
                  _PermissionSwitch(
                    title: 'Record payments',
                    subtitle: 'Rent payments and marking bills paid.',
                    value: _permissions.recordPayments,
                    onChanged: (v) => setState(() => _permissions = _permissions.copyWith(recordPayments: v)),
                  ),
                  _PermissionSwitch(
                    title: 'See money',
                    subtitle: 'Rent amounts, payments, receipts, balances, ID numbers.',
                    value: _permissions.seeMoney,
                    onChanged: (v) => setState(() => _permissions = _permissions.copyWith(seeMoney: v)),
                  ),
                  _PermissionSwitch(
                    title: 'Manage apartments',
                    subtitle: 'Add/edit apartments and rents, property details, bill types.',
                    value: _permissions.manageApartments,
                    onChanged: (v) => setState(() => _permissions = _permissions.copyWith(manageApartments: v)),
                  ),
                  _PermissionSwitch(
                    title: 'Manage tenants & tenancies',
                    subtitle: 'Start, renew and end tenancies; invite codes.',
                    value: _permissions.manageTenancies,
                    onChanged: (v) => setState(() => _permissions = _permissions.copyWith(manageTenancies: v)),
                  ),
                  _PermissionSwitch(
                    title: 'Manage the team',
                    subtitle: 'Add, change and remove managers and caretakers.',
                    value: _permissions.manageTeam,
                    onChanged: (v) => setState(() => _permissions = _permissions.copyWith(manageTeam: v)),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _busy ? null : _save,
                  child: Text(_isAdding ? 'Add' : 'Save'),
                ),
                // Owners can give a MANAGER a temporary password. Caretakers'
                // passwords are reset only by the app admin (database rule).
                if (!_isAdding && widget.existing!.role == MembershipRole.caretaker && !widget.isMe) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Forgot their password? The app admin can reset a caretaker\'s password.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                if (!_isAdding && !widget.isMe && widget.iAmOwner &&
                    widget.existing!.role == MembershipRole.manager) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => resetPasswordFlow(
                              context,
                              personName: widget.existing!.displayName,
                              reset: () => ref.read(tenantAccessRepositoryProvider).resetPassword(
                                    propertyId: widget.propertyId,
                                    userId: widget.existing!.userId,
                                  ),
                            ),
                    icon: const Icon(Icons.key_rounded),
                    label: const Text('Reset password'),
                  ),
                ],
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

/// One permission switch: title, explanation, on/off.
class _PermissionSwitch extends StatelessWidget {
  const _PermissionSwitch({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.highlight = false,
  });

  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(
        title,
        style: TextStyle(
          fontWeight: highlight ? FontWeight.w700 : FontWeight.w500,
          color: highlight ? AppColors.primary : null,
        ),
      ),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      value: value,
      onChanged: onChanged,
    );
  }
}
