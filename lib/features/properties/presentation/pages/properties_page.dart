import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/presentation/widgets/role_chip.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';

/// Home screen for staff: every property I'm a member of.
class PropertiesPage extends ConsumerWidget {
  const PropertiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(myPropertiesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('My properties'),
        actions: [
          IconButton(
            tooltip: 'My profile',
            icon: const Icon(Icons.account_circle_outlined),
            onPressed: () => context.push(AppRoutes.profile),
          ),
        ],
      ),
      body: properties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myPropertiesProvider),
        ),
        data: (properties) => properties.isEmpty
            ? const _EmptyState()
            // Pull down to reload.
            : RefreshIndicator(
                onRefresh: () => ref.refresh(myPropertiesProvider.future),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  itemCount: properties.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, index) =>
                      _PropertyCard(myProperty: properties[index]),
                ),
              ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.newProperty),
        icon: const Icon(Icons.add),
        label: const Text('Add property'),
      ),
    );
  }
}

class _PropertyCard extends StatelessWidget {
  const _PropertyCard({required this.myProperty});

  final MyProperty myProperty;

  @override
  Widget build(BuildContext context) {
    final property = myProperty.property;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: const CircleAvatar(child: Icon(Icons.apartment_rounded)),
        title: Text(property.name),
        subtitle: Text(property.address ?? 'No address'),
        trailing: RoleChip(role: myProperty.access.role),
        onTap: () => context.push(AppRoutes.propertyDetail(property.id)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_work_outlined, size: 64),
            const SizedBox(height: 16),
            Text('No properties yet', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
              'Add your first property to start managing apartments and tenants. '
              'If someone added you to their property, it will show up here.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
