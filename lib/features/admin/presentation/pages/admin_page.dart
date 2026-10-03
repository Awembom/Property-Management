import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/admin/data/activity_entry.dart';
import 'package:rental_app/features/admin/data/admin_models.dart';
import 'package:rental_app/features/admin/data/admin_repository.dart';
import 'package:rental_app/features/admin/data/describe_activity.dart';
import 'package:rental_app/features/admin/providers/admin_providers.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/presentation/widgets/temporary_password_dialog.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// The super admin's screen: watch what happens across the whole app, see
/// every property and person, reset passwords and transfer ownership.
///
/// It's read-only by design: there's no button that changes rent, payments,
/// apartments or tenancies, and the database would refuse it anyway.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAppAdminProvider);

    return isAdmin.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(error: error, onRetry: () => ref.invalidate(isAppAdminProvider)),
      ),
      data: (isAdmin) => !isAdmin
          ? Scaffold(
              appBar: AppBar(title: const Text('Admin')),
              body: const Center(
                child: EmptyState(
                  icon: Icons.lock_rounded,
                  color: AppColors.ended,
                  title: 'Admins only',
                  message: 'This screen is only for the app admin.',
                ),
              ),
            )
          : const DefaultTabController(
              length: 3,
              child: Scaffold(
                appBar: _AdminAppBar(),
                body: TabBarView(
                  children: [_ActivityTab(), _PropertiesTab(), _PeopleTab()],
                ),
              ),
            ),
    );
  }
}

class _AdminAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _AdminAppBar();

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + kTextTabBarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      title: const Text('Admin'),
      bottom: const TabBar(
        tabs: [
          Tab(icon: Icon(Icons.history_rounded), text: 'Activity'),
          Tab(icon: Icon(Icons.apartment_rounded), text: 'Properties'),
          Tab(icon: Icon(Icons.people_alt_rounded), text: 'People'),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Activity

class _ActivityTab extends ConsumerWidget {
  const _ActivityTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activity = ref.watch(activityProvider);
    // Names and currencies to show next to each line.
    final properties = {
      for (final p in ref.watch(adminPropertiesProvider).value ?? const <AdminProperty>[]) p.id: p,
    };
    final people = {
      for (final p in ref.watch(adminPeopleProvider).value ?? const <AdminPerson>[]) p.id: p,
    };

    return activity.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          AsyncErrorView(error: error, onRetry: () => ref.invalidate(activityProvider)),
      data: (entries) => RefreshIndicator(
        onRefresh: () => ref.refresh(activityProvider.future),
        child: entries.isEmpty
            ? ListView(children: const [
                EmptyState(
                  icon: Icons.history_rounded,
                  color: AppColors.primary,
                  title: 'Nothing yet',
                  message: 'Changes made in the app will appear here.',
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _ActivityTile(
                    entry: entry,
                    property: properties[entry.propertyId],
                    actor: people[entry.actorId],
                    target: entry.tableName == 'auth' ? people[entry.rowId] : null,
                  );
                },
              ),
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile({required this.entry, this.property, this.actor, this.target});

  final ActivityEntry entry;
  final AdminProperty? property;
  final AdminPerson? actor;

  /// For password resets: whose password.
  final AdminPerson? target;

  String _when(DateTime time) {
    final minutes = DateTime.now().difference(time).inMinutes;
    if (minutes < 1) return 'just now';
    if (minutes < 60) return '$minutes min ago';
    if (minutes < 24 * 60) return '${minutes ~/ 60} h ago';
    return '${time.day}/${time.month}/${time.year}';
  }

  @override
  Widget build(BuildContext context) {
    final text = describeActivity(entry, currency: property?.currency);
    final changes = entry.changes;
    final who = entry.actorId == null ? 'System' : (actor?.displayName ?? 'Deleted account');
    final where = entry.propertyId == null ? null : (property?.name ?? 'Deleted property');
    final title = target == null ? text.title : '${text.title}: ${target!.displayName}';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        shape: const Border(),
        leading: IconBubble(icon: text.icon, color: text.color, size: 40),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([who, ?where, _when(entry.happenedAt)].join(' · ')),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (changes.isEmpty)
            Text(
              entry.action == 'UPDATE' ? 'No visible changes.' : 'Details: ${entry.row}',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final (field, before, after) in changes)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text.rich(TextSpan(children: [
                  TextSpan(
                    text: '$field: ',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '${before ?? '-'}',
                    style: const TextStyle(
                      color: AppColors.overdue,
                      decoration: TextDecoration.lineThrough,
                    ),
                  ),
                  const TextSpan(text: '  ›  '),
                  TextSpan(
                    text: '${after ?? '-'}',
                    style: const TextStyle(color: AppColors.paid, fontWeight: FontWeight.w700),
                  ),
                ])),
              ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- Properties

class _PropertiesTab extends ConsumerWidget {
  const _PropertiesTab();

  Future<void> _transfer(BuildContext context, WidgetRef ref, AdminProperty property) async {
    final username = await showDialog<String>(
      context: context,
      builder: (_) => _UsernameDialog(propertyName: property.name),
    );
    if (username == null || !context.mounted) return;
    try {
      await ref.read(adminRepositoryProvider).transferOwnership(
            propertyId: property.id,
            username: username,
          );
      ref.invalidate(adminPropertiesProvider);
      ref.invalidate(activityProvider);
      if (context.mounted) showMessage(context, '@$username is now an owner of ${property.name}');
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(adminPropertiesProvider);
    return properties.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          AsyncErrorView(error: error, onRetry: () => ref.invalidate(adminPropertiesProvider)),
      data: (properties) => RefreshIndicator(
        onRefresh: () => ref.refresh(adminPropertiesProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            for (final property in properties)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: IconBubble(
                    icon: Icons.apartment_rounded,
                    color: AppColors.forId(property.id),
                    size: 44,
                  ),
                  title: Text(property.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    property.owners.isEmpty ? 'No owner!' : 'Owner: ${property.owners.join(', ')}',
                    '${property.apartmentCount} apartments · ${property.currency}',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (_) => _transfer(context, ref, property),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'transfer', child: Text('Transfer ownership')),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for the username of the new owner.
class _UsernameDialog extends StatefulWidget {
  const _UsernameDialog({required this.propertyName});

  final String propertyName;

  @override
  State<_UsernameDialog> createState() => _UsernameDialogState();
}

class _UsernameDialogState extends State<_UsernameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = _controller.text.trim().replaceFirst('@', '');
    return AlertDialog(
      title: Text('New owner of ${widget.propertyName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('They become an owner. The current owners stay; '
              'the new owner can remove them in Team.'),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            autocorrect: false,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: 'Their username',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: username.isEmpty ? null : () => Navigator.of(context).pop(username),
          child: const Text('Make owner'),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- People

class _PeopleTab extends ConsumerWidget {
  const _PeopleTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(adminPeopleProvider);
    return people.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          AsyncErrorView(error: error, onRetry: () => ref.invalidate(adminPeopleProvider)),
      data: (people) => RefreshIndicator(
        onRefresh: () => ref.refresh(adminPeopleProvider.future),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 32),
          children: [
            for (final person in people)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: IconBubble(
                    icon: person.accountType?.icon ?? Icons.person_rounded,
                    color: person.accountType?.color ?? AppColors.ended,
                    size: 44,
                  ),
                  title: Text(person.displayName, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text([
                    if (person.username != null) '@${person.username}',
                    '${person.propertyCount} properties · ${person.rentalCount} rentals',
                  ].join('\n')),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (person.accountType != null)
                        StatusPill(label: person.accountType!.label, color: person.accountType!.color),
                    ],
                  ),
                  onTap: () => resetPasswordFlow(
                    context,
                    personName: person.displayName,
                    reset: () => ref.read(tenantAccessRepositoryProvider).resetPassword(
                          propertyId: null, // the admin needs no property
                          userId: person.id,
                        ),
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'Tap a person to give them a temporary password.',
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
