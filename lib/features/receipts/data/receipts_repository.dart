import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/data/signed_receipt.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Signing receipts and the tenant's answer to them (migration
/// 20261003100000_receipt_signatures_confirmations.sql).
class ReceiptsRepository {
  ReceiptsRepository(this._client);

  final SupabaseClient _client;

  /// Asks the sign-receipt Edge Function to sign this payment's receipt (it
  /// returns the stored signature if it was signed before).
  Future<SignedReceipt> sign(String paymentId) async {
    try {
      final response = await _client.functions.invoke('sign-receipt', body: {'payment_id': paymentId});
      final data = response.data as Map<String, dynamic>;
      return SignedReceipt(payload: data['payload'] as String, signature: data['signature'] as String);
    } on FunctionException catch (e) {
      final details = e.details;
      final message = details is Map ? details['error'] as String? : null;
      if (e.status == 404 && message == null) {
        throw StateError('The sign-receipt function isn\'t deployed in Supabase yet.');
      }
      throw StateError(message ?? 'Could not sign the receipt.');
    }
  }

  /// The tenant confirms their receipt. Sending it twice is harmless.
  Future<void> confirm(String paymentId) async {
    await _client.rpc('confirm_receipt', params: {'p_payment_id': paymentId});
  }

  /// The tenant reports a problem; returns the ticket it opened.
  Future<String> reportProblem({
    required String paymentId,
    required ReceiptProblem problem,
    required String details,
  }) async {
    final id = await _client.rpc('dispute_receipt', params: {
      'p_payment_id': paymentId,
      'p_problem': problem.value,
      'p_details': details,
    });
    return id as String;
  }

  /// A scanned receipt's payment as THIS account sees it now (voided?
  /// answered?), or null if this account may not see it.
  Future<Payment?> lookUp(String paymentId) async {
    final row = await _client.from('payments').select(Payment.columns).eq('id', paymentId).maybeSingle();
    return row == null ? null : Payment.fromJson(row);
  }
}

final receiptsRepositoryProvider = Provider<ReceiptsRepository>((ref) {
  return ReceiptsRepository(ref.watch(supabaseClientProvider));
});
