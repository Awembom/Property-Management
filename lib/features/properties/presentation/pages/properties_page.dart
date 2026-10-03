import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/dashboard/providers/dashboard_providers.dart';
import 'package:rental_app/features/properties/presentation/widgets/property_card.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';

/// The Properties tab: every property I'm on the team of, as cards with
/// occupancy. Landlords also get "Add property".
class PropertiesPage extends ConsumerWidget {
  const PropertiesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final properties = ref.watch(myPropertiesProvider);
    // Occupancy numbers; the cards show without them while they load.
    final dashboard = ref.watch(dashboardProvider).value;
    // Only landlord accounts add properties (the database refuses others too).
    final isLandlord =
        ref.watch(myProfileProvider).value?.accountType == AccountType.landlord;

    return Scaffold(
      appBar: AppBar(title: const Text('Properties')),
      body: properties.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(myPropertiesProvider),
        ),
        data: (properties) => RefreshIndicator(
          onRefresh: () => ref.refresh(myPropertiesProvider.future),
          child: properties.isEmpty
              ? ListView(
                  children: [
                    EmptyState(
                      icon: Icons.apartment_rounded,
                      color: AppColors.primary,
                      title: 'No properties yet',
                      message: isLandlord
                          ? 'Add your first property to manage its apartments and tenants.'
                          : 'When an owner adds you to their team, the property appears here.',
                      actionLabel: isLandlord ? 'Add property' : null,
                      onAction: isLandlord ? () => context.push(AppRoutes.newProperty) : null,
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                  itemCount: properties.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 14),
                  itemBuilder: (context, index) {
                    final my = properties[index];
                    return PropertyCard(
                      myProperty: my,
                      stats: dashboard?.statsFor(my.property.id),
                      onTap: () => context.push(AppRoutes.propertyDetail(my.property.id)),
                    );
                  },
                ),
        ),
      ),
      floatingActionButton: isLandlord && (properties.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.newProperty),
              icon: const Icon(Icons.add),
              label: const Text('Add property'),
            )
          : null,
    );
  }
}
