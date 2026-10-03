import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/tenancies_repository.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';

/// All tenancies (current and past) of one apartment, newest first.
final apartmentTenanciesProvider = FutureProvider.autoDispose
    .family<List<TenancyOverview>, String>((ref, apartmentId) {
      return ref
          .watch(tenanciesRepositoryProvider)
          .fetchApartmentTenancies(apartmentId);
    });

/// One tenancy with its tenant, for the tenancy screen.
///
/// The argument is a record of two ids. Records compare by value, so
/// `(propertyId: 'a', tenancyId: 'b')` always means the same provider.
/// The property id is needed to know whether I may see rent amounts.
final tenancyDetailsProvider = FutureProvider.autoDispose
    .family<TenancyDetails, ({String propertyId, String tenancyId})>((
      ref,
      ids,
    ) async {
      final myProperty = await ref.watch(
        myPropertyProvider(ids.propertyId).future,
      );
      return ref
          .watch(tenanciesRepositoryProvider)
          .fetchTenancyDetails(
            ids.tenancyId,
            withMoney: myProperty.access.canSeeMoney,
          );
    });

/// Tenant contacts of a property (to pick an existing tenant).
final propertyTenantsProvider = FutureProvider.autoDispose
    .family<List<Tenant>, String>((ref, propertyId) {
      return ref.watch(tenanciesRepositoryProvider).fetchTenants(propertyId);
    });
