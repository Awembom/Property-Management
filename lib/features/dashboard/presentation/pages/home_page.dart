import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/admin/providers/admin_providers.dart';
import 'package:rental_app/features/announcements/presentation/pages/announcements_page.dart';
import 'package:rental_app/features/announcements/providers/announcements_providers.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/dashboard/data/dashboard.dart';
import 'package:rental_app/features/dashboard/providers/dashboard_providers.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';
import 'package:rental_app/features/properties/presentation/widgets/property_card.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/receipts/providers/receipts_providers.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/rent_status_pill.dart';
import 'package:rental_app/features/tenancies/presentation/widgets/tenancy_row.dart';
import 'package:rental_app/features/tenant_access/data/my_rental.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/async_error_view.dart';
import 'package:rental_app/shared/widgets/collected_card.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';
import 'package:rental_app/shared/widgets/property_photo.dart';
import 'package:rental_app/shared/widgets/section_title.dart';
import 'package:rental_app/shared/widgets/stat_card.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';
import 'package:rental_app/shared/widgets/user_avatar.dart';

/// The Home tab. Tenants see their home; landlords and team members see an
/// overview of the properties they manage.
class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileValue = ref.watch(myProfileProvider);
    // Who am I? Until that's known, a short wait (not the wrong Home page).
    if (profileValue.isLoading && !profileValue.hasValue) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final profile = profileValue.value;
    final managesSomething = (ref.watch(myPropertiesProvider).value ?? const []).isNotEmpty;
    final isTenant = profile?.accountType == AccountType.tenant && !managesSomething;

    return Scaffold(
      body: SafeArea(
        child: isTenant ? _TenantHome(profile: profile) : _StaffHome(profile: profile),
      ),
    );
  }
}

// ---------------------------------------------------------------- greeting

/// "Welcome back, Tina" with an avatar, plus round action buttons.
class _Greeting extends StatelessWidget {
  const _Greeting({required this.profile, this.actions = const []});

  final Profile? profile;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = profile?.fullName ?? profile?.username ?? '';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
      child: Row(
        children: [
          UserAvatar(name: name.isEmpty ? '?' : name, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Welcome back,', style: text.bodySmall),
                Text(
                  name.isEmpty ? 'Hello!' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(fontSize: 18),
                ),
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A round white button with an icon (used next to the greeting).
class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: Colors.black26,
        child: IconButton(tooltip: tooltip, icon: Icon(icon), onPressed: onPressed),
      ),
    );
  }
}

/// The bell, with how many notifications I haven't read.
class _BellButton extends ConsumerWidget {
  const _BellButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(unreadNotificationsProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Material(
        color: Theme.of(context).colorScheme.surface,
        shape: const CircleBorder(),
        elevation: 1,
        shadowColor: Colors.black26,
        child: IconButton(
          tooltip: 'Notifications',
          onPressed: () => context.push(AppRoutes.notifications),
          icon: Badge.count(
            count: unread,
            isLabelVisible: unread > 0,
            child: Icon(unread > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- staff

class _StaffHome extends ConsumerWidget {
  const _StaffHome({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);
    final isAdmin = ref.watch(isAppAdminProvider).value ?? false;
    final isLandlord = profile?.accountType == AccountType.landlord;

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(myProfileProvider);
        ref.invalidate(myPropertiesProvider);
        ref.invalidate(attentionItemsProvider);
        ref.invalidate(myNotificationsProvider);
        return ref.refresh(dashboardProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _Greeting(profile: profile, actions: [
            const _BellButton(),
            if (isAdmin)
              _RoundButton(
                icon: Icons.admin_panel_settings_outlined,
                tooltip: 'Admin',
                onPressed: () => context.push(AppRoutes.admin),
              ),
            _RoundButton(
              icon: Icons.qr_code_scanner_rounded,
              tooltip: 'Check a receipt',
              onPressed: () => context.push(AppRoutes.checkReceipt),
            ),
            if (isLandlord)
              _RoundButton(
                icon: Icons.add_rounded,
                tooltip: 'Add property',
                onPressed: () => context.push(AppRoutes.newProperty),
              ),
          ]),
          ...dashboard.when(
            loading: () => [
              const Padding(
                padding: EdgeInsets.all(48),
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, _) => [
              AsyncErrorView(error: error, onRetry: () => ref.invalidate(dashboardProvider)),
            ],
            data: (d) => d.properties.isEmpty
                ? [_NoPropertiesYet(isLandlord: isLandlord, username: profile?.username)]
                : _overview(context, ref, d),
          ),
        ],
      ),
    );
  }

  List<Widget> _overview(BuildContext context, WidgetRef ref, Dashboard d) {
    final collected = d.collectedByCurrency;
    final attention = d.needsAttention;
    final others = ref.watch(attentionItemsProvider).value ?? const <AttentionItem>[];
    return [
      const SectionTitle('Overview'),
      StatGrid(children: [
        StatCard(
          icon: Icons.apartment_rounded,
          label: 'Properties',
          value: '${d.properties.length}',
          highlight: true,
          onTap: () => context.go(AppRoutes.properties),
        ),
        StatCard(
          icon: Icons.door_front_door_rounded,
          label: 'Occupied units',
          value: '${d.occupied}/${d.apartments}',
          color: AppColors.accent,
        ),
        StatCard(
          icon: Icons.error_outline_rounded,
          label: 'Overdue',
          value: '${d.overdue}',
          color: AppColors.overdue,
          onTap: () => context.go(AppRoutes.tenants),
        ),
        StatCard(
          icon: Icons.schedule_rounded,
          label: 'Due soon',
          value: '${d.dueSoon}',
          color: AppColors.dueSoon,
        ),
      ]),
      // Money only for those who may see it; hidden until the eye is tapped.
      if (collected.isNotEmpty) ...[
        const SizedBox(height: 12),
        CollectedCard(amountText: collected.entries.map((e) => formatMoney(e.value, e.key)).join(' + ')),
      ],
      if (attention.isNotEmpty || others.isNotEmpty) ...[
        SectionTitle(
          'Needs attention',
          trailing: TextButton(
            onPressed: () => context.go(AppRoutes.tenants),
            child: const Text('See all'),
          ),
        ),
        // Late rent first, then receipt disputes, open issues, overdue bills.
        for (final tenancy in attention.take(4))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TenancyRow(tenancy: tenancy, propertyName: d.propertyName(tenancy.propertyId)),
          ),
        for (final item in others.take(6))
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: AppCard(
              padding: const EdgeInsets.all(12),
              onTap: () => context.push(item.route),
              child: Row(
                children: [
                  IconBubble(icon: item.icon, color: item.color, size: 44),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall),
                        Text(item.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
                ],
              ),
            ),
          ),
      ],
      SectionTitle(
        'My properties',
        trailing: TextButton(
          onPressed: () => context.go(AppRoutes.properties),
          child: const Text('See all'),
        ),
      ),
      SizedBox(
        height: 196,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: d.properties.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (context, index) {
            final my = d.properties[index];
            return SizedBox(
              width: 170,
              child: PropertyCard(
                myProperty: my,
                stats: d.statsFor(my.property.id),
                compact: true,
                onTap: () => context.push(AppRoutes.propertyDetail(my.property.id)),
              ),
            );
          },
        ),
      ),
    ];
  }
}

class _NoPropertiesYet extends StatelessWidget {
  const _NoPropertiesYet({required this.isLandlord, this.username});

  final bool isLandlord;
  final String? username;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: AppCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PropertyPhoto(seed: 'empty-home', color: AppColors.primary, height: 150),
            const SizedBox(height: 18),
            Text(
              isLandlord ? 'Add your first property' : 'Waiting to be added',
              textAlign: TextAlign.center,
              style: text.titleLarge,
            ),
            const SizedBox(height: 6),
            Text(
              isLandlord
                  ? 'Add a property, then its apartments and tenants. You\'ll see '
                      'rent, occupancy and who needs attention right here.'
                  : 'Give your username ${username == null ? '' : '@$username '}to the '
                      'property owner. Once they add you to their team, the property '
                      'appears here. Pull down to refresh.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            if (isLandlord) ...[
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.newProperty),
                icon: const Icon(Icons.add_rounded),
                label: const Text('Add property'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- tenant

class _TenantHome extends ConsumerWidget {
  const _TenantHome({required this.profile});

  final Profile? profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rentals = ref.watch(myRentalsProvider);
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () {
        ref.invalidate(myHomeBillsProvider);
        ref.invalidate(myAnnouncementsProvider);
        ref.invalidate(receiptsToCheckProvider);
        ref.invalidate(myNotificationsProvider);
        return ref.refresh(myRentalsProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          _Greeting(profile: profile, actions: const [_BellButton()]),
          ...rentals.when(
            loading: () => [
              const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator())),
            ],
            error: (error, _) => [
              AsyncErrorView(error: error, onRetry: () => ref.invalidate(myRentalsProvider)),
            ],
            data: (rentals) => rentals.isEmpty
                ? [
                    const SizedBox(height: 16),
                    AppCard(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const PropertyPhoto(seed: 'tenant-welcome', color: AppColors.accent, height: 150),
                          const SizedBox(height: 18),
                          Text('Connect to your home',
                              textAlign: TextAlign.center, style: text.titleLarge),
                          const SizedBox(height: 6),
                          Text(
                            'Enter the invite code your landlord gave you to see your '
                            'rent, due dates and receipts.',
                            textAlign: TextAlign.center,
                            style: text.bodyMedium?.copyWith(color: AppColors.muted),
                          ),
                          const SizedBox(height: 18),
                          FilledButton.icon(
                            onPressed: () => context.push(AppRoutes.joinWithCode),
                            icon: const Icon(Icons.vpn_key_rounded),
                            label: const Text('Enter invite code'),
                          ),
                        ],
                      ),
                    ),
                  ]
                : [
                    // New receipts to check (only 24 hours to answer), then
                    // bills, so new ones are the first thing tenants see.
                    ..._receiptsToCheck(context, ref),
                    ..._myBills(context, ref),
                    const SectionTitle('My home'),
                    for (final rental in rentals)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: _RentalCard(rental: rental),
                      ),
                    ..._latestAnnouncements(context, ref),
                    TextButton.icon(
                      onPressed: () => context.push(AppRoutes.joinWithCode),
                      icon: const Icon(Icons.vpn_key_rounded),
                      label: const Text('Have another invite code?'),
                    ),
                  ],
          ),
        ],
      ),
    );
  }
}

/// New receipts the tenant should confirm or question, with the time left.
/// Nothing at all if there are none.
List<Widget> _receiptsToCheck(BuildContext context, WidgetRef ref) {
  final receipts = ref.watch(receiptsToCheckProvider).value ?? const <ReceiptToCheck>[];
  if (receipts.isEmpty) return const [];
  final text = Theme.of(context).textTheme;
  return [
    const SectionTitle('Receipts to check'),
    for (final r in receipts)
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          color: AppColors.solidSoft(context, AppColors.dueSoon),
          padding: const EdgeInsets.all(14),
          onTap: () => context.push(AppRoutes.myReceipt(r.tenancyId, r.payment.id)),
          child: Row(
            children: [
              const Icon(Icons.receipt_long_rounded, color: AppColors.dueSoon, size: 30),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${r.payment.receiptNumber} · ${formatMoney(r.payment.amount, r.currency)}',
                      style: text.titleSmall,
                    ),
                    Text(
                      'Is it correct? Confirm or report a problem '
                      'by ${DateFormat('d MMM, HH:mm').format(r.deadline)}.',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
  ];
}

/// "My bills" for the tenant's Home: what's left to pay (in red if
/// overdue), then the bills, unpaid first. Nothing at all if there are none.
List<Widget> _myBills(BuildContext context, WidgetRef ref) {
  final bills = ref.watch(myHomeBillsProvider).value ?? const <HomeBill>[];
  if (bills.isEmpty) return const [];
  final text = Theme.of(context).textTheme;

  final unpaid = bills.where((b) => b.bill.isOpen).toList();
  final overdue = unpaid.where((b) => b.bill.status == BillStatus.overdue).length;
  // Totals per currency (usually just one).
  final toPay = <String, int>{};
  for (final b in unpaid) {
    toPay[b.currency] = (toPay[b.currency] ?? 0) + b.bill.amount;
  }
  final color = overdue > 0 ? AppColors.overdue : (unpaid.isEmpty ? AppColors.paid : AppColors.dueSoon);
  // Show what's unpaid, or else the three most recent paid ones.
  final shown = unpaid.isNotEmpty ? unpaid : bills.take(3).toList();

  return [
    SectionTitle(
      'My bills',
      trailing: TextButton(
        onPressed: () => context.go(AppRoutes.myBills),
        child: const Text('See all'),
      ),
    ),
    AppCard(
      color: AppColors.solidSoft(context, color),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(
            unpaid.isEmpty ? Icons.check_circle_rounded : Icons.receipt_long_rounded,
            color: color,
            size: 30,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  unpaid.isEmpty
                      ? 'All bills paid'
                      : 'To pay: ${toPay.entries.map((e) => formatMoney(e.value, e.key)).join(' + ')}',
                  style: text.titleMedium?.copyWith(color: color),
                ),
                Text(
                  unpaid.isEmpty
                      ? 'Nothing left to pay. Thank you!'
                      : '${unpaid.length} unpaid bill${unpaid.length == 1 ? '' : 's'}'
                          '${overdue > 0 ? ' · $overdue overdue' : ''}',
                  style: text.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    const SizedBox(height: 10),
    for (final b in shown.take(4))
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: AppCard(
          padding: const EdgeInsets.all(14),
          onTap: () => context.go(AppRoutes.myBills),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.soft(b.bill.status.color)),
                child: Icon(_billIcon(b.bill.title), color: b.bill.status.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(b.bill.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall),
                    Text(
                      '${formatMoney(b.bill.amount, b.currency)} · '
                      '${b.bill.isOpen ? 'due ${formatDate(b.bill.dueDate)}' : b.bill.status.label.toLowerCase()}',
                      style: text.bodySmall,
                    ),
                  ],
                ),
              ),
              StatusPill(label: b.bill.status.label, color: b.bill.status.color),
            ],
          ),
        ),
      ),
  ];
}

/// Water and electricity get their own icon; anything else a receipt.
IconData _billIcon(String title) {
  final lower = title.toLowerCase();
  if (lower.startsWith('water')) return Icons.water_drop_rounded;
  if (lower.startsWith('electric')) return Icons.bolt_rounded;
  return Icons.receipt_rounded;
}

/// The two newest announcements, with "See all".
List<Widget> _latestAnnouncements(BuildContext context, WidgetRef ref) {
  final list = ref.watch(myAnnouncementsProvider).value ?? const [];
  if (list.isEmpty) return const [];
  return [
    SectionTitle(
      'Announcements',
      trailing: TextButton(
        onPressed: () => context.push(AppRoutes.myAnnouncements),
        child: const Text('See all'),
      ),
    ),
    for (final a in list.take(2))
      Padding(padding: const EdgeInsets.only(bottom: 10), child: AnnouncementCard(announcement: a)),
  ];
}

class _RentalCard extends StatelessWidget {
  const _RentalCard({required this.rental});

  final MyRental rental;

  @override
  Widget build(BuildContext context) {
    final tenancy = rental.tenancy;
    final text = Theme.of(context).textTheme;
    final needsAgreement = tenancy.agreementAcceptedAt == null;
    final days = daysUntil(tenancy.paidUntil);

    return AppCard(
      padding: const EdgeInsets.all(10),
      onTap: () => context.push(AppRoutes.myRental(tenancy.id)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PropertyPhoto(
            seed: tenancy.propertyId,
            height: 150,
            borderRadius: 14,
            child: Align(
              alignment: Alignment.topRight,
              child: needsAgreement
                  ? const StatusPill(label: 'To accept', color: AppColors.primary)
                  : RentStatusPill(tenancy: tenancy),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 12, 6, 6),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Apartment ${tenancy.apartmentName}', style: text.titleMedium),
                      Text(rental.propertyName, style: text.bodySmall),
                    ],
                  ),
                ),
                if (!needsAgreement)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        days <= 0 ? 'Overdue' : timeLeftText(tenancy.paidUntil),
                        style: text.titleMedium?.copyWith(color: tenancyColor(tenancy)),
                      ),
                      Text(days <= 0 ? 'rent is late' : 'until rent is due', style: text.bodySmall),
                    ],
                  ),
              ],
            ),
          ),
          if (needsAgreement)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
              child: Text(
                'Tap to read and accept your tenancy agreement',
                style: text.bodySmall?.copyWith(color: AppColors.primary, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
    );
  }
}
