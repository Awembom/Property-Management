import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenant_access/data/my_rental.dart';
import 'package:rental_app/features/tenant_access/data/my_rental_details.dart';
import 'package:rental_app/features/tenant_access/data/tenant_invite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Getting people into the app: tenant invite codes, linking a tenant's
/// account, and temporary passwords.
///
/// Every action goes through a database function (or the reset-password Edge
/// Function) that checks the caller's role itself; see migration
/// 20261001160000_usernames_invites_password_reset.sql.
class TenantAccessRepository {
  TenantAccessRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  // ---------- staff side ----------

  /// The tenant's current, still valid invite code, or null.
  Future<TenantInvite?> fetchOpenInvite(String tenantId) async {
    final rows = await _cache.rows(
      'open_invite/$tenantId',
      () => _client
          .from('tenant_invites')
          .select('code, expires_at')
          .eq('tenant_id', tenantId)
          .isFilter('redeemed_at', null)
          .isFilter('cancelled_at', null)
          .gt('expires_at', DateTime.now().toUtc().toIso8601String())
          .order('created_at', ascending: false)
          .limit(1),
    );
    final invite = rows.isEmpty ? null : TenantInvite.fromJson(rows.first);
    // A saved code may have expired since (offline).
    return invite != null && invite.expiresAt.isAfter(DateTime.now()) ? invite : null;
  }

  /// A new 7-day code; any older code for this tenant stops working.
  Future<TenantInvite> createInvite(String tenantId) async {
    final rows = await _client.rpc('create_tenant_invite', params: {'p_tenant_id': tenantId}) as List;
    return TenantInvite.fromJson(rows.single as Map<String, dynamic>);
  }

  Future<void> cancelInvite(String tenantId) async {
    await _client.rpc('cancel_tenant_invite', params: {'p_tenant_id': tenantId});
  }

  /// Disconnects the app account from a tenant contact (wrong person linked).
  Future<void> unlinkAccount(String tenantId) async {
    await _client.rpc('unlink_tenant_account', params: {'p_tenant_id': tenantId});
  }

  /// Gives [userId] a temporary password (returned, to pass on to them).
  /// They must choose a new one when they next log in. The Edge Function
  /// refuses unless the database allows it (see password_reset_target).
  /// [propertyId] may be null only for the app admin.
  Future<String> resetPassword({required String? propertyId, required String userId}) async {
    try {
      final response = await _client.functions.invoke(
        'reset-password',
        body: {'property_id': propertyId, 'user_id': userId},
      );
      return (response.data as Map<String, dynamic>)['temporary_password'] as String;
    } on FunctionException catch (e) {
      // The function answers {"error": "..."} with a readable reason.
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      if (e.status == 404) {
        throw StateError('The reset-password function isn\'t deployed in Supabase yet.');
      }
      throw StateError(message ?? 'Could not reset the password.');
    }
  }

  // ---------- tenant side ----------

  /// Links the logged-in user to the tenant contact the code belongs to.
  Future<RedeemResult> redeemInvite(String code) async {
    final json = await _client.rpc('redeem_tenant_invite', params: {'p_code': code});
    return RedeemResult.fromJson(json as Map<String, dynamic>);
  }

  /// One rental of the logged-in tenant, with rent, balance and payments.
  /// RLS lets a tenant read their own tenancy, payments and receipts.
  Future<MyRentalDetails> fetchMyRentalDetails(String tenancyId) async {
    final overviewRow = await _cache.row(
      'tenancy_overview/$tenancyId',
      () => _client.from('tenancy_overview').select(TenancyOverview.columns).eq('id', tenancyId).maybeSingle(),
    );
    if (overviewRow == null) throw StateError('Rental not found');
    final tenancy = TenancyOverview.fromJson(overviewRow);

    final (rentRow, propertyRow, balanceRow, paymentRows) = await (
      _cache.row(
        'my_rent/$tenancyId',
        () => _client.from('tenancies').select('monthly_rent').eq('id', tenancyId).single(),
      ),
      _cache.row(
        'property_info/${tenancy.propertyId}',
        () => _client
            .from('properties')
            .select('name, address, currency, contact_phone')
            .eq('id', tenancy.propertyId)
            .single(),
      ),
      _cache.row(
        'tenancy_balance/$tenancyId',
        () => _client.from('tenancy_balances').select('balance').eq('tenancy_id', tenancyId).maybeSingle(),
      ),
      _cache.rows(
        'payments/$tenancyId',
        () => _client
            .from('payments')
            .select(Payment.columns)
            .eq('tenancy_id', tenancyId)
            .order('created_at', ascending: false),
      ),
    ).wait;

    return MyRentalDetails(
      tenancy: tenancy,
      tenantName: tenancy.tenantName,
      propertyName: propertyRow!['name'] as String,
      propertyAddress: propertyRow['address'] as String?,
      contactPhone: propertyRow['contact_phone'] as String?,
      currency: propertyRow['currency'] as String,
      monthlyRent: rentRow!['monthly_rent'] as int,
      balance: (balanceRow?['balance'] as int?) ?? 0,
      payments: paymentRows.map(Payment.fromJson).toList(),
    );
  }

  /// The tenant accepts their tenancy agreement (only they can).
  Future<void> acceptAgreement(String tenancyId) async {
    await _client.rpc('accept_tenancy_agreement', params: {'p_tenancy_id': tenancyId});
  }

  /// Active tenancies where the logged-in user is the (linked) tenant.
  Future<List<MyRental>> fetchMyRentals() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return [];

    final tenantRows = await _cache.rows(
      'my_tenant_records',
      () => _client.from('tenants').select('id').eq('user_id', userId),
    );
    if (tenantRows.isEmpty) return [];
    final tenantIds = tenantRows.map((row) => row['id'] as String).toList();

    final rows = await _cache.rows(
      'my_tenancies',
      () => _client
          .from('tenancy_overview')
          .select(TenancyOverview.columns)
          .inFilter('tenant_id', tenantIds)
          .eq('status', 'active'),
    );
    final tenancies = rows.map(TenancyOverview.fromJson).toList();
    if (tenancies.isEmpty) return [];

    // Tenants may read the name of a property they rent in.
    final propertyRows = await _cache.rows(
      'my_rental_properties',
      () => _client
          .from('properties')
          .select('id, name, currency')
          .inFilter('id', tenancies.map((t) => t.propertyId).toSet().toList()),
    );
    final byId = {for (final row in propertyRows) row['id'] as String: row};

    return [
      for (final tenancy in tenancies)
        MyRental(
          tenancy: tenancy,
          propertyName: (byId[tenancy.propertyId]?['name'] as String?) ?? '',
          currency: (byId[tenancy.propertyId]?['currency'] as String?) ?? 'XAF',
        ),
    ];
  }
}

final tenantAccessRepositoryProvider = Provider<TenantAccessRepository>((ref) {
  return TenantAccessRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
