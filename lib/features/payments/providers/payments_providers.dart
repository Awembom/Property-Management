import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/data/payments_repository.dart';

/// Payments of one tenancy, newest first.
final tenancyPaymentsProvider =
    FutureProvider.autoDispose.family<List<Payment>, String>((ref, tenancyId) {
  return ref.watch(paymentsRepositoryProvider).fetchTenancyPayments(tenancyId);
});

/// Earlier receipts with the same reference code as this payment (oldest
/// first): what goes on the extra pages of its PDF.
final earlierReceiptsProvider =
    FutureProvider.autoDispose.family<List<Payment>, String>((ref, paymentId) async {
  final payment = await ref.watch(paymentProvider(paymentId).future);
  return ref.watch(paymentsRepositoryProvider).fetchEarlierWithSameReference(payment);
});

/// One payment (for its receipt).
final paymentProvider = FutureProvider.autoDispose.family<Payment, String>((ref, paymentId) {
  return ref.watch(paymentsRepositoryProvider).fetchPayment(paymentId);
});
