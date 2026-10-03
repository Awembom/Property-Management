import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/core/offline/cache_cipher.dart';
import 'package:rental_app/core/offline/connection_status.dart';
import 'package:rental_app/core/offline/local_store.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/shared/widgets/offline_banner.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// An OfflineCache with memory storage, a switchable account and connection.
class Harness {
  final store = MemoryLocalStore();
  final cipher = CacheCipher(MemoryKeyVault());
  String? account = 'tina';
  var connection = const ConnectionInfo(hasNetwork: true, serverReachable: true);
  final reports = <bool>[];

  late final cache = OfflineCache(
    store: store,
    cipher: cipher,
    account: () => account,
    connection: () => connection,
    reportRequest: ({required reached}) => reports.add(reached),
  );
}

List<Map<String, dynamic>> rowsOf(String name) => [
      {'id': '1', 'name': name},
    ];

void main() {
  test('online: returns fresh data and saves it; offline: the saved copy', () async {
    final h = Harness();
    expect(await h.cache.rows('apartments/p1', () async => rowsOf('A1')), rowsOf('A1'));
    await Future<void>.delayed(Duration.zero); // saving runs in the background

    // The request fails for lack of connection: the saved answer comes back.
    final offline = await h.cache.rows('apartments/p1', () async => throw const SocketException('no route'));
    expect(offline, rowsOf('A1'));
    expect(h.reports, [true, false]);
  });

  test('fresher data replaces the saved copy', () async {
    final h = Harness();
    await h.cache.rows('k', () async => rowsOf('old'));
    await h.cache.rows('k', () async => rowsOf('new'));
    await Future<void>.delayed(Duration.zero);
    h.connection = const ConnectionInfo(hasNetwork: false, serverReachable: false);
    expect(await h.cache.rows('k', () async => fail('must not call the server')), rowsOf('new'));
  });

  test('no network at all: answers from the phone without trying the server', () async {
    final h = Harness();
    await h.cache.row('my_profile', () async => {'id': 'u1'});
    await Future<void>.delayed(Duration.zero);
    h.connection = const ConnectionInfo(hasNetwork: false, serverReachable: false);
    expect(await h.cache.row('my_profile', () async => fail('no request offline')), {'id': 'u1'});
  });

  test('offline and never loaded: OfflineException', () async {
    final h = Harness();
    h.connection = const ConnectionInfo(hasNetwork: false, serverReachable: false);
    expect(() => h.cache.rows('never', () async => rowsOf('x')), throwsA(isA<OfflineException>()));
  });

  test('a saved "nothing" (null) is not mistaken for "never saved"', () async {
    final h = Harness();
    await h.cache.row('tenancy_balance/t1', () async => null);
    await Future<void>.delayed(Duration.zero);
    expect(await h.cache.row('tenancy_balance/t1', () async => throw const SocketException('x')), isNull);
  });

  test('the server saying no is passed on, not hidden behind old data', () async {
    final h = Harness();
    await h.cache.rows('k', () async => rowsOf('A1'));
    await Future<void>.delayed(Duration.zero);
    expect(
      () => h.cache.rows('k', () async => throw const PostgrestException(message: 'denied', code: '42501')),
      throwsA(isA<PostgrestException>()),
    );
  });

  test('saved data only opens for the same account', () async {
    final h = Harness();
    await h.cache.rows('k', () async => rowsOf('Tina\'s'));
    await Future<void>.delayed(Duration.zero);

    // Someone else logs in on the same phone, offline: nothing for them.
    h.account = 'paul';
    h.connection = const ConnectionInfo(hasNetwork: false, serverReachable: false);
    expect(() => h.cache.rows('k', () async => rowsOf('x')), throwsA(isA<OfflineException>()));

    // Tina logs back in: her data is still there.
    h.account = 'tina';
    expect(await h.cache.rows('k', () async => rowsOf('x')), rowsOf('Tina\'s'));
  });

  test('data on the phone is encrypted, and is unreadable with another key', () async {
    final h = Harness();
    await h.cache.rows('k', () async => rowsOf('Sunset Court'));
    await Future<void>.delayed(Duration.zero);
    final entry = await h.store.read('tina', 'k');
    expect(String.fromCharCodes(entry!.data).contains('Sunset'), isFalse);
    expect(() => h.cipher.decrypt('paul', entry.data), throwsA(anything));
    expect(await h.cipher.decrypt('tina', entry.data), contains('Sunset Court'));
  });

  test('which errors count as "no connection"', () {
    expect(isNetworkError(const SocketException('x')), isTrue);
    expect(isNetworkError(const OfflineException()), isTrue);
    expect(isNetworkError(AuthRetryableFetchException()), isTrue);
    expect(isNetworkError(const PostgrestException(message: 'denied')), isFalse);
    expect(isNetworkError(StateError('Only owners can remove members.')), isFalse);
  });

  test('outbox items survive being saved and read back', () {
    final item = OutboxItem.ticketMessage(ticketId: 'k1', body: 'Still leaking');
    final back = OutboxItem.fromJson(item.toJson());
    expect(back.id, item.id);
    expect(back.kind, OutboxKind.ticketMessage);
    expect(back.asMessage(fromStaff: false).pending, isTrue);
    expect(back.asMessage(fromStaff: false).body, 'Still leaking');

    final ticket = OutboxItem.newTicket(
      tenancyId: 't1',
      title: 'Broken lock',
      description: null,
      category: TicketCategory.security,
    ).asTicket();
    expect(ticket.pending, isTrue);
    expect(ticket.category, TicketCategory.security);
    expect(RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$').hasMatch(newUuid()), isTrue);
  });

  test('offline strip details', () {
    final now = DateTime(2026, 10, 2, 12);
    expect(offlineDetails(null, 0, now: now), 'Offline');
    expect(offlineDetails(now.subtract(const Duration(hours: 2)), 0, now: now), 'Offline · last updated 2 h ago');
    expect(
      offlineDetails(now.subtract(const Duration(minutes: 5)), 1, now: now),
      'Offline · last updated 5 min ago · 1 waiting to send',
    );
  });
}
