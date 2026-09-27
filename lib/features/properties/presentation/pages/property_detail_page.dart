import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/constants/currencies.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/presentation/widgets/role_chip.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';

/// One property: its details, and links to apartments and members.
/// Buttons appear only if my role allows them (the database checks too).
class PropertyDetailPage extends ConsumerWidget {
  const PropertyDetailPage({super.key, required this.propertyId});

  final String propertyId;

  Future<void> _delete(BuildContext context, WidgetRef ref, Property property) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete property?',
      message: 'This permanently deletes "${property.name}" and everything in it: '
          'apartments, tenants, payments and receipts. This cannot be undone.',
      confirmLabel: 'Delete forever',
      destructive: true,
      typeToConfirm: property.name,
    );
    if (!confirmed || !context.mounted) return;

    try {
      await ref.read(propertiesRepositoryProvider).deleteProperty(property.id);
      ref.invalidate(myPropertiesProvider);
      if (context.mounted) {
        showMessage(context, '"${property.name}" deleted');
        context.go(AppRoutes.properties);
      }
    } catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId));

    return myProperty.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myPropertyProvider(propertyId)),
        ),
      ),
      data: (myProperty) {
        final property = myProperty.property;
        final access = myProperty.access;

        return Scaffold(
          appBar: AppBar(
            title: Text(property.name),
            actions: [
              if (access.canEditProperty)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => context.push(AppRoutes.editProperty(property.id)),
                ),
              if (access.canDeleteProperty)
                PopupMenuButton<String>(
                  onSelected: (_) => _delete(context, ref, property),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: 'delete', child: Text('Delete property')),
                  ],
                ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () => ref.refresh(myPropertyProvider(propertyId).future),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text('Your role: '),
                            RoleChip(role: access.role),
                          ],
                        ),
                        const Divider(height: 24),
                        _InfoRow(
                          icon: Icons.place_outlined,
                          text: property.address ?? 'No address',
                        ),
                        _InfoRow(
                          icon: Icons.payments_outlined,
                          text: '${property.currency}: '
                              '${kCurrencies[property.currency] ?? property.currency}',
                        ),
                        _InfoRow(
                          icon: Icons.schedule_outlined,
                          text: 'Rent shows "Due soon" ${property.gracePeriodDays} '
                              'day${property.gracePeriodDays == 1 ? '' : 's'} before it\'s due',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      const ListTile(
                        leading: Icon(Icons.door_front_door_outlined),
                        title: Text('Apartments'),
                        subtitle: Text('Coming next (Phase 4)'),
                        enabled: false,
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.group_outlined),
                        title: const Text('Team'),
                        subtitle: Text(access.canManageMembers
                            ? 'Add and manage owners, managers and caretakers'
                            : 'See who manages this property'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => context.push(AppRoutes.propertyMembers(property.id)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
