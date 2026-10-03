import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/presentation/widgets/apartment_look.dart';
import 'package:rental_app/features/apartments/presentation/widgets/apartment_sheet.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/empty_state.dart';
import 'package:rental_app/shared/widgets/gradient_header.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// Which apartments the list shows.
enum _Filter {
  all('All'),
  occupied('Occupied'),
  vacant('Vacant'),
  attention('Needs attention'); // rent overdue or due soon

  const _Filter(this.label);
  final String label;

  bool matches(ApartmentWithTenancy item) => switch (this) {
    _Filter.all => true,
    _Filter.occupied => !item.isVacant,
    _Filter.vacant => item.isVacant,
    _Filter.attention =>
      item.activeTenancy?.rentStatus == RentStatus.overdue ||
          item.activeTenancy?.rentStatus == RentStatus.dueSoon,
  };
}

/// All apartments of a property, each marked Vacant or with its rent status.
/// Everyone on the team can see this; only owners and managers get the
/// "Add apartment" button (the database enforces the same rule).
class ApartmentsPage extends ConsumerStatefulWidget {
  const ApartmentsPage({super.key, required this.propertyId});

  final String propertyId;

  @override
  ConsumerState<ApartmentsPage> createState() => _ApartmentsPageState();
}

class _ApartmentsPageState extends ConsumerState<ApartmentsPage> {
  // The selected filter is purely local UI state, so setState is fine here.
  _Filter _filter = _Filter.all;

  Future<void> _addApartment() async {
    final currency = ref
        .read(myPropertyProvider(widget.propertyId))
        .value
        ?.property
        .currency;
    if (currency == null) return; // property still loading
    final result = await showApartmentSheet(
      context,
      propertyId: widget.propertyId,
      currency: currency,
    );
    if (result == ApartmentSheetResult.saved && mounted) {
      ref.invalidate(apartmentsProvider(widget.propertyId));
      showMessage(context, 'Apartment added');
    }
  }

  @override
  Widget build(BuildContext context) {
    final myProperty = ref.watch(myPropertyProvider(widget.propertyId)).value;
    final apartments = ref.watch(apartmentsProvider(widget.propertyId));
    final canManage = myProperty?.access.canManageApartments ?? false;
    final color = AppColors.forId(widget.propertyId);

    return Scaffold(
      appBar: AppBar(title: const Text('Apartments')),
      body: apartments.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => AsyncErrorView(
          error: error,
          onRetry: () => ref.invalidate(apartmentsProvider(widget.propertyId)),
        ),
        data: (items) {
          if (items.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                child: EmptyState(
                  icon: Icons.door_front_door_rounded,
                  color: color,
                  title: 'No apartments yet',
                  message: canManage
                      ? 'Add the apartments in this property, then you can give each one a tenant.'
                      : 'An owner or manager hasn\'t added any apartments yet.',
                  actionLabel: canManage ? 'Add apartment' : null,
                  onAction: canManage ? _addApartment : null,
                ),
              ),
            );
          }

          final occupied = items.where((item) => !item.isVacant).length;
          final overdue = items
              .where(
                (item) => item.activeTenancy?.rentStatus == RentStatus.overdue,
              )
              .length;
          final shown = items.where(_filter.matches).toList();

          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(apartmentsProvider(widget.propertyId).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                GradientHeader(
                  color: color,
                  icon: Icons.apartment_rounded,
                  title: myProperty?.property.name ?? 'Apartments',
                  subtitle: 'Tap an apartment to see its tenant',
                  stats: [
                    HeaderStat(value: '${items.length}', label: 'Total'),
                    HeaderStat(value: '$occupied', label: 'Occupied'),
                    HeaderStat(
                      value: '${items.length - occupied}',
                      label: 'Vacant',
                    ),
                    HeaderStat(value: '$overdue', label: 'Overdue'),
                  ],
                ),
                const SizedBox(height: 16),
                // Filter chips; scroll sideways on narrow phones.
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final filter in _Filter.values)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(filter.label),
                            selected: _filter == filter,
                            onSelected: (_) => setState(() => _filter = filter),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (shown.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                      'No apartments match "${_filter.label}".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final item in shown)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: ApartmentCard(
                      item: item,
                      currency: myProperty?.property.currency,
                      canSeeMoney: myProperty?.access.canSeeMoney ?? false,
                      onTap: () => context.push(
                        AppRoutes.apartmentDetail(
                          widget.propertyId,
                          item.apartment.id,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: canManage && (apartments.value?.isNotEmpty ?? false)
          ? FloatingActionButton.extended(
              onPressed: _addApartment,
              icon: const Icon(Icons.add),
              label: const Text('Add apartment'),
            )
          : null,
    );
  }
}

/// One apartment in the list: coloured icon, name, tenant and status.
class ApartmentCard extends StatelessWidget {
  const ApartmentCard({
    super.key,
    required this.item,
    required this.onTap,
    this.currency,
    this.canSeeMoney = false,
  });

  final ApartmentWithTenancy item;
  final VoidCallback onTap;

  /// Needed to show the monthly rent (owners and managers only).
  final String? currency;
  final bool canSeeMoney;

  /// Second line of the card: the tenant, or for a vacant apartment its rent.
  String _subtitle() {
    final tenancy = item.activeTenancy;
    if (tenancy != null) return tenancy.tenantName;
    final rent = item.apartment.monthlyRent;
    if (!canSeeMoney || currency == null) return 'Ready for a new tenant';
    if (rent == null) return 'Ready · monthly rent not set';
    return 'Ready · ${formatMoney(rent, currency!)} / month';
  }

  @override
  Widget build(BuildContext context) {
    final look = apartmentLook(item);
    final text = Theme.of(context).textTheme;

    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              IconBubble(
                icon: Icons.door_front_door_rounded,
                color: look.color,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.apartment.name,
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(),
                      style: text.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              StatusPill(label: look.label, color: look.color, icon: look.icon),
            ],
          ),
        ),
      ),
    );
  }
}
