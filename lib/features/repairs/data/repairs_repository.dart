import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/repairs/data/repair.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// A unit's repair log. Reading and writing go through database functions
/// (migration 20261004100000): costs are hidden from staff who may not see
/// money, and a repair can bill the tenant in the same step.
class RepairsRepository {
  RepairsRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// A unit's repairs, newest first.
  Future<List<Repair>> fetchForApartment(String apartmentId) async {
    final rows = await _cache.rows('repairs/$apartmentId', () async {
      final result = await _client.rpc('apartment_repairs', params: {'p_apartment_id': apartmentId}) as List;
      return result.cast<Map<String, dynamic>>();
    });
    return rows.map(Repair.fromJson).toList();
  }

  /// Logs a repair. With [billAmount], the current tenant gets a "Repairs"
  /// bill for it, due on [billDue].
  Future<String> add({
    required String apartmentId,
    required String title,
    String? details,
    required DateTime repairedOn,
    int? cost,
    String? ticketId,
    int? billAmount,
    DateTime? billDue,
  }) async {
    final id = await _client.rpc('add_repair', params: {
      'p_apartment_id': apartmentId,
      'p_title': title,
      'p_details': details,
      'p_repaired_on': toDbDate(repairedOn),
      'p_cost': cost,
      'p_ticket_id': ticketId,
      'p_bill_amount': billAmount,
      'p_bill_due': billDue == null ? null : toDbDate(billDue),
    });
    return id as String;
  }

  Future<void> delete(String repairId) async {
    await _client.rpc('delete_repair', params: {'p_repair_id': repairId});
  }
}

final repairsRepositoryProvider = Provider<RepairsRepository>((ref) {
  return RepairsRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});

/// A unit's repairs, newest first.
final unitRepairsProvider = FutureProvider.autoDispose.family<List<Repair>, String>((ref, apartmentId) {
  return ref.watch(repairsRepositoryProvider).fetchForApartment(apartmentId);
});
