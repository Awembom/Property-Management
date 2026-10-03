import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/data/signed_receipt.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';

/// One line of a receipt, e.g. "Amount paid: XAF 120,000".
/// [isAlert] lines are shown in red (money still owed).
class ReceiptLine {
  const ReceiptLine(this.label, this.value, {this.isAlert = false});

  final String label;
  final String value;
  final bool isAlert;
}

/// Everything printed on a receipt.
class ReceiptInfo {
  const ReceiptInfo({
    required this.property,
    required this.tenantName,
    required this.apartmentName,
    required this.payment,
    required this.tenantHasAccount,
  });

  final Property property;
  final String tenantName;
  final String apartmentName;
  final Payment payment;

  /// Only tenants with an app account can confirm receipts; without one the
  /// receipt shows no confirmation status.
  final bool tenantHasAccount;

  /// Where the receipt stands with the tenant (null = nothing to show).
  ReceiptStanding? standing({bool confirmationQueued = false, DateTime? now}) => ReceiptStanding.of(
        issuedAt: payment.issuedAt,
        isVoided: payment.isVoided,
        response: payment.response,
        tenantHasAccount: tenantHasAccount,
        confirmationQueued: confirmationQueued,
        now: now,
      );

  /// The same receipt for an earlier payment (same property and tenant).
  ReceiptInfo forPayment(Payment other) => ReceiptInfo(
        property: property,
        tenantName: tenantName,
        apartmentName: apartmentName,
        payment: other,
        tenantHasAccount: tenantHasAccount,
      );

  /// A copy whose payment carries its signature (signed after loading).
  ReceiptInfo withSigned(SignedReceipt signed) => ReceiptInfo(
        property: property,
        tenantName: tenantName,
        apartmentName: apartmentName,
        payment: payment.withSigned(signed),
        tenantHasAccount: tenantHasAccount,
      );

  /// The receipt's lines, shared by the PDF and the on-screen receipt so both
  /// always show the same thing.
  List<ReceiptLine> get lines {
    final p = payment;
    final currency = property.currency;
    return [
      ReceiptLine('Reference', p.referenceCode),
      ReceiptLine('Tenant', tenantName),
      ReceiptLine('Apartment', apartmentName),
      ReceiptLine('Paid on', formatDate(p.paidOn)),
      if (p.kind == PaymentKind.rent) ...[
        ReceiptLine('Period', '${formatDate(p.periodStart!)} - ${formatDate(p.periodEnd!)}'),
        ReceiptLine('Months paid', PaymentInterval.monthsText(p.months!)),
        ReceiptLine('Rent paid until', formatDate(p.periodEnd!)),
        ReceiptLine('Amount due', formatMoney(p.expectedAmount!, currency)),
      ] else
        const ReceiptLine('For', 'Rest of the rent owed'),
      ReceiptLine('Amount paid', formatMoney(p.amount, currency)),
      // Not everything paid yet: say how much is left, in red.
      if (p.balanceAfter > 0)
        ReceiptLine('Amount left', formatMoney(p.balanceAfter, currency), isAlert: true),
      ReceiptLine('Payment method', PaymentMethod.labelFor(p.method)),
      if (p.reference != null) ReceiptLine('Transaction ID', p.reference!),
    ];
  }

  /// "Amount left: XAF 30,000", "Fully paid" or "Paid in advance: ...".
  String get balanceText {
    final balance = payment.balanceAfter;
    final currency = property.currency;
    if (balance > 0) return 'Amount left: ${formatMoney(balance, currency)}';
    if (balance < 0) return 'Paid in advance: ${formatMoney(-balance, currency)}';
    return 'Fully paid';
  }
}

/// Builds the receipt as a PDF (A5) to share or print.
///
/// Page 1 is [info]'s receipt. If [earlier] receipts are given (receipts with
/// the same reference code, e.g. the part payment this payment completes),
/// each one follows on its own page.
///
/// Each page has the receipt's QR code (if it's signed): the app's "Check a
/// receipt" scanner proves it's genuine, and a changed PDF fails the check.
///
/// Uses the PDF's built-in Helvetica font, which only has basic Latin
/// letters, so the text sticks to plain characters (e.g. "-" not an arrow).
Future<Uint8List> buildReceiptPdf(ReceiptInfo info, {List<ReceiptInfo> earlier = const []}) async {
  final all = [info, ...earlier];
  final doc = pw.Document(title: 'Receipt ${info.payment.receiptNumber}');
  for (var i = 0; i < all.length; i++) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => _receiptPage(
          all[i],
          note: i == 0
              ? null
              : 'Earlier receipt with the same reference (${info.payment.referenceCode})',
          footer: all.length == 1 ? null : 'Page ${i + 1} of ${all.length}',
        ),
      ),
    );
  }
  return doc.save();
}

const _violet = PdfColor.fromInt(0xFF6D4AFF);
const _red = PdfColor.fromInt(0xFFE11D48);
const _green = PdfColor.fromInt(0xFF16A34A);

pw.Widget _receiptPage(ReceiptInfo info, {String? note, String? footer}) {
  final payment = info.payment;
  final balance = payment.balanceAfter;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      if (note != null)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Text(note, style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 9)),
        ),
      // Coloured header with the property and receipt number.
      pw.Container(
        padding: const pw.EdgeInsets.all(16),
        decoration: const pw.BoxDecoration(
          color: _violet,
          borderRadius: pw.BorderRadius.all(pw.Radius.circular(12)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              info.property.name,
              style: pw.TextStyle(color: PdfColors.white, fontSize: 18, fontWeight: pw.FontWeight.bold),
            ),
            if (info.property.address != null)
              pw.Text(info.property.address!,
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
            pw.SizedBox(height: 10),
            pw.Text(
              'RENT RECEIPT  ${payment.receiptNumber}',
              style: pw.TextStyle(color: PdfColors.white, fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.Text('Issued ${formatDate(payment.issuedAt)}',
                style: const pw.TextStyle(color: PdfColors.white, fontSize: 10)),
          ],
        ),
      ),
      if (payment.isVoided) ...[
        pw.SizedBox(height: 10),
        pw.Container(
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(color: _red, width: 2)),
          child: pw.Text(
            'VOID - ${payment.voidReason}',
            style: pw.TextStyle(color: _red, fontWeight: pw.FontWeight.bold),
          ),
        ),
      ],
      pw.SizedBox(height: 16),
      for (final line in info.lines)
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(vertical: 4),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  line.label,
                  style: pw.TextStyle(
                    color: line.isAlert ? _red : PdfColors.grey700,
                    fontWeight: line.isAlert ? pw.FontWeight.bold : null,
                  ),
                ),
              ),
              pw.Text(
                line.value,
                style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold,
                  color: line.isAlert ? _red : null,
                ),
              ),
            ],
          ),
        ),
      pw.Divider(),
      pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          // Solid light tints: PDF viewers don't reliably show see-through colours.
          color: balance > 0 ? const PdfColor.fromInt(0xFFFDE8EC) : const PdfColor.fromInt(0xFFE6F6EC),
          borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        ),
        child: pw.Text(
          info.balanceText,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(
            fontSize: 14,
            fontWeight: pw.FontWeight.bold,
            color: balance > 0 ? _red : _green,
          ),
        ),
      ),
      if (info.standing()?.pdfLine case final line?) ...[
        pw.SizedBox(height: 8),
        pw.Text(line, textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: 9)),
      ],
      pw.Spacer(),
      if (payment.signed case final signed?)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            children: [
              pw.BarcodeWidget(
                barcode: pw.Barcode.qrCode(),
                data: signed.qrText,
                width: 74,
                height: 74,
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Text(
                  'Proof this receipt is genuine: scan this code with the Homedly app '
                  '(Profile > Check a receipt). Any change to this receipt makes the check fail.',
                  style: const pw.TextStyle(color: PdfColors.grey700, fontSize: 8),
                ),
              ),
            ],
          ),
        ),
      pw.Text(
        'Thank you. Keep this receipt as proof of payment.',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
      ),
      if (footer != null)
        pw.Text(
          footer,
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(color: PdfColors.grey600, fontSize: 9),
        ),
    ],
  );
}
