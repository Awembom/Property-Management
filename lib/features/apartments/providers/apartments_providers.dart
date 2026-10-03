import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/data/bills_repository.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/data/tickets_repository.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/data/apartments_repository.dart';

// Same pattern as properties_providers.dart: FutureProvider + autoDispose +
// family (one provider per id). After a change, screens call
// ref.invalidate(...) so the data reloads.

/// The apartments of one property, each with its current tenancy.
final apartmentsProvider = FutureProvider.autoDispose
    .family<List<ApartmentWithTenancy>, String>((ref, propertyId) {
      return ref
          .watch(apartmentsRepositoryProvider)
          .fetchApartments(propertyId);
    });

/// One apartment by id.
final apartmentProvider = FutureProvider.autoDispose.family<Apartment, String>((
  ref,
  apartmentId,
) {
  return ref.watch(apartmentsRepositoryProvider).fetchApartment(apartmentId);
});

/// Every issue reported from a unit (by any of its tenants), newest first.
final unitTicketsProvider = FutureProvider.autoDispose.family<List<Ticket>, String>((ref, apartmentId) async {
  final tenancies = await ref.watch(apartmentTenanciesProvider(apartmentId).future);
  return ref.watch(ticketsRepositoryProvider).fetchForUnit(apartmentId, [for (final t in tenancies) t.id]);
});

/// Every bill a unit got (all its tenancies), newest due date first.
final unitBillsProvider = FutureProvider.autoDispose.family<List<MyBill>, String>((ref, apartmentId) async {
  final tenancies = await ref.watch(apartmentTenanciesProvider(apartmentId).future);
  return ref.watch(billsRepositoryProvider).fetchUnitBills(apartmentId, [for (final t in tenancies) t.id]);
});
