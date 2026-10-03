import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/presentation/widgets/apartment_look.dart';
import 'package:rental_app/features/apartments/presentation/widgets/apartment_sheet.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/dashboard/providers/dashboard_providers.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/presentation/widgets/role_chip.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/utils/phone.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/confirm_dialog.dart';
import 'package:rental_app/shared/widgets/property_photo.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/collected_card.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';

/// One property: a short header, three numbers, quick actions (bills,
/// issues, message tenants, team) and its units.
/// Buttons appear only if my role allows them (the database checks too).
class PropertyDetailPage extends ConsumerWidget {
  const PropertyDetailPage({super.key, required this.propertyId});

  final String propertyId;

  Future<void> _delete(
    BuildContext context,
    WidgetRef ref,
    Property property,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: 'Delete property?',
      message:
          'This permanently deletes "${property.name}" and everything in it: '
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

  Future<void> _addApartment(
    BuildContext context,
    WidgetRef ref,
    Property property,
  ) async {
    final result = await showApartmentSheet(
      context,
      propertyId: property.id,
      currency: property.currency,
    );
    if (result == ApartmentSheetResult.saved && context.mounted) {
      ref.invalidate(apartmentsProvider(property.id));
      ref.invalidate(dashboardProvider);
      showMessage(context, 'Apartment added');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myProperty = ref.watch(myPropertyProvider(propertyId));

    return myProperty.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
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
        final apartmentsValue = ref.watch(apartmentsProvider(propertyId));
        final apartments = apartmentsValue.value;
        final collected = ref
            .watch(dashboardProvider)
            .value
            ?.statsFor(propertyId)
            .collectedThisMonth;
        final text = Theme.of(context).textTheme;
        final openTickets = ref
            .watch(propertyTicketsProvider(propertyId))
            .value
            ?.where((t) => t.status != TicketStatus.resolved)
            .length;

        final total = apartments?.length ?? 0;
        final occupied = apartments?.where((a) => !a.isVacant).length ?? 0;
        final overdue =
            apartments
                ?.where(
                  (a) => a.activeTenancy?.rentStatus == RentStatus.overdue,
                )
                .length ??
            0;

        // Everything owners need daily is on this one page: a short header,
        // four quick actions and the units. Less frequent things (agreement,
        // bill types, deleting) are in the ⋮ menu.
        return Scaffold(
          appBar: AppBar(
            title: Text(property.name),
            actions: [
              if (access.canEditProperty)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () =>
                      context.push(AppRoutes.editProperty(property.id)),
                ),
              PopupMenuButton<String>(
                onSelected: (value) => switch (value) {
                  'agreement' => context.push(AppRoutes.agreement(property.id)),
                  'types' => context.push(AppRoutes.billTypes(property.id)),
                  'announcements' => context.push(
                    AppRoutes.announcements(property.id),
                  ),
                  _ => _delete(context, ref, property),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'agreement',
                    child: Text('Tenancy agreement'),
                  ),
                  const PopupMenuItem(
                    value: 'announcements',
                    child: Text('Sent messages'),
                  ),
                  if (access.canManageBillTypes)
                    const PopupMenuItem(
                      value: 'types',
                      child: Text('Bill types'),
                    ),
                  if (access.canDeleteProperty)
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete property'),
                    ),
                ],
              ),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () {
              ref.invalidate(apartmentsProvider(propertyId));
              ref.invalidate(dashboardProvider);
              ref.invalidate(propertyTicketsProvider(propertyId));
              return ref.refresh(myPropertyProvider(propertyId).future);
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
              children: [
                // Short header: picture, address, contact number, my role.
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 84,
                        child: PropertyPhoto(
                          seed: property.id,
                          height: 72,
                          borderRadius: 14,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              property.address ?? 'No address',
                              style: text.bodyMedium,
                              maxLines: 2,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              property.contactPhone == null
                                  ? 'No contact phone for tenants'
                                  : 'Tenants call ${formatPhone(property.contactPhone!)}',
                              style: text.bodySmall,
                            ),
                            const SizedBox(height: 6),
                            RoleChip(role: access.role),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Big, at-a-glance cards: occupancy, then overdue and open
                // issues side by side, then the month's money (hidden at first).
                _OccupancyCard(
                  occupied: occupied,
                  total: total,
                  loading: apartments == null,
                ),
                const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _BigNumber(
                          icon: Icons.error_rounded,
                          color: overdue > 0
                              ? AppColors.overdue
                              : AppColors.paid,
                          value: apartments == null ? '-' : '$overdue',
                          label: overdue == 1
                              ? 'tenant overdue'
                              : 'tenants overdue',
                          onTap: () => context.go(AppRoutes.tenants),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _BigNumber(
                          icon: Icons.build_circle_rounded,
                          color: (openTickets ?? 0) > 0
                              ? AppColors.dueSoon
                              : AppColors.paid,
                          value: openTickets == null ? '-' : '$openTickets',
                          label: openTickets == 1
                              ? 'open issue'
                              : 'open issues',
                          onTap: () => context.push(
                            AppRoutes.propertyTickets(property.id),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (access.canSeeMoney && collected != null) ...[
                  const SizedBox(height: 12),
                  CollectedCard(
                    amountText: formatMoney(collected, property.currency),
                  ),
                ],
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ActionButton(
                      icon: Icons.receipt_long_rounded,
                      label: 'Bills',
                      color: AppColors.primary,
                      onTap: () => context.push(AppRoutes.bills(property.id)),
                    ),
                    _ActionButton(
                      icon: Icons.build_circle_rounded,
                      label: 'Issues',
                      color: AppColors.overdue,
                      badge: openTickets ?? 0,
                      onTap: () =>
                          context.push(AppRoutes.propertyTickets(property.id)),
                    ),
                    _ActionButton(
                      icon: Icons.campaign_rounded,
                      label: 'Message',
                      color: AppColors.accent,
                      onTap: () =>
                          context.push(AppRoutes.newAnnouncement(property.id)),
                    ),
                    _ActionButton(
                      icon: Icons.groups_rounded,
                      label: 'Team',
                      color: AppColors.paid,
                      onTap: () =>
                          context.push(AppRoutes.propertyMembers(property.id)),
                    ),
                  ],
                ),

                SectionTitle(
                  apartments == null ? 'Units' : 'Units ($total)',
                  trailing: TextButton(
                    onPressed: () =>
                        context.push(AppRoutes.apartments(property.id)),
                    child: const Text('List view'),
                  ),
                ),
                if (apartments == null && apartmentsValue.hasError)
                  AsyncErrorView(
                    error: apartmentsValue.error!,
                    onRetry: () =>
                        ref.invalidate(apartmentsProvider(propertyId)),
                  )
                else if (apartments == null)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else
                  _UnitGrid(
                    apartments: apartments,
                    onOpen: (a) => context.push(
                      AppRoutes.apartmentDetail(property.id, a.apartment.id),
                    ),
                    onAdd: access.canManageApartments
                        ? () => _addApartment(context, ref, property)
                        : null,
                    // "Record rent" right on late units, for those who may record payments.
                    onRecordRent: access.canRecordPayments
                        ? (t) => context.push(
                            AppRoutes.recordPayment(property.id, t.id),
                          )
                        : null,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// The occupancy card: how many units are let, with a bar.
class _OccupancyCard extends StatelessWidget {
  const _OccupancyCard({
    required this.occupied,
    required this.total,
    required this.loading,
  });

  final int occupied;
  final int total;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final share = total == 0 ? 0.0 : occupied / total;
    const white = Colors.white;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.gradientFor(AppColors.accent),
        borderRadius: BorderRadius.circular(22),
        boxShadow: AppColors.cardShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.door_front_door_rounded, color: white, size: 22),
              const SizedBox(width: 8),
              Text('Occupancy', style: text.titleSmall?.copyWith(color: white)),
              const Spacer(),
              Text(
                loading ? '' : '${(share * 100).round()}%',
                style: text.titleMedium?.copyWith(
                  color: white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            loading ? '-' : '$occupied of $total units let',
            style: text.headlineSmall?.copyWith(
              color: white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: loading ? null : share,
              minHeight: 10,
              color: white,
              backgroundColor: white.withValues(alpha: 0.25),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            loading
                ? ''
                : (total - occupied == 0
                      ? 'No vacant units'
                      : '${total - occupied} vacant'),
            style: text.bodySmall?.copyWith(
              color: white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }
}

/// A big number card, e.g. "2 tenants overdue".
class _BigNumber extends StatelessWidget {
  const _BigNumber({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconBubble(icon: icon, color: color, size: 42),
          const SizedBox(height: 12),
          Text(
            value,
            style: text.headlineMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(label, style: text.bodyMedium?.copyWith(color: AppColors.muted)),
        ],
      ),
    );
  }
}

/// A round coloured button with a word under it (and a count, if any).
class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
    this.badge = 0,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Column(
          children: [
            Badge.count(
              count: badge,
              isLabelVisible: badge > 0,
              child: IconBubble(icon: icon, color: color, size: 52),
            ),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

/// Units as big tiles, two per row: name, who lives there and the rent
/// status in colour; late units get a "Record rent" button.
class _UnitGrid extends StatelessWidget {
  const _UnitGrid({
    required this.apartments,
    required this.onOpen,
    this.onAdd,
    this.onRecordRent,
  });

  final List<ApartmentWithTenancy> apartments;
  final ValueChanged<ApartmentWithTenancy> onOpen;
  final VoidCallback? onAdd;
  final ValueChanged<TenancyOverview>? onRecordRent;

  /// Inside the padding; fits icon, name, tenant and the button.
  static const tileHeight = 142.0;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final tiles = <Widget>[
      for (final item in apartments)
        _UnitTile(item: item, onOpen: onOpen, onRecordRent: onRecordRent),
      if (onAdd != null)
        AppCard(
          onTap: onAdd,
          color: AppColors.soft(AppColors.primary),
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            height: tileHeight,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const IconBubble(
                  icon: Icons.add_rounded,
                  color: AppColors.primary,
                  size: 48,
                ),
                const SizedBox(height: 8),
                Text(
                  'Add unit',
                  style: text.titleSmall?.copyWith(color: AppColors.primary),
                ),
              ],
            ),
          ),
        ),
    ];
    if (tiles.isEmpty) {
      return Text(
        'No units yet.',
        style: text.bodyMedium?.copyWith(color: AppColors.muted),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = 12.0;
        final width = (constraints.maxWidth - gap) / 2;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: width, child: tile),
          ],
        );
      },
    );
  }
}

class _UnitTile extends StatelessWidget {
  const _UnitTile({
    required this.item,
    required this.onOpen,
    this.onRecordRent,
  });

  final ApartmentWithTenancy item;
  final ValueChanged<ApartmentWithTenancy> onOpen;
  final ValueChanged<TenancyOverview>? onRecordRent;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final look = apartmentLook(item);
    final tenancy = item.activeTenancy;
    final late =
        tenancy != null &&
        (tenancy.rentStatus == RentStatus.overdue ||
            tenancy.rentStatus == RentStatus.dueSoon);
    return AppCard(
      onTap: () => onOpen(item),
      padding: const EdgeInsets.all(14),
      // Same height for every tile, so the grid lines up.
      child: SizedBox(
        height: _UnitGrid.tileHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconBubble(
                  icon: Icons.door_front_door_rounded,
                  color: look.color,
                  size: 40,
                ),
                const Spacer(),
                StatusPill(label: look.label, color: look.color),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.apartment.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleLarge,
            ),
            Text(
              tenancy?.tenantName ?? 'No tenant',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.bodySmall,
            ),
            const Spacer(),
            if (late && onRecordRent != null)
              SizedBox(
                width: double.infinity,
                height: 36,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                  ),
                  onPressed: () => onRecordRent!(tenancy),
                  icon: const Icon(Icons.payments_rounded, size: 18),
                  label: const FittedBox(child: Text('Record rent')),
                ),
              )
            else if (tenancy != null)
              Text(
                'Paid until ${formatDate(tenancy.paidUntil)}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.bodySmall?.copyWith(
                  color: look.color,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
