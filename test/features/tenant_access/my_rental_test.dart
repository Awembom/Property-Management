import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/admin/providers/admin_providers.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/dashboard/presentation/pages/home_page.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/presentation/pages/properties_page.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenant_access/data/my_rental.dart';
import 'package:rental_app/features/tenant_access/data/my_rental_details.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/my_rental_page.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/tenant_tabs.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:rental_app/features/tenant_access/data/agreement_text.dart';
import 'package:rental_app/shared/utils/dates.dart';

import '../../helpers/fakes.dart';

/// Active tenancy, paid until 1 Sep 2026, every 3 months; agreement as given.
TenancyOverview tenancyWith({DateTime? acceptedAt}) {
  final t = fakeTenancy(status: null);
  return TenancyOverview(
    id: t.id,
    propertyId: t.propertyId,
    apartmentId: t.apartmentId,
    apartmentName: t.apartmentName,
    tenantId: t.tenantId,
    tenantName: t.tenantName,
    paymentIntervalMonths: 3,
    startDate: t.startDate,
    billingStartDate: t.billingStartDate,
    paidUntil: addMonths(today(), 1), // due in one month
    paidMonths: t.paidMonths,
    isActive: true,
    endDate: addMonths(today(), 6),
    agreementAcceptedAt: acceptedAt,
  );
}

MyRentalDetails detailsWith({DateTime? acceptedAt, int balance = 0}) =>
    MyRentalDetails(
      tenancy: tenancyWith(acceptedAt: acceptedAt),
      tenantName: 'Tina Tenant',
      propertyName: 'Sunset Court',
      currency: 'XAF',
      monthlyRent: 50000,
      balance: balance,
      payments: [fakePartPayment()],
    );

void main() {
  test('time left in words', () {
    expect(timeLeftText(today()), 'today');
    expect(timeLeftText(today().add(const Duration(days: 1))), '1 day');
    expect(timeLeftText(addMonths(today(), 2)), '2 months');
    expect(
      timeLeftText(addMonths(today(), 1).add(const Duration(days: 3))),
      anyOf('1 month 3 days', '1 month 2 days', '1 month 4 days'),
    );
  });

  testWidgets('tenant home: their rental, no landlord things', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [
        profileOf(AccountType.tenant),
        isAppAdminProvider.overrideWith((ref) async => false),
        myPropertiesProvider.overrideWith((ref) async => []),
        myRentalsProvider.overrideWith(
          (ref) async => [
            MyRental(tenancy: tenancyWith(), propertyName: 'Sunset Court'),
          ],
        ),
      ],
      screen: const Size(360, 1000),
    );
    expect(find.text('Add property'), findsNothing);
    expect(find.byTooltip('Add property'), findsNothing);
    expect(find.text('Apartment A1'), findsOneWidget);
    expect(
      find.text('Tap to read and accept your tenancy agreement'),
      findsOneWidget,
    );
    expect(find.text('To accept'), findsOneWidget);
  });

  testWidgets('landlord properties tab still has "Add property"', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const PropertiesPage(),
      overrides: [
        profileOf(AccountType.landlord),
        myPropertiesProvider.overrideWith((ref) async => []),
      ],
    );
    expect(find.text('Add property'), findsOneWidget);
  });

  testWidgets('first the agreement: accept only after ticking the box', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const MyRentalPage(tenancyId: 't1'),
      overrides: [
        myRentalDetailsProvider.overrideWith((ref, id) async => detailsWith()),
      ],
      screen: const Size(360, 2000),
    );
    expect(find.text('Your tenancy agreement'), findsOneWidget);
    expect(
      find.textContaining('Rent: XAF 50,000 per month'),
      findsOneWidget,
    ); // real summary
    expect(
      find.textContaining('The tenant keeps the home clean'),
      findsWidgets,
    ); // placeholder clauses

    final accept = find.widgetWithText(FilledButton, 'Accept agreement');
    expect(tester.widget<FilledButton>(accept).onPressed, isNull);
    await tester.tap(find.text('I have read and accept the tenancy agreement'));
    await tester.pump();
    expect(tester.widget<FilledButton>(accept).onPressed, isNotNull);
  });

  testWidgets(
    'after accepting: time left, due date, rent, amount left, payments',
    (tester) async {
      await pumpPage(
        tester,
        const MyRentalPage(tenancyId: 't1'),
        overrides: [
          myRentalDetailsProvider.overrideWith(
            (ref, id) async =>
                detailsWith(acceptedAt: DateTime(2026, 10, 1), balance: 30000),
          ),
          myBillsProvider.overrideWith(
            (ref, id) async => [
              MyBill(
                assignmentId: 'b1',
                title: 'Water - October',
                amount: 4500,
                dueDate: today().add(const Duration(days: 5)),
              ),
            ],
          ),
          tenancyTicketsProvider.overrideWith((ref, id) async => []),
        ],
        screen: const Size(360, 3000),
      );
      expect(find.text('1 month'), findsOneWidget); // header: time left
      expect(find.text('until rent is due'), findsOneWidget);
      expect(find.text('Amount left to pay: XAF 30,000'), findsOneWidget);
      expect(
        find.text('Every 3 months · XAF 150,000 each time'),
        findsOneWidget,
      );
      expect(find.textContaining('6 months left'), findsOneWidget); // lease
      expect(find.text('Accepted on 1 Oct 2026'), findsOneWidget);
      expect(find.text('Report an issue'), findsOneWidget);
      // Bills, payments and issues live in their own tabs now.
      expect(find.text('Water - October'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Bills'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Payments'), findsOneWidget);
      expect(find.widgetWithText(TextButton, 'Issues'), findsOneWidget);
    },
  );

  testWidgets('the landlord\'s number is on the home page, ready to call', (tester) async {
    final d = detailsWith(acceptedAt: DateTime(2026, 10, 1));
    await pumpPage(tester, const MyRentalPage(tenancyId: 't1'), overrides: [
      myRentalDetailsProvider.overrideWith((ref, id) async => MyRentalDetails(
            tenancy: d.tenancy,
            tenantName: d.tenantName,
            propertyName: d.propertyName,
            currency: d.currency,
            monthlyRent: d.monthlyRent,
            balance: 0,
            payments: const [],
            contactPhone: '+237 677 000 111',
          )),
    ]);
    expect(find.text('Call your landlord'), findsOneWidget);
    expect(find.text('+237 677 000 111'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Call'), findsOneWidget);
  });

  test('owner\'s agreement: fields filled in, "# " lines become headings', () {
    final sections = agreementSections(
      propertyName: 'Sunset Court',
      apartmentName: 'A1',
      tenantName: 'Tina Tenant',
      monthlyRent: 50000,
      currency: 'XAF',
      paymentIntervalMonths: 3,
      startDate: DateTime(2026, 1, 1),
      template: 'Welcome {tenant}.\n# Pets\nNo pets in {unit}.\n# Rent\n{rent}, paid {pays}, until {end}.',
    );
    expect(sections.first.$1, 'Summary');
    expect(sections[1], ('', 'Welcome Tina Tenant.'));
    expect(sections[2], ('Pets', 'No pets in A1.'));
    expect(sections[3], ('Rent', 'XAF 50,000, paid every 3 months, until no fixed end date.'));
  });

  group('tenant tabs', () {
    final rentalOverride = myRentalsProvider.overrideWith(
      (ref) async => [MyRental(tenancy: tenancyWith(acceptedAt: DateTime(2026, 10, 1)), propertyName: 'Sunset Court')],
    );

    testWidgets('Bills: what is left to pay, then each bill', (tester) async {
      await pumpPage(tester, const MyBillsTab(), overrides: [
        rentalOverride,
        myBillsProvider.overrideWith((ref, id) async => [
              MyBill(assignmentId: 'b1', title: 'Water - October', amount: 4500, dueDate: today().add(const Duration(days: 5))),
            ]),
      ]);
      expect(find.text('My bills'), findsOneWidget);
      expect(find.text('To pay'), findsOneWidget);
      expect(find.text('XAF 4,500'), findsOneWidget);
      expect(find.text('Bills paid so far'), findsOneWidget);
      expect(find.text('Water - October'), findsOneWidget);
    });

    testWidgets('Payments: amount left and each payment', (tester) async {
      await pumpPage(tester, const MyPaymentsTab(), overrides: [
        rentalOverride,
        myRentalDetailsProvider.overrideWith(
          (ref, id) async => detailsWith(acceptedAt: DateTime(2026, 10, 1), balance: 30000),
        ),
      ]);
      expect(find.text('Amount left to pay: XAF 30,000'), findsOneWidget);
      expect(find.text('Total rent paid'), findsOneWidget);
      expect(find.text('XAF 120,000'), findsWidgets);
      expect(find.text('RCT-2026-0007 · 2 Jun 2026\nRent until 1 Sep 2026'), findsOneWidget);
    });

    testWidgets('Issues: list and a button to report one', (tester) async {
      await pumpPage(tester, const MyIssuesTab(), overrides: [
        rentalOverride,
        tenancyTicketsProvider.overrideWith((ref, id) async => []),
      ]);
      expect(find.text('No issues reported'), findsOneWidget);
      expect(find.text('Report an issue'), findsOneWidget);
    });
  });

  testWidgets(
    'tenant Home shows bills first: total to pay, overdue, each bill',
    (tester) async {
      HomeBill homeBill(
        String title,
        int amount,
        int dueInDays, {
        bool paid = false,
      }) => HomeBill(
        bill: MyBill(
          assignmentId: title,
          title: title,
          amount: amount,
          dueDate: today().add(Duration(days: dueInDays)),
          paidAt: paid ? DateTime(2026, 10, 1) : null,
        ),
        tenancyId: 't1',
        apartmentName: 'A1',
        currency: 'XAF',
      );
      await pumpPage(
        tester,
        const HomePage(),
        overrides: [
          profileOf(AccountType.tenant),
          isAppAdminProvider.overrideWith((ref) async => false),
          myPropertiesProvider.overrideWith((ref) async => []),
          myRentalsProvider.overrideWith(
            (ref) async => [
              MyRental(
                tenancy: tenancyWith(acceptedAt: DateTime(2026, 10, 1)),
                propertyName: 'Sunset Court',
              ),
            ],
          ),
          myHomeBillsProvider.overrideWith(
            (ref) async => [
              homeBill('Water - September', 4000, -3), // overdue
              homeBill('Electricity - October', 7500, 10),
              homeBill('Water - August', 4000, -40, paid: true),
            ],
          ),
        ],
        screen: const Size(360, 1400),
      );
      expect(find.text('My bills'), findsOneWidget);
      expect(find.text('To pay: XAF 11,500'), findsOneWidget);
      expect(find.text('2 unpaid bills · 1 overdue'), findsOneWidget);
      expect(find.text('Water - September'), findsOneWidget);
      expect(find.text('Overdue'), findsOneWidget);
      expect(
        find.text('Water - August'),
        findsNothing,
      ); // paid ones hide while some are unpaid
      // Bills come before "My home".
      expect(
        tester.getTopLeft(find.text('My bills')).dy <
            tester.getTopLeft(find.text('My home')).dy,
        isTrue,
      );
    },
  );

  testWidgets('tenant Home: "All bills paid" when nothing is left', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [
        profileOf(AccountType.tenant),
        isAppAdminProvider.overrideWith((ref) async => false),
        myPropertiesProvider.overrideWith((ref) async => []),
        myRentalsProvider.overrideWith(
          (ref) async => [
            MyRental(
              tenancy: tenancyWith(acceptedAt: DateTime(2026, 10, 1)),
              propertyName: 'Sunset Court',
            ),
          ],
        ),
        myHomeBillsProvider.overrideWith(
          (ref) async => [
            HomeBill(
              bill: MyBill(
                assignmentId: 'x',
                title: 'Water - August',
                amount: 4000,
                dueDate: today(),
                paidAt: DateTime(2026, 9, 1),
              ),
              tenancyId: 't1',
              apartmentName: 'A1',
              currency: 'XAF',
            ),
          ],
        ),
      ],
      screen: const Size(360, 1200),
    );
    expect(find.text('All bills paid'), findsOneWidget);
    expect(find.text('Water - August'), findsOneWidget);
  });
}
