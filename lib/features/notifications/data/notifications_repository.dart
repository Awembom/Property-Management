import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/notifications/data/app_notification.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// The bell list, this phone's registration for push notifications, and the
/// team's rent-reminder controls (migration 20261005100000).
class NotificationsRepository {
  NotificationsRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// My latest notifications, newest first.
  Future<List<AppNotification>> fetchMine() async {
    final rows = await _cache.rows(
      'notifications',
      () => _client
          .from('notifications')
          .select(AppNotification.columns)
          .order('created_at', ascending: false)
          .limit(100),
    );
    return rows.map(AppNotification.fromJson).toList();
  }

  Future<void> markAllRead() async {
    await _client.rpc('mark_notifications_read');
  }

  /// This phone gets my push notifications (called after login).
  Future<void> registerDevice(String token) async {
    await _client.rpc(
      'register_device',
      params: {'p_token': token, 'p_platform': 'android'},
    );
  }

  /// This phone stops getting them (called just before logout).
  Future<void> unregisterDevice(String token) async {
    await _client.rpc('unregister_device', params: {'p_token': token});
  }

  /// Sends the unit's tenant a rent reminder now (at most every 6 hours).
  Future<void> sendRentReminder(String tenancyId) async {
    await _client.rpc(
      'send_rent_reminder',
      params: {'p_tenancy_id': tenancyId},
    );
  }

  /// Pauses the unit's automatic rent reminders for [days] days (0 = turn
  /// them back on). Returns the day they start again, or null if on.
  Future<DateTime?> setRemindersPaused(String tenancyId, int days) async {
    final until = await _client.rpc(
      'set_rent_reminders_muted',
      params: {'p_tenancy_id': tenancyId, 'p_days': days},
    );
    return until == null ? null : parseDbDate(until as String);
  }
}

final notificationsRepositoryProvider = Provider<NotificationsRepository>((
  ref,
) {
  return NotificationsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineCacheProvider),
  );
});

/// My notifications (the bell list).
final myNotificationsProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) {
      return ref.watch(notificationsRepositoryProvider).fetchMine();
    });

/// How many I haven't read (the number on the bell).
final unreadNotificationsProvider = Provider.autoDispose<int>((ref) {
  return (ref.watch(myNotificationsProvider).value ?? const [])
      .where((n) => !n.isRead)
      .length;
});
