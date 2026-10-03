import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/cache_cipher.dart';
import 'package:rental_app/core/offline/connection_status.dart';
import 'package:rental_app/core/offline/local_store.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';

/// Keeps the last answer of every read on the phone, so the app works offline.
///
/// Repositories wrap each Supabase query:
///
///     final rows = await _cache.rows('payments/$tenancyId', () => _client.from(...)...);
///
/// - Online: runs the query, saves the answer (encrypted, for the logged-in
///   account only) and returns it.
/// - No connection: returns the saved answer instead, however old. Nothing
///   saved yet: throws [OfflineException].
/// - The server says no (e.g. permission denied): that error is passed on as
///   usual; saved data is only for when the server can't be reached.
///
/// Saved answers are replaced by fresher ones and kept until then, also after
/// logout (they only open for the same account again; see SecureKeyVault).
class OfflineCache {
  OfflineCache({
    required this._store,
    required this._cipher,
    required this._account,
    required this._connection,
    required this._reportRequest,
    this.timeout = const Duration(seconds: 15),
  });

  final LocalStore _store;
  final CacheCipher _cipher;
  final String? Function() _account;
  final ConnectionInfo Function() _connection;
  final void Function({required bool reached}) _reportRequest;

  /// A request taking longer than this counts as "no connection".
  final Duration timeout;

  /// A list of rows (`select(...)` without single()).
  Future<List<Map<String, dynamic>>> rows(
    String key,
    Future<List<Map<String, dynamic>>> Function() fetch,
  ) async {
    final data = await _load(key, fetch);
    return (data as List).cast<Map<String, dynamic>>();
  }

  /// One row (`single()`), or null (`maybeSingle()`).
  Future<Map<String, dynamic>?> row(String key, Future<Map<String, dynamic>?> Function() fetch) async {
    return await _load(key, fetch) as Map<String, dynamic>?;
  }

  /// A plain JSON value, e.g. the bool from an rpc().
  Future<T> value<T>(String key, Future<T> Function() fetch) async {
    return await _load(key, fetch) as T;
  }

  /// Only what's saved under [key], without a request. Throws
  /// [OfflineException] if nothing is saved.
  Future<List<Map<String, dynamic>>> savedRows(String key) async {
    final account = _account();
    final saved = account == null ? null : await _readSaved(account, key);
    if (saved == null) throw const OfflineException();
    return (saved.$1 as List).cast<Map<String, dynamic>>();
  }

  /// Saves [json] under [key] without a request (e.g. each payment of a
  /// list, so its receipt opens offline).
  Future<void> put(String key, Object? json) async {
    final account = _account();
    if (account != null) await _save(account, key, json);
  }

  /// When this account's data was last saved (shown as "updated 2 h ago").
  Future<DateTime?> lastUpdated() async {
    final account = _account();
    return account == null ? null : _store.latestSave(account);
  }

  Future<Object?> _load(String key, Future<Object?> Function() fetch) async {
    final account = _account();
    if (account == null) return fetch(); // logged out: nothing to keep

    final connection = _connection();
    if (!connection.hasNetwork || connection.recentlyFailed) {
      // Known to be offline: answer from the phone straight away. Never
      // saved: try the network after all (it may be back).
      final saved = await _readSaved(account, key);
      if (saved != null) return saved.$1;
      if (!connection.hasNetwork) throw const OfflineException();
    }

    try {
      final data = await fetch().timeout(timeout);
      _reportRequest(reached: true);
      unawaited(_save(account, key, data));
      return data;
    } catch (error) {
      if (!isNetworkError(error)) rethrow;
      _reportRequest(reached: false);
      final saved = await _readSaved(account, key);
      if (saved == null) throw const OfflineException();
      return saved.$1;
    }
  }

  /// The saved value as a record, so a saved `null` (e.g. no balance row)
  /// isn't mistaken for "nothing saved".
  Future<(Object?,)?> _readSaved(String account, String key) async {
    try {
      final entry = await _store.read(account, key);
      if (entry == null) return null;
      return (jsonDecode(await _cipher.decrypt(account, entry.data)),);
    } catch (e) {
      debugPrint('Offline cache: could not read $key: $e');
      return null;
    }
  }

  Future<void> _save(String account, String key, Object? data) async {
    try {
      await _store.write(account, key, await _cipher.encrypt(account, jsonEncode(data)), DateTime.now());
    } catch (e) {
      debugPrint('Offline cache: could not save $key: $e');
    }
  }
}

/// The phone's offline database. Tests replace it with MemoryLocalStore.
final localStoreProvider = Provider<LocalStore>((ref) => SqliteLocalStore());

/// Where each account's encryption key is kept. Tests use MemoryKeyVault.
final keyVaultProvider = Provider<KeyVault>((ref) => SecureKeyVault());

final cacheCipherProvider = Provider<CacheCipher>((ref) => CacheCipher(ref.watch(keyVaultProvider)));

final offlineCacheProvider = Provider<OfflineCache>((ref) {
  final client = ref.watch(supabaseClientProvider);
  return OfflineCache(
    store: ref.watch(localStoreProvider),
    cipher: ref.watch(cacheCipherProvider),
    account: () => client.auth.currentUser?.id,
    connection: () => ref.read(connectionProvider),
    reportRequest: ({required reached}) =>
        ref.read(connectionProvider.notifier).reportRequest(reached: reached),
  );
});
