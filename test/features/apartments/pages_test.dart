import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/presentation/pages/apartment_detail_page.dart';
import 'package:rental_app/features/apartments/presentation/pages/apartments_page.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';

import 'package:rental_app/features/repairs/data/repairs_repository.dart';

import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/repairs/data/repair.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/shared/utils/dates.dart';

import 'package:rental_app/features/payments/providers/payments_providers.dart';

import '../../helpers/fakes.dart';

void main() {
  final list = [
    ApartmentWithTenancy(apartment: a1, activeTenancy: fakeTenancy()),
    const ApartmentWithTenancy(apartment: a2),
  ];

  testWidgets('apartments list shows vacant and rent status; manager can add', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const ApartmentsPage(propertyId: 'p1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => fakeProperty(MembershipRole.manager),
        ),
        apartmentsProvider.overrideWith((ref, id) async => list),
      ],
    );
    expect(find.text('Tina Tenant'), findsOneWidget);
    expect(find.text('Overdue'), findsWidgets); // pill + header stat label
    // Owners/managers see a vacant apartment's standard rent.
    expect(find.text('Ready · XAF 60,000 / month'), findsOneWidget);
    expect(find.text('Add apartment'), findsOneWidget);

    // Filter: only vacant apartments.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Vacant'));
    await tester.pumpAndSettle();
    expect(find.text('Tina Tenant'), findsNothing);
    expect(find.text('A2'), findsOneWidget);
  });

  testWidgets('caretaker sees apartments but cannot add', (tester) async {
    await pumpPage(
      tester,
      const ApartmentsPage(propertyId: 'p1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => fakeProperty(MembershipRole.caretaker),
        ),
        apartmentsProvider.overrideWith((ref, id) async => list),
      ],
    );
    expect(find.text('A1'), findsOneWidget);
    expect(find.text('Add apartment'), findsNothing);
    expect(find.textContaining('XAF'), findsNothing); // no money for caretakers
    expect(find.text('Ready for a new tenant'), findsOneWidget);
  });

  testWidgets('empty list invites a manager to add the first apartment', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const ApartmentsPage(propertyId: 'p1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => fakeProperty(MembershipRole.owner),
        ),
        apartmentsProvider.overrideWith((ref, id) async => []),
      ],
    );
    expect(find.text('No apartments yet'), findsOneWidget);
    await tester.tap(find.text('Add apartment'));
    await tester.pumpAndSettle();
    expect(find.text('Name or number'), findsOneWidget);
    expect(find.text('Monthly rent'), findsOneWidget);

    // The rent is required.
    // .last = the button in the sheet (the empty screen has one too).
    await tester.tap(find.widgetWithText(FilledButton, 'Add apartment').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter an amount, e.g. 50000'), findsOneWidget);
  });

  List detailOverrides(
    MembershipRole role,
    List<TenancyOverview> tenancies, {
    List<Ticket> tickets = const [],
    List<MyBill> bills = const [],
    List<Repair> repairs = const [],
  }) =>
      [
        myPropertyProvider.overrideWith((ref, id) async => fakeProperty(role)),
        apartmentProvider.overrideWith((ref, id) async => a1),
        apartmentTenanciesProvider.overrideWith((ref, id) async => tenancies),
        unitTicketsProvider.overrideWith((ref, id) async => tickets),
        unitBillsProvider.overrideWith((ref, id) async => bills),
        unitRepairsProvider.overrideWith((ref, id) async => repairs),
      ];

  testWidgets('vacant apartment: manager can start a tenancy, sees history', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
      overrides: detailOverrides(MembershipRole.manager, [
        fakeTenancy(active: false),
      ]),
      screen: const Size(360, 2000),
    );
    expect(find.text('No one lives here right now'), findsOneWidget);
    expect(find.text('No issues reported'), findsOneWidget);
    expect(find.text('No repairs logged'), findsOneWidget);
    expect(find.text('Same as the property'), findsOneWidget);
    expect(find.text('Start tenancy'), findsOneWidget);
    expect(find.text('Old Oscar'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsOneWidget);
  });

  testWidgets('vacant apartment: caretaker cannot start a tenancy or edit', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
      overrides: detailOverrides(MembershipRole.caretaker, []),
    );
    expect(find.text('No one lives here right now'), findsOneWidget);
    expect(find.text('Start tenancy'), findsNothing);
    expect(find.byTooltip('Edit'), findsNothing);
  });

  testWidgets(
    'occupied apartment shows the current tenant and when rent was due',
    (tester) async {
      await pumpPage(
        tester,
        const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
        overrides: detailOverrides(MembershipRole.manager, [fakeTenancy()]),
      );
      expect(find.text('Tina Tenant'), findsOneWidget);
      expect(find.textContaining('Rent was due 1 Sep 2026'), findsOneWidget);
      expect(find.text('Start tenancy'), findsNothing);
    },
  );

  testWidgets('occupied unit: quick actions, issues, bills (one waived) and repairs in one place', (tester) async {
    await pumpPage(
      tester,
      const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
      screen: const Size(360, 2400),
      overrides: [
        ...detailOverrides(
          MembershipRole.owner,
          [fakeTenancy()],
          tickets: [
              Ticket(
                id: 'k1',
                propertyId: 'p1',
                tenancyId: 't1',
                title: 'Leaking tap',
                category: TicketCategory.plumbing,
                status: TicketStatus.open,
                createdAt: DateTime(2026, 9, 20),
                updatedAt: DateTime(2026, 9, 20),
              ),
          ],
          bills: [
              MyBill(assignmentId: 'b1', title: 'Water - October', amount: 4500, dueDate: today().add(const Duration(days: 5))),
              MyBill(
                assignmentId: 'b2',
                title: 'Repair: tap',
                amount: 8000,
                dueDate: today(),
                waivedAt: DateTime(2026, 10, 1),
                waiveReason: 'Our fault',
              ),
          ],
          repairs: [
              Repair(
                id: 'r1',
                apartmentId: 'a1',
                title: 'New tap',
                repairedOn: DateTime(2026, 9, 25),
                createdAt: DateTime(2026, 9, 25),
                cost: 12000,
                billId: 'bill9',
              ),
          ],
        ),
        tenancyPaymentsProvider.overrideWith((ref, id) async => [fakePartPayment()]),
        tenancyDetailsProvider.overrideWith((ref, ids) async => TenancyDetails(
              overview: fakeTenancy(),
              tenant: const Tenant(id: 'x1', fullName: 'Tina Tenant', phone: '+237 677 000 111'),
            )),
      ],
    );
    // Rent is overdue, so "Remind" (a ready-written message) replaces "Message".
    for (final action in ['Remind', 'Bill', 'Rent', 'Call', 'Repair']) {
      expect(find.text(action), findsOneWidget, reason: action);
    }
    expect(find.text('Issues (1 open)'), findsOneWidget);
    expect(find.text('Leaking tap'), findsOneWidget);
    expect(find.text('Bills · XAF 4,500 to pay'), findsOneWidget); // the waived one doesn't count
    expect(find.text('Waived: Our fault'), findsOneWidget);
    expect(find.text('New tap'), findsOneWidget);
    expect(find.text('25 Sep 2026 · cost XAF 12,000 · tenant billed'), findsOneWidget);
    expect(find.text('Collected from Tina'), findsOneWidget);
    expect(find.text('XAF 120,000'), findsOneWidget); // the part payment
  });

  test('a rent reminder says how much and since when', () {
    final text = rentReminderText(fakeTenancy(), const TenancyMoney(monthlyRent: 50000), 'XAF');
    expect(text, startsWith('Hello Tina, a friendly reminder that your rent of XAF 150,000 for apartment A1 was due on 1 Sep 2026'));
    expect(rentReminderText(fakeTenancy(), null, null), contains('your rent for apartment A1'));
  });
}
