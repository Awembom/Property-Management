import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/data/receipts_repository.dart';
import 'package:rental_app/features/receipts/data/signed_receipt.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';

/// Signs a receipt that has no signature yet (sign-receipt Edge Function).
/// Null when offline: the QR code is added once the phone is back online.
final receiptSignatureProvider = FutureProvider.autoDispose.family<SignedReceipt?, String>((ref, paymentId) async {
  try {
    return await ref.watch(receiptsRepositoryProvider).sign(paymentId);
  } catch (e) {
    if (isNetworkError(e)) return null;
    rethrow;
  }
});

/// A receipt the tenant should still check (within its 24 hours).
class ReceiptToCheck {
  const ReceiptToCheck({required this.payment, required this.tenancyId, required this.currency, required this.deadline});

  final Payment payment;
  final String tenancyId;
  final String currency;
  final DateTime deadline;
}

/// The logged-in tenant's receipts waiting for a confirmation, soonest
/// deadline first (shown on their Home page).
final receiptsToCheckProvider = FutureProvider.autoDispose<List<ReceiptToCheck>>((ref) async {
  final rentals = await ref.watch(myRentalsProvider.future);
  final queued = ref.watch(queuedConfirmationsProvider);
  final all = <ReceiptToCheck>[];
  for (final rental in rentals) {
    final details = await ref.watch(myRentalDetailsProvider(rental.tenancy.id).future);
    for (final payment in details.payments) {
      final standing = ReceiptStanding.of(
        issuedAt: payment.issuedAt,
        isVoided: payment.isVoided,
        response: payment.response,
        tenantHasAccount: true,
        confirmationQueued: queued.contains(payment.id),
      );
      if (standing != null && standing.canAnswer) {
        all.add(ReceiptToCheck(
          payment: payment,
          tenancyId: rental.tenancy.id,
          currency: details.currency,
          deadline: standing.at!,
        ));
      }
    }
  }
  return all..sort((a, b) => a.deadline.compareTo(b.deadline));
});
