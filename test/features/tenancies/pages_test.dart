import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/payments/providers/payments_providers.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tenancies/presentation/pages/start_tenancy_page.dart';
import 'package:rental_app/features/tenancies/presentation/pages/tenancy_detail_page.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  const tenant = Tenant(
    id: 'x1',
    fullName: 'Tina Tenant',
    phone: '+237 600 000 000',
    idNumber: 'ID-123456',
  );

  List overrides(MembershipRole role, {required bool withMoney}) => [
    myPropertyProvider.overrideWith((ref, id) async => fakeProperty(role)),
    tenancyDetailsProvider.overrideWith(
      (ref, ids) async => TenancyDetails(
        overview: fakeTenancy(),
        // Caretakers never receive the ID number from the database.
        tenant: withMoney
            ? tenant
            : const Tenant(id: 'x1', fullName: 'Tina Tenant'),
        money: withMoney
            ? const TenancyMoney(
                monthlyRent: 50000,
                standardMonthlyRent: 55000, // negotiated down from 55,000
                balance: 30000,
              )
            : null,
      ),
    ),
    tenancyPaymentsProvider.overrideWith(
      (ref, id) async => [fakePartPayment()],
    ),
  ];

  testWidgets('manager sees rent, balance, ID number, payments and actions', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const TenancyDetailPage(propertyId: 'p1', tenancyId: 't1'),
      overrides: overrides(MembershipRole.manager, withMoney: true),
      screen: const Size(
        360,
        2600,
      ), // tall, so the buttons at the bottom are built
    );
    expect(find.text('Tina Tenant - Unit A1'), findsOneWidget);
    expect(find.text('XAF 50,000 per month'), findsOneWidget);
    expect(find.text('Negotiated rent'), findsOneWidget);
    expect(find.text('Every 3 months · XAF 150,000 each time'), findsOneWidget);
    expect(find.text('Left to pay'), findsWidgets); // header + rent card
    expect(find.text('ID-123456'), findsOneWidget);
    expect(find.text('Record payment'), findsOneWidget);
    expect(find.text('Part paid'), findsOneWidget); // the payment in the list
    expect(find.text('Renew (continue tenancy)'), findsOneWidget);

    await tester.tap(find.text('Renew (continue tenancy)'));
    await tester.pumpAndSettle();
    expect(find.text('Monthly rent from now on'), findsOneWidget);
  });

  testWidgets('caretaker sees no money, no ID number, no manage buttons', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const TenancyDetailPage(propertyId: 'p1', tenancyId: 't1'),
      overrides: overrides(MembershipRole.caretaker, withMoney: false),
      screen: const Size(360, 2000),
    );
    expect(find.textContaining('XAF'), findsNothing);
    expect(
      find.text('Rent amounts are only shown to owners and managers.'),
      findsOneWidget,
    );
    expect(find.text('ID card number'), findsNothing);
    expect(find.text('Payments & receipts'), findsNothing);
    expect(find.text('Record payment'), findsNothing); // no can_record_payments
    expect(find.text('Renew (continue tenancy)'), findsNothing);
    expect(find.text('End tenancy (move out)'), findsNothing);
    expect(find.text('Edit'), findsNothing);
  });

  testWidgets('start tenancy form checks the required fields', (tester) async {
    await pumpPage(
      tester,
      const StartTenancyPage(propertyId: 'p1', apartmentId: 'a1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => fakeProperty(MembershipRole.owner),
        ),
        apartmentProvider.overrideWith((ref, id) async => a1),
        propertyTenantsProvider.overrideWith((ref, id) async => [tenant]),
      ],
      screen: const Size(360, 2000),
    );
    expect(find.text('New tenant · A1'), findsOneWidget);
    expect(find.text('Existing'), findsOneWidget); // there's a contact to pick
    expect(find.text('ID card number (optional)'), findsOneWidget);

    await tester.tap(find.text('Start tenancy'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the tenant\'s name'), findsOneWidget);
    expect(find.text('Enter an amount, e.g. 50000'), findsOneWidget);
  });

  testWidgets(
    'monthly rent pre-filled; intervals have no weekly but have custom',
    (tester) async {
      await pumpPage(
        tester,
        const StartTenancyPage(propertyId: 'p1', apartmentId: 'a2'),
        overrides: [
          myPropertyProvider.overrideWith(
            (ref, id) async => fakeProperty(MembershipRole.owner),
          ),
          apartmentProvider.overrideWith(
            (ref, id) async => a2,
          ), // 60,000 / month
          propertyTenantsProvider.overrideWith((ref, id) async => []),
        ],
        screen: const Size(360, 2000),
      );
      final rentField = find.widgetWithText(TextFormField, 'Monthly rent');
      expect(
        find.descendant(of: rentField, matching: find.text('60000')),
        findsOneWidget,
      );
      expect(find.textContaining('Standard rent for A2'), findsOneWidget);

      for (final label in [
        'Monthly',
        'Every 3 months',
        'Every 6 months',
        'Yearly',
        'Custom',
      ]) {
        expect(find.widgetWithText(ChoiceChip, label), findsOneWidget);
      }
      expect(find.textContaining('Weekly'), findsNothing);

      // Every 6 months: shows what each payment will be.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Every 6 months'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('They\'ll pay XAF 360,000 every 6 months.'),
        findsOneWidget,
      );

      // Custom: type a number of months.
      await tester.tap(find.widgetWithText(ChoiceChip, 'Custom'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Number of months'),
        '2',
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('They\'ll pay XAF 120,000 every 2 months.'),
        findsOneWidget,
      );
    },
  );
}
