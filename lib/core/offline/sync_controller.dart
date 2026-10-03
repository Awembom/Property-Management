import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/connection_status.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/announcements/data/announcements_repository.dart';
import 'package:rental_app/features/apartments/data/apartments_repository.dart';
import 'package:rental_app/features/auth/data/profile_repository.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/bills/data/bills_repository.dart';
import 'package:rental_app/features/dashboard/data/dashboard_repository.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';
import 'package:rental_app/features/payments/data/payments_repository.dart';
import 'package:rental_app/features/properties/data/properties_repository.dart';
import 'package:rental_app/features/repairs/data/repairs_repository.dart';
import 'package:rental_app/features/tenancies/data/tenancies_repository.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tickets/data/tickets_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Keeps the phone ready for offline use:
/// - sends the outbox (things done offline) when the connection is back;
/// - downloads the main data in the background, so every main screen opens
///   offline, not only the ones visited.
///
/// Runs after login, when the app comes back to the front, and when the
/// connection returns; the download at most every [_minGap].
class SyncController {
  SyncController(this._ref);

  final Ref _ref;
  bool _running = false;
  DateTime? _lastDownload;

  static const _minGap = Duration(minutes: 3);

  /// [force]: download even if it was done a moment ago.
  Future<void> syncNow({bool force = false}) async {
    if (_running) return;
    if (_ref.read(supabaseClientProvider).auth.currentUser == null) return;
    if (!_ref.read(connectionProvider).online) return;
    _running = true;
    try {
      await _ref.read(outboxProvider.notifier).flush();
      final last = _lastDownload;
      if (force || last == null || DateTime.now().difference(last) > _minGap) {
        await downloadForOffline(_ref);
        _lastDownload = DateTime.now();
      }
    } catch (e) {
      debugPrint('Sync stopped: $e');
    } finally {
      _running = false;
    }
  }
}

final syncControllerProvider = Provider<SyncController>((ref) {
  final controller = SyncController(ref);
  // Connection back: send what waited and refresh.
  ref.listen(connectionProvider, (previous, next) {
    if (next.online && previous?.online == false) unawaited(controller.syncNow());
  });
  // Logged in (or the app started with a saved login).
  ref.listen(authStateProvider, (previous, next) {
    final event = next.value?.event;
    if (next.value?.session != null &&
        (event == AuthChangeEvent.signedIn || event == AuthChangeEvent.initialSession)) {
      unawaited(controller.syncNow(force: true));
    }
  });
  return controller;
});

/// Loads what the main screens show, the same way they load it, so it's
/// saved for offline use. Errors in one part don't stop the rest.
Future<void> downloadForOffline(Ref ref) async {
  Future<void> step(String what, Future<void> Function() load) async {
    try {
      await load();
    } catch (e) {
      debugPrint('Offline download: $what failed: $e');
    }
  }

  await step('profile', () => ref.read(profileRepositoryProvider).fetchMyProfile());
  await step('notifications', () => ref.read(notificationsRepositoryProvider).fetchMine());

  // ---- staff: my properties and everything in them ----
  final properties = ref.read(propertiesRepositoryProvider);
  final apartments = ref.read(apartmentsRepositoryProvider);
  final tenancies = ref.read(tenanciesRepositoryProvider);
  final payments = ref.read(paymentsRepositoryProvider);
  final bills = ref.read(billsRepositoryProvider);
  final tickets = ref.read(ticketsRepositoryProvider);
  final announcements = ref.read(announcementsRepositoryProvider);
  final repairs = ref.read(repairsRepositoryProvider);
  final tenantAccess = ref.read(tenantAccessRepositoryProvider);

  final mine = await properties.fetchMyProperties().catchError((_) => const <Never>[]);
  await step('dashboard', () => ref.read(dashboardRepositoryProvider).fetchDashboard(mine));

  for (final myProperty in mine) {
    final id = myProperty.property.id;
    final access = myProperty.access;
    await Future.wait([
      step('property', () => properties.fetchMyProperty(id)),
      step('members', () => properties.fetchMembers(id)),
      step('bills', () => bills.fetchBills(id)),
      step('bill types', () => bills.fetchTypes(id)),
      step('announcements', () => announcements.fetchForProperty(id)),
      step('tenants', () => tenancies.fetchTenants(id)),
    ]);

    await step('apartments', () async {
      final list = await apartments.fetchApartments(id);
      for (final item in list) {
        final apartmentId = item.apartment.id;
        await Future.wait([
          step('apartment', () => apartments.fetchApartment(apartmentId)),
          step('repairs', () => repairs.fetchForApartment(apartmentId)),
          // The unit page: its issues and bills, from all its tenancies.
          step('unit history', () async {
            final ids = [for (final t in await tenancies.fetchApartmentTenancies(apartmentId)) t.id];
            await Future.wait([
              step('unit issues', () => tickets.fetchForUnit(apartmentId, ids)),
              step('unit bills', () => bills.fetchUnitBills(apartmentId, ids)),
            ]);
          }),
        ]);
        final tenancy = item.activeTenancy;
        if (tenancy == null) continue;
        await Future.wait([
          step('tenancy', () => tenancies.fetchTenancyDetails(tenancy.id, withMoney: access.canSeeMoney)),
          if (access.canSeeMoney) step('payments', () => payments.fetchTenancyPayments(tenancy.id)),
          // The tenant's invite code, shown on the tenancy screen.
          if (access.canManageTenancies)
            step('invite', () => tenantAccess.fetchOpenInvite(tenancy.tenantId)),
        ]);
      }
    });

    await step('tickets', () async {
      final list = await tickets.fetchForProperty(id);
      // The conversations of the 20 most recently active tickets.
      for (final ticket in list.take(20)) {
        await step('ticket messages', () => tickets.fetchMessages(ticket.id));
      }
    });
  }

  // ---- tenant: my homes ----
  final rentals = await tenantAccess.fetchMyRentals().catchError((_) => const <Never>[]);
  if (rentals.isNotEmpty) {
    await step(
      'my announcements',
      () => announcements.fetchMine(rentals.map((r) => r.tenancy.propertyId).toSet().toList()),
    );
  }
  for (final rental in rentals) {
    final tenancyId = rental.tenancy.id;
    await Future.wait([
      step('my rental', () => tenantAccess.fetchMyRentalDetails(tenancyId)),
      step('my bills', () => bills.fetchMyBills(tenancyId)),
      step('my tickets', () async {
        final list = await tickets.fetchForTenancy(tenancyId);
        for (final ticket in list.take(20)) {
          await step('ticket', () => tickets.fetchTicket(ticket.id));
          await step('ticket messages', () => tickets.fetchMessages(ticket.id));
        }
      }),
    ]);
  }
}
