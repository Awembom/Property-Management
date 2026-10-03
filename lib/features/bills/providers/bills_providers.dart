import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/data/bills_repository.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';

final billTypesProvider = FutureProvider.autoDispose.family<List<BillType>, String>((ref, propertyId) {
  return ref.watch(billsRepositoryProvider).fetchTypes(propertyId);
});

final propertyBillsProvider = FutureProvider.autoDispose.family<List<Bill>, String>((ref, propertyId) {
  return ref.watch(billsRepositoryProvider).fetchBills(propertyId);
});

final billProvider = FutureProvider.autoDispose.family<Bill, String>((ref, billId) {
  return ref.watch(billsRepositoryProvider).fetchBill(billId);
});

/// A tenant's bills for one tenancy.
final myBillsProvider = FutureProvider.autoDispose.family<List<MyBill>, String>((ref, tenancyId) {
  return ref.watch(billsRepositoryProvider).fetchMyBills(tenancyId);
});

/// One of my bills on the Home page, with where it's for and the currency.
class HomeBill {
  const HomeBill({required this.bill, required this.tenancyId, required this.apartmentName, required this.currency});

  final MyBill bill;
  final String tenancyId;
  final String apartmentName;
  final String currency;
}

/// All my bills across the homes I rent: unpaid and overdue first (soonest
/// due first), then paid ones (newest first).
final myHomeBillsProvider = FutureProvider.autoDispose<List<HomeBill>>((ref) async {
  final rentals = await ref.watch(myRentalsProvider.future);
  final repository = ref.watch(billsRepositoryProvider);
  final lists = await Future.wait([
    for (final rental in rentals)
      repository.fetchMyBills(rental.tenancy.id).then((bills) => [
            for (final bill in bills)
              HomeBill(
                bill: bill,
                tenancyId: rental.tenancy.id,
                apartmentName: rental.tenancy.apartmentName,
                currency: rental.currency,
              ),
          ]),
  ]);
  final all = lists.expand((l) => l).toList()
    ..sort((a, b) {
      final aPaid = !a.bill.isOpen, bPaid = !b.bill.isOpen;
      if (aPaid != bPaid) return aPaid ? 1 : -1;
      return aPaid ? b.bill.dueDate.compareTo(a.bill.dueDate) : a.bill.dueDate.compareTo(b.bill.dueDate);
    });
  return all;
});
