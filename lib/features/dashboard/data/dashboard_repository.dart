import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/dashboard/data/dashboard.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Loads the numbers for the Home and Properties tabs with three queries for
/// ALL my properties at once (instead of a few queries per property).
class DashboardRepository {
  DashboardRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  Future<Dashboard> fetchDashboard(List<MyProperty> properties) async {
    if (properties.isEmpty) {
      return const Dashboard(properties: [], stats: {}, active: []);
    }
    final ids = properties.map((p) => p.property.id).toList();
    // Money only from properties where my role may see it (owner/manager).
    final moneyIds = [
      for (final p in properties)
        if (p.access.canSeeMoney) p.property.id,
    ];
    final firstOfMonth = DateTime(today().year, today().month);

    final (apartmentRows, tenancyRows, paymentRows) = await (
      _cache.rows(
        'dashboard/apartments',
        () => _client.from('apartments').select('property_id').inFilter('property_id', ids),
      ),
      _cache.rows(
        'dashboard/tenancies',
        () => _client
            .from('tenancy_overview')
            .select(TenancyOverview.columns)
            .inFilter('property_id', ids)
            .eq('status', 'active'),
      ),
      moneyIds.isEmpty
          ? Future.value(<Map<String, dynamic>>[])
          : _cache.rows(
              'dashboard/payments/${toDbDate(firstOfMonth)}',
              () => _client
                  .from('payments')
                  .select('property_id, amount, void:payment_voids(payment_id)')
                  .inFilter('property_id', moneyIds)
                  .gte('paid_on', toDbDate(firstOfMonth)),
            ),
    ).wait;

    final active = tenancyRows.map(TenancyOverview.fromJson).toList();
    final stats = <String, PropertyStats>{};
    for (final id in ids) {
      final mine = active.where((t) => t.propertyId == id);
      final collected = moneyIds.contains(id)
          ? paymentRows
              .where((row) => row['property_id'] == id && row['void'] == null)
              .fold<int>(0, (sum, row) => sum + (row['amount'] as int))
          : null;
      stats[id] = PropertyStats(
        apartments: apartmentRows.where((row) => row['property_id'] == id).length,
        occupied: mine.length,
        overdue: mine.where((t) => t.rentStatus == RentStatus.overdue).length,
        dueSoon: mine.where((t) => t.rentStatus == RentStatus.dueSoon).length,
        collectedThisMonth: collected,
      );
    }
    return Dashboard(properties: properties, stats: stats, active: active);
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>((ref) {
  return DashboardRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
