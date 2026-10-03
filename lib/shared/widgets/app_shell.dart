import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/receipts/providers/receipts_providers.dart';

/// The frame around the main tabs: the page, plus the bottom bar.
///
/// Landlords and team members get Home, Properties, Tenants and Profile.
/// Tenants get Home, Bills, Payments, Issues and Profile, so each list is one
/// tap away (unless someone also added them to a property's team).
/// Bills and Payments show a badge when something needs their attention.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.navigationShell});

  /// Provided by go_router: knows which tab (branch) is showing.
  final StatefulNavigationShell navigationShell;

  // Branch numbers, in the order they're declared in app_router.dart.
  static const _home = 0;
  static const _properties = 1;
  static const _tenants = 2;
  static const _profile = 3;
  static const _myBills = 4;
  static const _myPayments = 5;
  static const _myIssues = 6;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(myProfileProvider);
    // Right after login the account type isn't known yet: no bar for that
    // moment, rather than the wrong one (a tenant briefly seeing Properties).
    if (profile.isLoading && !profile.hasValue) {
      return Scaffold(body: navigationShell);
    }
    final accountType = profile.value?.accountType;
    final managesSomething = (ref.watch(myPropertiesProvider).value ?? const []).isNotEmpty;
    final staffTabs = accountType != AccountType.tenant || managesSomething;

    final branches = staffTabs
        ? [_home, _properties, _tenants, _profile]
        : [_home, _myBills, _myPayments, _myIssues, _profile];
    // Tenants: unpaid bills and receipts still to check.
    final unpaidBills = staffTabs
        ? 0
        : (ref.watch(myHomeBillsProvider).value ?? const []).where((b) => b.bill.isOpen).length;
    final toCheck = staffTabs ? 0 : (ref.watch(receiptsToCheckProvider).value ?? const []).length;
    final selected = branches.indexOf(navigationShell.currentIndex).clamp(0, branches.length - 1);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 20, offset: const Offset(0, -4)),
          ],
        ),
        child: NavigationBar(
          selectedIndex: selected,
          onDestinationSelected: (index) => navigationShell.goBranch(
            branches[index],
            // Tapping the current tab again goes back to its first page.
            initialLocation: branches[index] == navigationShell.currentIndex,
          ),
          destinations: [
            for (final branch in branches)
              switch (branch) {
                _myBills => _withBadge(_destinations[branch]!, unpaidBills),
                _myPayments => _withBadge(_destinations[branch]!, toCheck),
                _ => _destinations[branch]!,
              },
          ],
        ),
      ),
    );
  }

  /// The same tab with a small count on its icon (nothing if 0).
  static NavigationDestination _withBadge(NavigationDestination d, int count) {
    if (count == 0) return d;
    return NavigationDestination(
      icon: Badge.count(count: count, child: d.icon),
      selectedIcon: Badge.count(count: count, child: d.selectedIcon ?? d.icon),
      label: d.label,
    );
  }

  static const _destinations = {
    _home: NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home_rounded),
      label: 'Home',
    ),
    _properties: NavigationDestination(
      icon: Icon(Icons.apartment_outlined),
      selectedIcon: Icon(Icons.apartment_rounded),
      label: 'Properties',
    ),
    _tenants: NavigationDestination(
      icon: Icon(Icons.people_alt_outlined),
      selectedIcon: Icon(Icons.people_alt_rounded),
      label: 'Tenants',
    ),
    _myBills: NavigationDestination(
      icon: Icon(Icons.receipt_outlined),
      selectedIcon: Icon(Icons.receipt_rounded),
      label: 'Bills',
    ),
    _myPayments: NavigationDestination(
      icon: Icon(Icons.payments_outlined),
      selectedIcon: Icon(Icons.payments_rounded),
      label: 'Payments',
    ),
    _myIssues: NavigationDestination(
      icon: Icon(Icons.build_circle_outlined),
      selectedIcon: Icon(Icons.build_circle_rounded),
      label: 'Issues',
    ),
    _profile: NavigationDestination(
      icon: Icon(Icons.person_outline_rounded),
      selectedIcon: Icon(Icons.person_rounded),
      label: 'Profile',
    ),
  };
}
