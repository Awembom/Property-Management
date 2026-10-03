import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/announcements/data/announcement.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Announcements: the team sends, tenants read. The database decides who
/// sees which (everyone in the property, or only the chosen tenants).
class AnnouncementsRepository {
  AnnouncementsRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// All announcements of a property, newest first (the team's view).
  Future<List<Announcement>> fetchForProperty(String propertyId) async {
    final rows = await _cache.rows(
      'announcements/$propertyId',
      () => _client
          .from('announcements')
          .select(Announcement.columns)
          .eq('property_id', propertyId)
          .order('created_at', ascending: false),
    );
    return rows.map(Announcement.fromJson).toList();
  }

  /// Announcements meant for me as a tenant, newest first.
  Future<List<Announcement>> fetchMine(List<String> propertyIds) async {
    if (propertyIds.isEmpty) return [];
    final rows = await _cache.rows(
      'my_announcements',
      () => _client
          .from('announcements')
          .select(Announcement.columns)
          .inFilter('property_id', propertyIds)
          .order('created_at', ascending: false)
          .limit(50),
    );
    return rows.map(Announcement.fromJson).toList();
  }

  /// [tenantIds] empty = every current tenant of the property.
  Future<void> send({
    required String propertyId,
    required String title,
    required String body,
    List<String> tenantIds = const [],
  }) async {
    await _client.rpc('send_announcement', params: {
      'p_property_id': propertyId,
      'p_title': title,
      'p_body': body,
      'p_tenant_ids': tenantIds.isEmpty ? null : tenantIds,
    });
  }
}

final announcementsRepositoryProvider = Provider<AnnouncementsRepository>((ref) {
  return AnnouncementsRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
