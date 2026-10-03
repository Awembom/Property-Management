import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/announcements/providers/announcements_providers.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/dashboard/providers/dashboard_providers.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/receipts/providers/receipts_providers.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Which screens' data to reload when a table changes. Whole families are
/// reloaded (e.g. every tenancy's payments); only the ones on screen
/// actually fetch again, the rest are simply forgotten.
final Map<String, List<ProviderOrFamily>> liveUpdateTargets = {
  'bills': _bills,
  'bill_assignments': _bills,
  'payments': _money,
  'payment_voids': _money,
  'receipt_responses': _money,
  'tenancies': [..._money, apartmentTenanciesProvider, myRentalsProvider],
  'apartments': [apartmentsProvider, apartmentProvider, dashboardProvider],
  'tickets': _tickets,
  'ticket_messages': _tickets,
  'announcements': [propertyAnnouncementsProvider, myAnnouncementsProvider],
  'notifications': [myNotificationsProvider],
};

final List<ProviderOrFamily> _bills = [
  propertyBillsProvider,
  billProvider,
  myBillsProvider,
  myHomeBillsProvider,
  unitBillsProvider,
  attentionItemsProvider,
];

final List<ProviderOrFamily> _money = [
  tenancyPaymentsProvider,
  paymentProvider,
  earlierReceiptsProvider,
  tenancyDetailsProvider,
  myRentalDetailsProvider,
  receiptsToCheckProvider,
  apartmentsProvider,
  dashboardProvider,
];

final List<ProviderOrFamily> _tickets = [
  propertyTicketsProvider,
  tenancyTicketsProvider,
  ticketProvider,
  ticketMessagesProvider,
  unitTicketsProvider,
  attentionItemsProvider,
];

/// Keeps open screens up to date without pulling down to refresh.
///
/// While the app is open and someone is logged in, one Supabase Realtime
/// channel listens to the tables in [liveUpdateTargets]. Supabase only sends
/// changes this account may see (the same RLS rules as reading). Changes
/// that arrive together are handled once, half a second later.
///
/// The channel closes when the app goes to the background (saves battery)
/// and opens again, with one full refresh, when it comes back.
class LiveUpdates {
  LiveUpdates(this._ref);

  final Ref _ref;
  RealtimeChannel? _channel;
  final _changed = <String>{};
  Timer? _debounce;

  SupabaseClient get _client => _ref.read(supabaseClientProvider);

  /// Starts listening (if logged in and not already listening).
  void start() {
    if (_channel != null || _client.auth.currentSession == null) return;
    var channel = _client.channel('homedly-live');
    for (final table in liveUpdateTargets.keys) {
      channel = channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: table,
        callback: (_) => tableChanged(table),
      );
    }
    _channel = channel.subscribe((status, error) {
      if (error != null) debugPrint('Live updates: $status $error');
    });
  }

  /// Stops listening (app in the background, or logged out).
  Future<void> stop() async {
    final channel = _channel;
    _channel = null;
    _debounce?.cancel();
    if (channel != null) await _client.removeChannel(channel);
  }

  /// Back in front: listen again and reload everything once (changes made
  /// while away were not heard).
  void resume() {
    start();
    _reload(liveUpdateTargets.keys.toSet());
  }

  /// A change in [table]: reload its screens shortly (grouping a burst of
  /// changes, e.g. one bill for ten apartments, into one reload).
  @visibleForTesting
  void tableChanged(String table, {Duration delay = const Duration(milliseconds: 500)}) {
    _changed.add(table);
    _debounce?.cancel();
    _debounce = Timer(delay, () {
      final tables = {..._changed};
      _changed.clear();
      _reload(tables);
    });
  }

  void _reload(Set<String> tables) {
    final targets = {for (final table in tables) ...?liveUpdateTargets[table]};
    for (final target in targets) {
      _ref.invalidate(target);
    }
  }
}

final liveUpdatesProvider = Provider<LiveUpdates>((ref) {
  final live = LiveUpdates(ref);
  ref.onDispose(live.stop);
  return live;
});
