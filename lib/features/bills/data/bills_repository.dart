import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bill types, bills and who has paid them. Creating a bill and marking it
/// paid go through database functions that check permissions.
class BillsRepository {
  BillsRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  // ---------- bill types ----------

  Future<List<BillType>> fetchTypes(String propertyId) async {
    final rows = await _cache.rows(
      'bill_types/$propertyId',
      () => _client
          .from('bill_types')
          .select(BillType.columns)
          .eq('property_id', propertyId)
          .order('is_standard', ascending: false)
          .order('name'),
    );
    return rows.map(BillType.fromJson).toList();
  }

  Future<void> addType(String propertyId, String name) async {
    await _client.from('bill_types').insert({'property_id': propertyId, 'name': name.trim()});
  }

  Future<void> setTypeEnabled(String typeId, bool enabled) async {
    final updated =
        await _client.from('bill_types').update({'enabled': enabled}).eq('id', typeId).select('id');
    if (updated.isEmpty) throw StateError('You don\'t have permission to change bill types.');
  }

  /// Only custom types, and only if no bill uses them yet.
  Future<void> deleteType(String typeId) async {
    try {
      final deleted = await _client.from('bill_types').delete().eq('id', typeId).select('id');
      if (deleted.isEmpty) throw StateError('This bill type can\'t be deleted.');
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        throw StateError('Bills already use this type. Switch it off instead.');
      }
      rethrow;
    }
  }

  // ---------- bills ----------

  /// A property's bills, newest first, with who paid.
  Future<List<Bill>> fetchBills(String propertyId) async {
    final rows = await _cache.rows(
      'bills/$propertyId',
      () => _client
          .from('bills')
          .select(Bill.columns)
          .eq('property_id', propertyId)
          .order('created_at', ascending: false),
    );
    // Also save each bill on its own, so it opens offline.
    for (final row in rows) {
      await _cache.put('bill/${row['id']}', row);
    }
    final names = await _names(rows, 'bill_names/$propertyId');
    return rows.map((row) => Bill.fromJson(row, names: names)).toList();
  }

  Future<Bill> fetchBill(String billId) async {
    final row = await _cache.row(
      'bill/$billId',
      () => _client.from('bills').select(Bill.columns).eq('id', billId).maybeSingle(),
    );
    if (row == null) throw StateError('Bill not found');
    return Bill.fromJson(row, names: await _names([row], 'bill_names/${row['property_id']}'));
  }

  /// A bill with its own amount for each apartment: [amounts] maps
  /// tenancy id -> amount (smallest currency unit).
  Future<String> createBillAmounts({
    required String propertyId,
    required String billTypeId,
    required DateTime dueDate,
    required Map<String, int> amounts,
    String? title,
    String? notes,
  }) async {
    final id = await _client.rpc('create_bill_amounts', params: {
      'p_property_id': propertyId,
      'p_bill_type_id': billTypeId,
      'p_due_date': toDbDate(dueDate),
      'p_amounts': amounts,
      'p_title': title,
      'p_notes': notes,
    });
    return id as String;
  }

  /// [tenancyIds] empty = every occupied apartment.
  Future<String> createBill({
    required String propertyId,
    required String billTypeId,
    required DateTime dueDate,
    required int amount,
    String? title,
    String? notes,
    List<String> tenancyIds = const [],
  }) async {
    final id = await _client.rpc('create_bill', params: {
      'p_property_id': propertyId,
      'p_bill_type_id': billTypeId,
      'p_due_date': toDbDate(dueDate),
      'p_amount': amount,
      'p_title': title,
      'p_notes': notes,
      'p_tenancy_ids': tenancyIds.isEmpty ? null : tenancyIds,
    });
    return id as String;
  }

  Future<void> setPaid(String assignmentId, bool paid) async {
    await _client.rpc('set_bill_paid', params: {'p_assignment_id': assignmentId, 'p_paid': paid});
  }

  /// Waives one apartment's part of a bill (with a reason), or undoes it.
  Future<void> setWaived(String assignmentId, {required bool waived, String? reason}) async {
    await _client.rpc('set_bill_waived', params: {
      'p_assignment_id': assignmentId,
      'p_waived': waived,
      'p_reason': reason,
    });
  }

  /// All bills of one unit (every tenancy it had), newest due date first.
  Future<List<MyBill>> fetchUnitBills(String apartmentId, List<String> tenancyIds) async {
    if (tenancyIds.isEmpty) return [];
    final rows = await _cache.rows(
      'unit_bills/$apartmentId',
      () => _client.from('bill_assignments').select(MyBill.columns).inFilter('tenancy_id', tenancyIds),
    );
    return rows.map(MyBill.fromJson).toList()..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  }

  /// A tenant's bills for one tenancy, newest first.
  Future<List<MyBill>> fetchMyBills(String tenancyId) async {
    final rows = await _cache.rows(
      'my_bills/$tenancyId',
      () => _client
          .from('bill_assignments')
          .select(MyBill.columns)
          .eq('tenancy_id', tenancyId),
    );
    final bills = rows.map(MyBill.fromJson).toList()..sort((a, b) => b.dueDate.compareTo(a.dueDate));
    return bills;
  }

  /// tenancy id -> {apartment_name, tenant_name}, for the bills' parts.
  /// Saved under [cacheKey] (one per property, so a single bill's names are
  /// found offline too: the property's list includes them).
  Future<Map<String, Map<String, dynamic>>> _names(List<Map<String, dynamic>> bills, String cacheKey) async {
    final ids = {
      for (final bill in bills)
        for (final a in (bill['assignments'] as List? ?? const []).cast<Map<String, dynamic>>())
          a['tenancy_id'] as String,
    }.toList();
    if (ids.isEmpty) return {};
    List<Map<String, dynamic>> rows;
    try {
      rows = await _cache.rows(
        bills.length == 1 ? '$cacheKey/${bills.single['id']}' : cacheKey,
        () => _client.from('tenancy_overview').select('id, apartment_name, tenant_name').inFilter('id', ids),
      );
    } on OfflineException {
      // Offline and this bill was never opened: the property's bill list
      // (downloaded in the background) has the same names. Else no names.
      rows = await _cache.savedRows(cacheKey).catchError((_) => <Map<String, dynamic>>[]);
    }
    return {for (final r in rows) r['id'] as String: r};
  }
}

final billsRepositoryProvider = Provider<BillsRepository>((ref) {
  return BillsRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
