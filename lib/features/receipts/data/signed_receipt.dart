import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:rental_app/shared/utils/dates.dart';

/// The PUBLIC keys that check receipt signatures, by key id. The matching
/// private key exists only as a secret of the sign-receipt Edge Function.
/// To change keys later: add 'k2' here (keep 'k1' so older receipts still
/// check out) and set RECEIPT_SIGNING_KEY / RECEIPT_SIGNING_KEY_ID=k2.
const receiptPublicKeys = {
  'k1': 'ZTIXUyUx_uk9d3AINpPKAiHtqYf7ODihYPl1CflP-Yc',
};

/// A receipt's signed details, as stored on the receipt by sign-receipt.
class SignedReceipt {
  const SignedReceipt({required this.payload, required this.signature});

  /// The receipt's details as JSON text, exactly as signed.
  final String payload;

  /// Ed25519 signature of [payload] (base64url).
  final String signature;

  /// What the QR code contains: `RAPP1.<signature>.<payload>`.
  String get qrText => '$qrPrefix$signature.$payload';

  static const qrPrefix = 'RAPP1.';
}

/// The details inside a signed receipt (short keys keep the QR code small).
class ReceiptFacts {
  const ReceiptFacts({
    required this.paymentId,
    required this.receiptNumber,
    required this.referenceCode,
    required this.isRent,
    required this.amount,
    required this.amountLeft,
    required this.currency,
    required this.paidOn,
    required this.propertyName,
    required this.apartmentName,
    required this.tenantName,
    required this.issuedAt,
    this.amountDue,
    this.periodStart,
    this.periodEnd,
    this.months,
  });

  final String paymentId;
  final String receiptNumber;
  final String referenceCode;
  final bool isRent;
  final int amount;
  final int? amountDue;
  final int amountLeft;
  final String currency;
  final DateTime paidOn;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final int? months;
  final String propertyName;
  final String apartmentName;
  final String tenantName;
  final DateTime issuedAt;

  factory ReceiptFacts.fromPayload(String payload) {
    final json = jsonDecode(payload) as Map<String, dynamic>;
    return ReceiptFacts(
      paymentId: json['id'] as String,
      receiptNumber: json['no'] as String,
      referenceCode: json['ref'] as String,
      isRent: json['kind'] == 'rent',
      amount: json['amt'] as int,
      amountDue: json['due'] as int?,
      amountLeft: json['left'] as int,
      currency: json['cur'] as String,
      paidOn: parseDbDate(json['paid'] as String),
      periodStart: parseDbDateOrNull(json['from'] as String?),
      periodEnd: parseDbDateOrNull(json['to'] as String?),
      months: json['mo'] as int?,
      propertyName: json['prop'] as String,
      apartmentName: json['unit'] as String,
      tenantName: json['ten'] as String,
      issuedAt: DateTime.parse(json['iss'] as String).toLocal(),
    );
  }
}

/// The result of checking a scanned code.
sealed class ReceiptCheck {
  const ReceiptCheck();
}

/// Not one of our receipt codes at all (some other QR code).
class NotAReceiptCode extends ReceiptCheck {
  const NotAReceiptCode();
}

/// Looks like a receipt code, but the signature doesn't match: the receipt
/// was made up or changed.
class FakeReceipt extends ReceiptCheck {
  const FakeReceipt();
}

/// Signed by the app's server: these details are exactly what was issued.
class GenuineReceipt extends ReceiptCheck {
  const GenuineReceipt(this.facts);

  final ReceiptFacts facts;
}

/// Checks a scanned QR code. Works offline: only the built-in public keys
/// are needed. (Whether the payment was voided later needs the internet.)
/// [publicKeys] is only replaced in tests.
Future<ReceiptCheck> checkReceiptCode(String text, {Map<String, String> publicKeys = receiptPublicKeys}) async {
  if (!text.startsWith(SignedReceipt.qrPrefix)) return const NotAReceiptCode();
  final rest = text.substring(SignedReceipt.qrPrefix.length);
  final dot = rest.indexOf('.');
  if (dot <= 0) return const FakeReceipt();
  final signature = rest.substring(0, dot);
  final payload = rest.substring(dot + 1);

  try {
    final keyId = (jsonDecode(payload) as Map<String, dynamic>)['k'] as String?;
    final publicKey = publicKeys[keyId];
    if (publicKey == null) return const FakeReceipt();

    final valid = await Ed25519().verify(
      utf8.encode(payload),
      signature: Signature(
        _fromBase64Url(signature),
        publicKey: SimplePublicKey(_fromBase64Url(publicKey), type: KeyPairType.ed25519),
      ),
    );
    if (!valid) return const FakeReceipt();
    return GenuineReceipt(ReceiptFacts.fromPayload(payload));
  } catch (_) {
    // Not JSON, wrong lengths, missing fields: not something we signed.
    return const FakeReceipt();
  }
}

List<int> _fromBase64Url(String text) => base64Url.decode(base64Url.normalize(text));
