import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All Supabase calls for tenancies and tenant contacts.
///
/// Lists read the `tenancy_overview` view (no money, so it works for every
/// role). Rent amounts are read from `tenancies` only when the caller may
/// see money. Starting and ending go through database functions so they
/// happen all-or-nothing (migration 20261001120000_apartments_tenancies.sql).
class TenanciesRepository {
  TenanciesRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// Every tenancy of one apartment, newest first.
  Future<List<TenancyOverview>> fetchApartmentTenancies(
    String apartmentId,
  ) async {
    final rows = await _cache.rows(
      'apartment_tenancies/$apartmentId',
      () => _client
          .from('tenancy_overview')
          .select(TenancyOverview.columns)
          .eq('apartment_id', apartmentId)
          .order('start_date', ascending: false),
    );
    return rows.map(TenancyOverview.fromJson).toList();
  }

  /// The active tenancies of a property (one per occupied apartment).
  Future<List<TenancyOverview>> fetchActiveTenancies(String propertyId) async {
    final rows = await _cache.rows(
      'active_tenancies/$propertyId',
      () => _client
          .from('tenancy_overview')
          .select(TenancyOverview.columns)
          .eq('property_id', propertyId)
          .eq('status', 'active'),
    );
    return rows.map(TenancyOverview.fromJson).toList();
  }

  /// One tenancy with its tenant contact. If [withMoney] (owners/managers),
  /// also the rent, balance owed, renewals and the tenant's ID number.
  Future<TenancyDetails> fetchTenancyDetails(String tenancyId, {required bool withMoney}) async {
    final overviewRow = await _cache.row(
      'tenancy_overview/$tenancyId',
      () => _client.from('tenancy_overview').select(TenancyOverview.columns).eq('id', tenancyId).maybeSingle(),
    );
    if (overviewRow == null) throw StateError('Tenancy not found');
    final overview = TenancyOverview.fromJson(overviewRow);

    final tenantRow = await _cache.row(
      'tenant/${overview.tenantId}',
      () => _client.from('tenants').select(Tenant.columns).eq('id', overview.tenantId).single(),
    );
    var tenant = Tenant.fromJson(tenantRow!);

    if (!withMoney) return TenancyDetails(overview: overview, tenant: tenant);

    // Five small queries at the same time. Each table is protected by RLS,
    // which is why caretakers never get here (withMoney is false for them).
    final (moneyRow, standardRow, balanceRow, renewalRows, identityRow) = await (
      _cache.row(
        'tenancy_money/$tenancyId',
        () => _client.from('tenancies').select(TenancyMoney.columns).eq('id', tenancyId).maybeSingle(),
      ),
      _cache.row(
        'apartment_rent/${overview.apartmentId}',
        () => _client
            .from('apartment_rents')
            .select('monthly_rent')
            .eq('apartment_id', overview.apartmentId)
            .maybeSingle(),
      ),
      _cache.row(
        'tenancy_balance/$tenancyId',
        () => _client.from('tenancy_balances').select('balance').eq('tenancy_id', tenancyId).maybeSingle(),
      ),
      _cache.rows(
        'tenancy_renewals/$tenancyId',
        () => _client
            .from('tenancy_renewals')
            .select(TenancyRenewal.columns)
            .eq('tenancy_id', tenancyId)
            .order('created_at', ascending: false),
      ),
      _cache.row(
        'tenant_identity/${overview.tenantId}',
        () => _client
            .from('tenant_identities')
            .select('id_number')
            .eq('tenant_id', overview.tenantId)
            .maybeSingle(),
      ),
    ).wait;

    tenant = tenant.withIdNumber(identityRow?['id_number'] as String?);
    TenancyMoney? money;
    if (moneyRow != null) {
      money = TenancyMoney(
        monthlyRent: moneyRow['monthly_rent'] as int,
        notes: moneyRow['notes'] as String?,
        standardMonthlyRent: standardRow?['monthly_rent'] as int?,
        balance: (balanceRow?['balance'] as int?) ?? 0,
        renewals: renewalRows.map(TenancyRenewal.fromJson).toList(),
      );
    }
    return TenancyDetails(overview: overview, tenant: tenant, money: money);
  }

  /// Tenant contacts of a property, by name (to pick an existing one).
  Future<List<Tenant>> fetchTenants(String propertyId) async {
    final rows = await _cache.rows(
      'tenants/$propertyId',
      () => _client.from('tenants').select(Tenant.columns).eq('property_id', propertyId).order('full_name'),
    );
    return rows.map(Tenant.fromJson).toList();
  }

  /// Starts a tenancy (creating the tenant contact if new). Returns its id.
  Future<String> startTenancy(NewTenancy tenancy) async {
    final id = await _client.rpc(
      'start_tenancy',
      params: tenancy.toRpcParams(),
    );
    return id as String;
  }

  /// Ends a tenancy on [moveOutDate]; the apartment becomes vacant.
  Future<void> endTenancy(String tenancyId, DateTime moveOutDate) async {
    await _client.rpc(
      'end_tenancy',
      params: {
        'p_tenancy_id': tenancyId,
        'p_move_out_date': toDbDate(moveOutDate),
      },
    );
  }

  /// Changes how often rent is paid and the notes. (The rent and the lease
  /// end change through [renewTenancy], so a record of the change is kept.)
  Future<void> updateTenancyTerms({
    required String tenancyId,
    required int paymentIntervalMonths,
    required String? notes,
  }) async {
    final updated = await _client
        .from('tenancies')
        .update({'payment_interval_months': paymentIntervalMonths, 'notes': notes})
        .eq('id', tenancyId)
        .select('id');
    // RLS blocks silently (0 rows) instead of raising an error.
    if (updated.isEmpty) {
      throw StateError('Only owners and managers can change a tenancy.');
    }
  }

  /// Continues a tenancy: a new lease end date and, optionally, a new monthly
  /// rent. The database keeps a record of the old and new values.
  Future<void> renewTenancy({
    required String tenancyId,
    required DateTime newEndDate,
    int? newMonthlyRent,
    String? notes,
  }) async {
    await _client.rpc('renew_tenancy', params: {
      'p_tenancy_id': tenancyId,
      'p_new_end_date': toDbDate(newEndDate),
      'p_new_monthly_rent': newMonthlyRent,
      'p_notes': notes,
    });
  }

  /// Sets the tenant's ID card number; null or empty removes it.
  Future<void> setTenantIdNumber(String tenantId, String? idNumber) async {
    await _client.rpc('set_tenant_id_number', params: {
      'p_tenant_id': tenantId,
      'p_id_number': idNumber,
    });
  }

  Future<void> updateTenant(Tenant tenant) async {
    final updated = await _client
        .from('tenants')
        .update(tenant.toUpdateJson())
        .eq('id', tenant.id)
        .select('id');
    if (updated.isEmpty) {
      throw StateError('Only owners and managers can edit tenants.');
    }
  }
}

final tenanciesRepositoryProvider = Provider<TenanciesRepository>((ref) {
  return TenanciesRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
