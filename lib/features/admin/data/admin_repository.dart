import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/admin/data/activity_entry.dart';
import 'package:rental_app/features/admin/data/admin_models.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything the super admin screen reads.
///
/// All of this is READ-ONLY: the database gives the admin extra SELECT
/// policies and nothing else (migration 20261001170000). The only actions are
/// transferOwnership() and password resets (TenantAccessRepository), both of
/// which check is_app_admin() in the database.
class AdminRepository {
  AdminRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// Is the logged-in user the app admin?
  Future<bool> isAppAdmin() async {
    if (_client.auth.currentUser == null) return false;
    return _cache.value<bool>('is_app_admin', () async => await _client.rpc('is_app_admin') as bool);
  }

  /// Newest changes first.
  Future<List<ActivityEntry>> fetchActivity({int limit = 200, String? propertyId}) async {
    var query = _client.from('activity_log').select(ActivityEntry.columns);
    if (propertyId != null) query = query.eq('property_id', propertyId);
    final rows = await query.order('happened_at', ascending: false).limit(limit);
    return rows.map(ActivityEntry.fromJson).toList();
  }

  Future<List<AdminProperty>> fetchProperties() async {
    final (propertyRows, ownerRows, apartmentRows) = await (
      _client.from('properties').select('id, name, address, currency').order('name'),
      _client
          .from('memberships')
          .select('property_id, profile:profiles(full_name, username)')
          .eq('role', 'owner'),
      _client.from('apartments').select('property_id'),
    ).wait;

    final owners = <String, List<String>>{};
    for (final row in ownerRows) {
      final profile = row['profile'] as Map<String, dynamic>?;
      final name = [
        if (profile?['full_name'] != null) profile!['full_name'] as String,
        if (profile?['username'] != null) '@${profile!['username']}',
      ].join(' ');
      owners.putIfAbsent(row['property_id'] as String, () => []).add(name);
    }
    final apartments = <String, int>{};
    for (final row in apartmentRows) {
      final id = row['property_id'] as String;
      apartments[id] = (apartments[id] ?? 0) + 1;
    }

    return [
      for (final row in propertyRows)
        AdminProperty(
          id: row['id'] as String,
          name: row['name'] as String,
          address: row['address'] as String?,
          currency: row['currency'] as String,
          owners: owners[row['id']] ?? const [],
          apartmentCount: apartments[row['id']] ?? 0,
        ),
    ];
  }

  Future<List<AdminPerson>> fetchPeople() async {
    final (profileRows, membershipRows, tenantRows) = await (
      _client
          .from('profiles')
          .select('id, username, full_name, account_type, created_at')
          .order('created_at', ascending: false),
      _client.from('memberships').select('user_id'),
      _client.from('tenants').select('user_id').not('user_id', 'is', null),
    ).wait;

    int countFor(List<Map<String, dynamic>> rows, String id) =>
        rows.where((row) => row['user_id'] == id).length;

    return [
      for (final row in profileRows)
        AdminPerson(
          id: row['id'] as String,
          username: row['username'] as String?,
          fullName: row['full_name'] as String?,
          accountType: AccountType.fromJson(row['account_type'] as String?),
          createdAt: DateTime.parse(row['created_at'] as String).toLocal(),
          propertyCount: countFor(membershipRows, row['id'] as String),
          rentalCount: countFor(tenantRows, row['id'] as String),
        ),
    ];
  }

  /// Makes [username] an owner of the property (admin only). Needed before
  /// the account of a property's only owner can be deleted.
  Future<void> transferOwnership({required String propertyId, required String username}) async {
    await _client.rpc('admin_transfer_ownership', params: {
      'p_property_id': propertyId,
      'p_username': username,
    });
  }
}

final adminRepositoryProvider = Provider<AdminRepository>((ref) {
  return AdminRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
