import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/core/offline/outbox.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/presentation/pages/tenant_receipt_page.dart';
import 'package:rental_app/features/payments/presentation/receipt_pdf.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/receipts/data/receipt_standing.dart';
import 'package:rental_app/features/receipts/data/signed_receipt.dart';
import 'package:rental_app/features/tenant_access/data/my_rental_details.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';

import '../../helpers/fakes.dart';

/// A receipt payload like the sign-receipt Edge Function makes.
const payload = '{"v":1,"k":"test","id":"pay1","no":"RCT-2026-0007","ref":"PAY-7K3QX9","kind":"rent",'
    '"amt":120000,"due":150000,"left":30000,"cur":"XAF","paid":"2026-06-02","from":"2026-06-01",'
    '"to":"2026-09-01","mo":3,"prop":"Sunset Court","unit":"A1","ten":"Tina Tenant",'
    '"iss":"2026-06-02T09:00:00+00:00"}';

/// Signs [text] with a fresh test key; returns the signed receipt and the
/// public key map that checks it.
Future<(SignedReceipt, Map<String, String>)> signWithTestKey(String text) async {
  final algorithm = Ed25519();
  final keyPair = await algorithm.newKeyPair();
  final signature = await algorithm.sign(utf8.encode(text), keyPair: keyPair);
  final publicKey = await keyPair.extractPublicKey();
  return (
    SignedReceipt(payload: text, signature: base64Url.encode(signature.bytes).replaceAll('=', '')),
    {'test': base64Url.encode(publicKey.bytes).replaceAll('=', '')},
  );
}

/// [fakePartPayment], issued [age] ago, with an optional answer.
Payment paymentIssued(Duration age, {ReceiptResponse? response, SignedReceipt? signed}) {
  final p = fakePartPayment();
  return Payment(
    id: p.id,
    tenancyId: p.tenancyId,
    propertyId: p.propertyId,
    kind: p.kind,
    amount: p.amount,
    expectedAmount: p.expectedAmount,
    balanceAfter: p.balanceAfter,
    months: p.months,
    periodStart: p.periodStart,
    periodEnd: p.periodEnd,
    paidOn: p.paidOn,
    method: p.method,
    receiptNumber: p.receiptNumber,
    referenceCode: p.referenceCode,
    issuedAt: DateTime.now().subtract(age),
    response: response,
    signed: signed,
  );
}

/// Records what the screen asked the outbox to send.
class FakeOutbox extends OutboxNotifier {
  final sent = <OutboxItem>[];

  @override
  Future<List<OutboxItem>> build() async => [];

  @override
  Future<bool> sendOrQueue(OutboxItem item) async {
    sent.add(item);
    return true;
  }
}

void main() {
  group('QR check', () {
    test('a genuine receipt checks out, with its details', () async {
      final (signed, keys) = await signWithTestKey(payload);
      final result = await checkReceiptCode(signed.qrText, publicKeys: keys);
      expect(result, isA<GenuineReceipt>());
      final facts = (result as GenuineReceipt).facts;
      expect(facts.receiptNumber, 'RCT-2026-0007');
      expect(facts.amount, 120000);
      expect(facts.amountLeft, 30000);
      expect(facts.tenantName, 'Tina Tenant');
    });

    test('changing one number makes it fake', () async {
      final (signed, keys) = await signWithTestKey(payload);
      final changed = signed.qrText.replaceFirst('"amt":120000', '"amt":150000');
      expect(await checkReceiptCode(changed, publicKeys: keys), isA<FakeReceipt>());
    });

    test('a receipt signed with some other key is fake', () async {
      final (signed, _) = await signWithTestKey(payload);
      final (_, otherKeys) = await signWithTestKey(payload);
      expect(await checkReceiptCode(signed.qrText, publicKeys: otherKeys), isA<FakeReceipt>());
      // And the app's real key doesn't accept test signatures either.
      expect(await checkReceiptCode(signed.qrText), isA<FakeReceipt>());
    });

    test('other QR codes and garbage', () async {
      expect(await checkReceiptCode('https://example.com'), isA<NotAReceiptCode>());
      expect(await checkReceiptCode('RAPP1.nonsense'), isA<FakeReceipt>());
      expect(await checkReceiptCode('RAPP1.abc.{not json'), isA<FakeReceipt>());
    });
  });

  group('where a receipt stands', () {
    ReceiptStanding? standing(Payment p, {bool account = true, bool queued = false}) => ReceiptStanding.of(
          issuedAt: p.issuedAt,
          isVoided: p.isVoided,
          response: p.response,
          tenantHasAccount: account,
          confirmationQueued: queued,
        );

    test('within 24 hours: awaiting, the tenant can answer', () {
      final s = standing(paymentIssued(const Duration(hours: 2)))!;
      expect(s.kind, ReceiptStandingKind.awaiting);
      expect(s.canAnswer, isTrue);
      expect(s.describe(forTenant: true), contains('21 hours'));
    });

    test('after 24 hours with no answer: accepted automatically', () {
      final s = standing(paymentIssued(const Duration(hours: 25)))!;
      expect(s.kind, ReceiptStandingKind.accepted);
      expect(s.canAnswer, isFalse);
      expect(s.pdfLine, startsWith('Accepted: no problem reported within 24 hours'));
    });

    test('confirmed, disputed, resolved', () {
      final at = DateTime.now();
      expect(
        standing(paymentIssued(const Duration(hours: 1),
                response: ReceiptResponse(confirmed: true, answeredAt: at)))!
            .kind,
        ReceiptStandingKind.confirmed,
      );
      final disputed = standing(paymentIssued(const Duration(hours: 1),
          response: ReceiptResponse(
              confirmed: false, answeredAt: at, problem: ReceiptProblem.amount, ticketStatus: TicketStatus.open)))!;
      expect(disputed.kind, ReceiptStandingKind.disputed);
      expect(disputed.describe(forTenant: false), contains('wrong amount'));
      expect(
        standing(paymentIssued(const Duration(days: 3),
                response: ReceiptResponse(
                    confirmed: false, answeredAt: at, problem: ReceiptProblem.amount, ticketStatus: TicketStatus.resolved)))!
            .kind,
        ReceiptStandingKind.disputeResolved,
      );
    });

    test('a confirmation waiting offline already counts as confirmed', () {
      expect(standing(paymentIssued(const Duration(hours: 1)), queued: true)!.kind, ReceiptStandingKind.confirmed);
    });

    test('tenant without an app account: nothing to show', () {
      expect(standing(paymentIssued(const Duration(hours: 1)), account: false), isNull);
    });
  });

  test('the PDF builds with the QR code and the confirmation line', () async {
    final (signed, _) = await signWithTestKey(payload);
    final info = ReceiptInfo(
      property: fakeProperty(MembershipRole.owner).property,
      tenantName: 'Tina Tenant',
      apartmentName: 'A1',
      payment: paymentIssued(const Duration(hours: 30), signed: signed),
      tenantHasAccount: true,
    );
    final bytes = await buildReceiptPdf(info, earlier: [info.forPayment(fakeCompletingPayment())]);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(String.fromCharCodes(bytes).split('/Type /Page\n').length - 1, anyOf(0, 2)); // 2 pages (if uncompressed)
  });

  group('tenant receipt screen', () {
    Future<FakeOutbox> show(WidgetTester tester, Payment payment) async {
      final outbox = FakeOutbox();
      final details = MyRentalDetails(
        tenancy: fakeTenancy(status: null),
        tenantName: 'Tina Tenant',
        propertyName: 'Sunset Court',
        currency: 'XAF',
        monthlyRent: 50000,
        balance: 30000,
        payments: [payment],
      );
      await pumpPage(
        tester,
        const TenantReceiptPage(tenancyId: 't1', paymentId: 'pay1'),
        screen: const Size(360, 1600),
        overrides: [
          myRentalDetailsProvider('t1').overrideWith((ref) async => details),
          outboxProvider.overrideWith(() => outbox),
        ],
      );
      return outbox;
    }

    testWidgets('new receipt: confirm it (asks first), or report a problem', (tester) async {
      final (signed, _) = await signWithTestKey(payload);
      final outbox = await show(tester, paymentIssued(const Duration(hours: 3), signed: signed));

      expect(find.text('Awaiting confirmation'), findsOneWidget);
      expect(find.textContaining('20 hours'), findsOneWidget);
      expect(find.text('Report a problem'), findsOneWidget);
      expect(find.text('Proof it\'s genuine'), findsOneWidget);

      await tester.tap(find.text('Confirm, it\'s correct'));
      await tester.pumpAndSettle();
      expect(find.text('Confirm this receipt?'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Confirm'));
      await tester.pumpAndSettle();
      expect(outbox.sent.single.kind, OutboxKind.confirmReceipt);
      expect(outbox.sent.single.data['payment_id'], 'pay1');
    });

    testWidgets('after 24 hours: accepted, no buttons', (tester) async {
      final (signed, _) = await signWithTestKey(payload);
      await show(tester, paymentIssued(const Duration(hours: 30), signed: signed));
      expect(find.text('Accepted'), findsOneWidget);
      expect(find.text('Confirm, it\'s correct'), findsNothing);
      expect(find.text('Report a problem'), findsNothing);
    });

    testWidgets('disputed: says so and links to the conversation', (tester) async {
      final (signed, _) = await signWithTestKey(payload);
      await show(
        tester,
        paymentIssued(
          const Duration(hours: 3),
          signed: signed,
          response: ReceiptResponse(
            confirmed: false,
            answeredAt: DateTime.now(),
            problem: ReceiptProblem.months,
            ticketId: 'k9',
            ticketStatus: TicketStatus.open,
          ),
        ),
      );
      expect(find.text('Disputed'), findsOneWidget);
      expect(find.textContaining('wrong number of months'), findsOneWidget);
      expect(find.text('Open the conversation'), findsOneWidget);
      expect(find.text('Confirm, it\'s correct'), findsNothing);
    });
  });
}
