import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/tenancies/data/tenancies_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All Supabase calls for apartments.
///
/// Every staff member can read apartments; only owners and managers can add,
/// edit or delete them. That rule lives in the database (RLS), so a caretaker
/// calling these would simply be refused.
class ApartmentsRepository {
  ApartmentsRepository(this._client, this._cache, this._tenancies);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;
  final TenanciesRepository _tenancies;

  /// Apartments of a property with their current tenancy, sorted by name.
  Future<List<ApartmentWithTenancy>> fetchApartments(String propertyId) async {
    // Three small queries, run at the same time.
    final (rows, rentRows, activeTenancies) = await (
      _cache.rows(
        'apartments/$propertyId',
        () => _client.from('apartments').select(Apartment.columns).eq('property_id', propertyId),
      ),
      // Rents: the database returns no rows at all to caretakers.
      _cache.rows(
        'apartment_rents/$propertyId',
        () => _client
            .from('apartment_rents')
            .select('apartment_id, monthly_rent')
            .eq('property_id', propertyId),
      ),
      _tenancies.fetchActiveTenancies(propertyId),
    ).wait;

    // apartment id -> its rent / its active tenancy (at most one each).
    final rentByApartment = {
      for (final row in rentRows)
        row['apartment_id'] as String: row['monthly_rent'] as int,
    };
    final tenancyByApartment = {
      for (final t in activeTenancies) t.apartmentId: t,
    };

    return rows
        .map(Apartment.fromJson)
        .map(
          (apartment) => ApartmentWithTenancy(
            apartment: apartment.withMonthlyRent(rentByApartment[apartment.id]),
            activeTenancy: tenancyByApartment[apartment.id],
          ),
        )
        .toList()
      ..sort((a, b) => compareNatural(a.apartment.name, b.apartment.name));
  }

  Future<Apartment> fetchApartment(String apartmentId) async {
    final (row, rentRow) = await (
      _cache.row(
        'apartment/$apartmentId',
        () => _client.from('apartments').select(Apartment.columns).eq('id', apartmentId).maybeSingle(),
      ),
      _cache.row(
        'apartment_rent/$apartmentId',
        () => _client
            .from('apartment_rents')
            .select('monthly_rent')
            .eq('apartment_id', apartmentId)
            .maybeSingle(),
      ),
    ).wait;
    if (row == null) throw StateError('Apartment not found');
    return Apartment.fromJson(row)
        .withMonthlyRent(rentRow?['monthly_rent'] as int?);
  }

  /// Adds an apartment ([apartmentId] == null) or edits one, together with
  /// its monthly rent, in one step (the save_apartment database function).
  Future<void> saveApartment({
    required String propertyId,
    String? apartmentId,
    required String name,
    String? description,
    required int monthlyRent,
  }) async {
    // created_by is filled in by the database from the logged-in user.
    await _client.rpc(
      'save_apartment',
      params: {
        'p_property_id': propertyId,
        'p_apartment_id': apartmentId,
        'p_name': name,
        'p_description': description,
        'p_monthly_rent': monthlyRent,
      },
    );
  }

  /// Only works for apartments that never had a tenancy: the database keeps
  /// tenancy and payment history safe.
  Future<void> deleteApartment(String apartmentId) async {
    final deleted = await _client
        .from('apartments')
        .delete()
        .eq('id', apartmentId)
        .select('id');
    if (deleted.isEmpty) {
      throw StateError('Only owners and managers can delete apartments.');
    }
  }
}

final apartmentsRepositoryProvider = Provider<ApartmentsRepository>((ref) {
  return ApartmentsRepository(
    ref.watch(supabaseClientProvider),
    ref.watch(offlineCacheProvider),
    ref.watch(tenanciesRepositoryProvider),
  );
});
