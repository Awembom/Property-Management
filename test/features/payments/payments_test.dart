import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/payments/presentation/pages/receipt_page.dart';
import 'package:rental_app/features/payments/presentation/pages/record_payment_page.dart';
import 'package:rental_app/features/payments/presentation/receipt_pdf.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  const tenant = Tenant(id: 'x1', fullName: 'Tina Tenant');

  List overrides(
    MembershipRole role, {
    required bool withMoney,
    int balance = 0,
  }) => [
    myPropertyProvider.overrideWith((ref, id) async => fakeProperty(role)),
    tenancyDetailsProvider.overrideWith(
      (ref, ids) async => TenancyDetails(
        overview: fakeTenancy(), // pays every 3 months, paid until 1 Sep 2026
        tenant: tenant,
        money: withMoney
            ? TenancyMoney(monthlyRent: 50000, balance: balance)
            : null,
      ),
    ),
  ];

  Finder amountField() => find.widgetWithText(TextFormField, 'Amount paid');

  testWidgets('record payment fills in the period and the full amount', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RecordPaymentPage(propertyId: 'p1', tenancyId: 't1'),
      overrides: overrides(MembershipRole.owner, withMoney: true),
      screen: const Size(360, 2000),
    );
    // Starts with the tenant's usual 3 months: 1 Sep -> 1 Dec, 150,000.
    expect(find.text('1 Sep 2026 – 1 Dec 2026'), findsOneWidget);
    expect(
      find.descendant(of: amountField(), matching: find.text('150000')),
      findsOneWidget,
    );
    expect(find.text('Fully paid. Nothing left to pay.'), findsOneWidget);

    // 6 months: dates and amount follow.
    await tester.tap(find.widgetWithText(ChoiceChip, '6 months'));
    await tester.pumpAndSettle();
    expect(find.text('1 Sep 2026 – 1 Mar 2027'), findsOneWidget);
    expect(
      find.descendant(of: amountField(), matching: find.text('300000')),
      findsOneWidget,
    );

    // They paid less: the rest is shown as left to pay.
    await tester.enterText(amountField(), '250000');
    await tester.pumpAndSettle();
    expect(
      find.textContaining('XAF 50,000 will be left to pay'),
      findsOneWidget,
    );

    // Changing the months now keeps the typed amount.
    await tester.tap(find.widgetWithText(ChoiceChip, '3 months'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: amountField(), matching: find.text('250000')),
      findsOneWidget,
    );
    expect(find.textContaining('XAF 100,000 paid in advance'), findsOneWidget);
  });

  testWidgets('owing tenant can pay off the balance only', (tester) async {
    await pumpPage(
      tester,
      const RecordPaymentPage(propertyId: 'p1', tenancyId: 't1'),
      overrides: overrides(
        MembershipRole.manager,
        withMoney: true,
        balance: 30000,
      ),
      screen: const Size(360, 2000),
    );
    await tester.tap(find.text('Pay off balance'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: amountField(), matching: find.text('30000')),
      findsOneWidget,
    );
    expect(find.text('Fully paid. Nothing left to pay.'), findsOneWidget);
    expect(find.text('How long did they pay for?'), findsNothing);
  });

  testWidgets('caretaker records without seeing any amounts', (tester) async {
    await pumpPage(
      tester,
      const RecordPaymentPage(propertyId: 'p1', tenancyId: 't1'),
      overrides: overrides(MembershipRole.caretaker, withMoney: false),
      screen: const Size(360, 2000),
    );
    // No amounts like "XAF 50,000" (the bare "XAF" unit label is fine).
    expect(find.textContaining('XAF '), findsNothing);
    expect(
      find.text('Leave empty if they paid the full rent.'),
      findsOneWidget,
    );
    expect(find.text('1 Sep 2026 – 1 Dec 2026'), findsOneWidget);
  });

  ReceiptInfo receiptFor(Payment payment) => ReceiptInfo(
    property: fakeProperty(MembershipRole.owner).property,
    tenantName: 'Tina Tenant',
    apartmentName: 'A1',
    payment: payment,
    tenantHasAccount: true,
  );

  test('part-paid receipt has an "Amount left" line, marked red', () {
    final info = receiptFor(fakePartPayment());
    final lines = {for (final line in info.lines) line.label: line};
    expect(lines['Reference']!.value, 'PAY-7K3QX9');
    expect(lines['Months paid']!.value, '3 months');
    expect(lines['Rent paid until']!.value, '1 Sep 2026');
    expect(lines['Amount due']!.value, 'XAF 150,000');
    expect(lines['Amount paid']!.value, 'XAF 120,000');
    expect(lines['Amount left']!.value, 'XAF 30,000');
    expect(lines['Amount left']!.isAlert, isTrue);
    expect(lines['Amount paid']!.isAlert, isFalse);
    expect(lines['Payment method']!.value, 'Mobile money');
    expect(info.balanceText, 'Amount left: XAF 30,000');
  });

  test('completing receipt: same reference, no amount left', () {
    final info = receiptFor(fakeCompletingPayment());
    final labels = info.lines.map((line) => line.label);
    expect(labels, isNot(contains('Amount left')));
    expect(info.lines.first.value, 'PAY-7K3QX9');
    expect(info.balanceText, 'Fully paid');
  });

  test('receipt PDF: one page, or two with the earlier receipt', () async {
    int pageCount(List<int> bytes) =>
        RegExp(r'/Type\s*/Page[^s]')
            .allMatches(String.fromCharCodes(bytes))
            .length;

    final single = await buildReceiptPdf(receiptFor(fakePartPayment()));
    expect(String.fromCharCodes(single.take(5)), '%PDF-');
    expect(pageCount(single), 1);

    final both = await buildReceiptPdf(
      receiptFor(fakeCompletingPayment()),
      earlier: [receiptFor(fakePartPayment())],
    );
    expect(pageCount(both), 2);
  });

  testWidgets(
    'part-paid receipt page shows the amount left; manager can void',
    (tester) async {
      await pumpPage(
        tester,
        const ReceiptPage(propertyId: 'p1', paymentId: 'pay1'),
        overrides: [
          ...overrides(MembershipRole.manager, withMoney: true),
          paymentProvider.overrideWith((ref, id) async => fakePartPayment()),
          earlierReceiptsProvider.overrideWith((ref, id) async => []),
        ],
        screen: const Size(360, 1600),
      );
      expect(find.text('RCT-2026-0007'), findsOneWidget);
      expect(find.text('Amount left'), findsOneWidget);
      expect(find.text('Amount left: XAF 30,000'), findsOneWidget);
      expect(find.text('Share receipt (PDF)'), findsOneWidget);
      expect(find.text('Void this payment'), findsOneWidget);
    },
  );

  testWidgets('completing receipt links the earlier one and shares 2 pages', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const ReceiptPage(propertyId: 'p1', paymentId: 'pay2'),
      overrides: [
        ...overrides(MembershipRole.manager, withMoney: true),
        paymentProvider.overrideWith(
          (ref, id) async => fakeCompletingPayment(),
        ),
        earlierReceiptsProvider.overrideWith(
          (ref, id) async => [fakePartPayment()],
        ),
      ],
      screen: const Size(360, 1800),
    );
    expect(find.text('RCT-2026-0009'), findsOneWidget);
    expect(find.text('Fully paid'), findsOneWidget);
    expect(find.textContaining('Same reference PAY-7K3QX9'), findsOneWidget);
    expect(
      find.text('RCT-2026-0007'),
      findsOneWidget,
    ); // the linked earlier receipt
    expect(find.text('Share receipts (2-page PDF)'), findsOneWidget);
  });

  testWidgets('balance payment says which receipt it completes', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const RecordPaymentPage(propertyId: 'p1', tenancyId: 't1'),
      overrides: [
        ...overrides(MembershipRole.manager, withMoney: true, balance: 30000),
        tenancyPaymentsProvider.overrideWith(
          (ref, id) async => [fakePartPayment()],
        ),
      ],
      screen: const Size(360, 2000),
    );
    await tester.tap(find.text('Pay off balance'));
    await tester.pumpAndSettle();
    expect(find.text('Completes receipt RCT-2026-0007'), findsOneWidget);
    expect(find.textContaining('Same reference PAY-7K3QX9'), findsOneWidget);
  });

  test('payment kinds and methods read from the database', () {
    expect(PaymentKind.fromJson('balance'), PaymentKind.balance);
    expect(PaymentMethod.labelFor('bank'), 'Bank transfer');
    expect(PaymentMethod.labelFor(null), 'Not recorded');
  });
}
