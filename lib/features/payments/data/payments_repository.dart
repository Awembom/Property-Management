import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rental_app/core/offline/offline_cache.dart';
import 'package:rental_app/core/supabase/supabase_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// All Supabase calls for payments and receipts.
///
/// Recording and voiding go through database functions (record_payment,
/// void_payment) that also move "paid until" and number the receipt in the
/// same step. The app never updates or deletes payment rows (CLAUDE.md, rule 2).
class PaymentsRepository {
  PaymentsRepository(this._client, this._cache);

  final SupabaseClient _client;

  /// Keeps what was loaded, for offline use (see OfflineCache).
  final OfflineCache _cache;

  /// Payments of one tenancy, newest first (owners/managers and the tenant;
  /// the database returns nothing to caretakers).
  Future<List<Payment>> fetchTenancyPayments(String tenancyId) async {
    final rows = await _cache.rows(
      'payments/$tenancyId',
      () => _client
          .from('payments')
          .select(Payment.columns)
          .eq('tenancy_id', tenancyId)
          .order('created_at', ascending: false),
    );
    // Also save each payment on its own, so every receipt opens offline.
    for (final row in rows) {
      await _cache.put('payment/${row['id']}', row);
    }
    return rows.map(Payment.fromJson).toList();
  }

  /// The receipts that came BEFORE [payment] with the same reference code,
  /// oldest first. For a payment that completes a part payment, that's the
  /// part payment's receipt.
  /// (Picked from the tenancy's payments, so it works offline too.)
  Future<List<Payment>> fetchEarlierWithSameReference(Payment payment) async {
    final all = await fetchTenancyPayments(payment.tenancyId);
    return all
        .where((other) =>
            other.id != payment.id &&
            other.referenceCode == payment.referenceCode &&
            other.issuedAt.isBefore(payment.issuedAt))
        .toList()
      ..sort((a, b) => a.issuedAt.compareTo(b.issuedAt));
  }

  Future<Payment> fetchPayment(String paymentId) async {
    final row = await _cache.row(
      'payment/$paymentId',
      () => _client.from('payments').select(Payment.columns).eq('id', paymentId).maybeSingle(),
    );
    if (row == null) throw StateError('Payment not found');
    return Payment.fromJson(row);
  }

  /// Records rent for [months] months. [amount] null = the full rent for
  /// those months; a smaller amount leaves the rest owed (shown on the receipt).
  Future<RecordedPayment> recordRent({
    required String tenancyId,
    required int months,
    int? amount,
    required DateTime paidOn,
    String? method,
    String? reference,
  }) {
    return _record({
      'p_tenancy_id': tenancyId,
      'p_kind': 'rent',
      'p_months': months,
      'p_amount': amount,
      'p_paid_on': toDbDate(paidOn),
      'p_method': method,
      'p_reference': reference,
    });
  }

  /// Records money paid towards what is still owed (no new months).
  Future<RecordedPayment> recordBalance({
    required String tenancyId,
    required int amount,
    required DateTime paidOn,
    String? method,
    String? reference,
  }) {
    return _record({
      'p_tenancy_id': tenancyId,
      'p_kind': 'balance',
      'p_amount': amount,
      'p_paid_on': toDbDate(paidOn),
      'p_method': method,
      'p_reference': reference,
    });
  }

  Future<RecordedPayment> _record(Map<String, dynamic> params) async {
    // The function returns a table with one row.
    final rows = await _client.rpc('record_payment', params: params) as List;
    final row = rows.single as Map<String, dynamic>;
    return RecordedPayment(
      paymentId: row['payment_id'] as String,
      receiptNumber: row['receipt_number'] as String,
      paidUntil: parseDbDate(row['paid_until'] as String),
    );
  }

  /// Cancels a payment with a reason (owners/managers). The payment stays in
  /// the history, marked void, and "paid until" is recalculated.
  Future<void> voidPayment(String paymentId, String reason) async {
    await _client.rpc('void_payment', params: {
      'p_payment_id': paymentId,
      'p_reason': reason,
    });
  }
}

final paymentsRepositoryProvider = Provider<PaymentsRepository>((ref) {
  return PaymentsRepository(ref.watch(supabaseClientProvider), ref.watch(offlineCacheProvider));
});
