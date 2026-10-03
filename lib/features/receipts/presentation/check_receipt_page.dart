import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/data/receipts_repository.dart';
import 'package:rental_app/features/receipts/data/signed_receipt.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/status_pill.dart';

/// "Check a receipt": scan the QR code on a receipt (on paper, a PDF or
/// another phone) to see whether it's genuine.
///
/// The signature check works offline. Online, it also shows what the app
/// knows about the payment now (voided? confirmed?), if this account may
/// see that payment.
class CheckReceiptPage extends StatefulWidget {
  const CheckReceiptPage({super.key});

  @override
  State<CheckReceiptPage> createState() => _CheckReceiptPageState();
}

class _CheckReceiptPageState extends State<CheckReceiptPage> {
  ReceiptCheck? _result;
  bool _checking = false;

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_checking || _result != null) return;
    final value = capture.barcodes.map((b) => b.rawValue).nonNulls.firstOrNull;
    if (value == null) return;
    setState(() => _checking = true);
    final result = await checkReceiptCode(value);
    if (mounted) {
      setState(() {
        _checking = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('Check a receipt')),
      body: result == null
          ? _Scanner(onDetect: _onDetect, checking: _checking)
          : _ResultView(result: result, onScanAgain: () => setState(() => _result = null)),
    );
  }
}

class _Scanner extends StatelessWidget {
  const _Scanner({required this.onDetect, required this.checking});

  final void Function(BarcodeCapture) onDetect;
  final bool checking;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  MobileScanner(
                    onDetect: onDetect,
                    errorBuilder: (context, error) => ColoredBox(
                      color: Colors.black87,
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            error.errorCode == MobileScannerErrorCode.permissionDenied
                                ? 'The app needs the camera to scan receipts. Allow it in the phone\'s settings.'
                                : 'The camera could not start.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // A frame to aim with.
                  Center(
                    child: Container(
                      width: 230,
                      height: 230,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 3),
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                  ),
                  if (checking) const Center(child: CircularProgressIndicator()),
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
          child: Text(
            'Point the camera at the QR code at the bottom of the receipt.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }
}

class _ResultView extends ConsumerWidget {
  const _ResultView({required this.result, required this.onScanAgain});

  final ReceiptCheck result;
  final VoidCallback onScanAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final (Color color, IconData icon, String title, String message) = switch (result) {
      GenuineReceipt() => (
          AppColors.paid,
          Icons.verified_rounded,
          'Genuine receipt',
          'This receipt was issued through the app, and these are its exact details. '
              'Compare them with the paper or PDF: if anything differs, it was changed.',
        ),
      FakeReceipt() => (
          AppColors.overdue,
          Icons.gpp_bad_rounded,
          'Not genuine',
          'This code was not issued by the app, or the receipt was changed. Don\'t accept it.',
        ),
      NotAReceiptCode() => (
          AppColors.muted,
          Icons.qr_code_2_rounded,
          'Not a receipt code',
          'This QR code isn\'t from a Rental App receipt.',
        ),
    };

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        AppCard(
          child: Column(
            children: [
              Icon(icon, color: color, size: 64),
              const SizedBox(height: 8),
              Text(title, style: text.headlineSmall?.copyWith(color: color, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text(message, textAlign: TextAlign.center, style: text.bodyMedium),
            ],
          ),
        ),
        if (result case GenuineReceipt(:final facts)) ...[
          const SizedBox(height: 14),
          _FactsCard(facts: facts),
          const SizedBox(height: 14),
          _LiveStatus(facts: facts),
        ],
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: onScanAgain,
          icon: const Icon(Icons.qr_code_scanner_rounded),
          label: const Text('Scan another'),
        ),
      ],
    );
  }
}

/// The signed details, as issued.
class _FactsCard extends StatelessWidget {
  const _FactsCard({required this.facts});

  final ReceiptFacts facts;

  @override
  Widget build(BuildContext context) {
    final f = facts;
    final lines = [
      ('Receipt', f.receiptNumber),
      ('Reference', f.referenceCode),
      ('Property', f.propertyName),
      ('Apartment', f.apartmentName),
      ('Tenant', f.tenantName),
      ('Paid on', formatDate(f.paidOn)),
      if (f.isRent && f.periodStart != null && f.periodEnd != null)
        ('Period', '${formatDate(f.periodStart!)} - ${formatDate(f.periodEnd!)}'),
      if (f.months != null) ('Months paid', PaymentInterval.monthsText(f.months!)),
      if (f.amountDue != null) ('Amount due', formatMoney(f.amountDue!, f.currency)),
      ('Amount paid', formatMoney(f.amount, f.currency)),
      if (f.amountLeft > 0) ('Amount left', formatMoney(f.amountLeft, f.currency)),
      ('Issued', formatDate(f.issuedAt)),
    ];
    final text = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        children: [
          for (final (label, value) in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: Text(label, style: text.bodyMedium)),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: label == 'Amount left' ? AppColors.overdue : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// What the app knows about the payment right now (needs a connection and
/// permission to see the payment).
final _liveLookupProvider = FutureProvider.autoDispose.family<Payment?, String>((ref, paymentId) {
  return ref.watch(receiptsRepositoryProvider).lookUp(paymentId);
});

class _LiveStatus extends ConsumerWidget {
  const _LiveStatus({required this.facts});

  final ReceiptFacts facts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final lookup = ref.watch(_liveLookupProvider(facts.paymentId));
    final (String title, String detail, ReceiptStanding? standing) = lookup.when(
      loading: () => ('Checking its status…', '', null),
      error: (error, _) => isNetworkError(error)
          ? ('Status not checked', 'You\'re offline. The receipt is genuine, but whether it was voided '
                'later can only be checked online.', null)
          : ('Status not checked', 'Something went wrong while checking.', null),
      data: (payment) {
        if (payment == null) {
          return (
            'Status not available',
            'This account can\'t see this payment, so only the landlord can tell whether it was '
                'voided later.',
            null,
          );
        }
        final standing = ReceiptStanding.of(
          issuedAt: payment.issuedAt,
          isVoided: payment.isVoided,
          response: payment.response,
          tenantHasAccount: payment.response != null,
        );
        if (payment.isVoided) {
          return ('This payment was VOIDED', 'Reason: ${payment.voidReason}. The receipt is no longer valid.', standing);
        }
        return ('Still valid', 'The payment has not been voided.', standing);
      },
    );
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: text.titleSmall)),
              if (standing != null)
                StatusPill(label: standing.label, color: standing.color, icon: standing.icon),
            ],
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(detail, style: text.bodySmall),
          ],
        ],
      ),
    );
  }
}
