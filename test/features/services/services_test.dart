import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/announcements/data/announcement.dart';
import 'package:rental_app/features/announcements/presentation/pages/announcements_page.dart';
import 'package:rental_app/features/announcements/presentation/pages/new_announcement_page.dart';
import 'package:rental_app/features/announcements/providers/announcements_providers.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/bills/data/bill.dart';
import 'package:rental_app/features/bills/presentation/pages/bill_page.dart';
import 'package:rental_app/features/bills/presentation/pages/bill_types_page.dart';
import 'package:rental_app/features/bills/presentation/pages/bills_page.dart';
import 'package:rental_app/features/bills/presentation/pages/new_bill_page.dart';
import 'package:rental_app/features/bills/providers/bills_providers.dart';
import 'package:rental_app/features/properties/data/caretaker_permissions.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tickets/data/ticket.dart';
import 'package:rental_app/features/tickets/presentation/pages/property_tickets_page.dart';
import 'package:rental_app/features/tickets/presentation/pages/ticket_page.dart';
import 'package:rental_app/features/tickets/providers/tickets_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';

import '../../helpers/fakes.dart';

MyProperty caretakerWith(CaretakerPermissions permissions) => MyProperty(
  property: fakeProperty(MembershipRole.caretaker).property,
  access: PropertyAccess(
    role: MembershipRole.caretaker,
    permissions: permissions,
  ),
);

final bill = Bill(
  id: 'b1',
  propertyId: 'p1',
  billTypeId: 'water',
  title: 'Water - October',
  dueDate: today().subtract(const Duration(days: 2)), // already due
  createdAt: DateTime(2026, 10, 1),
  assignments: [
    BillAssignment(
      id: 'x1',
      tenancyId: 't1',
      amount: 4500,
      paidAt: DateTime(2026, 10, 2),
      apartmentName: 'A1',
      tenantName: 'Tina',
    ),
    const BillAssignment(
      id: 'x2',
      tenancyId: 't2',
      amount: 4500,
      apartmentName: 'A2',
      tenantName: 'Paul',
    ),
  ],
);

final ticket = Ticket(
  id: 'k1',
  propertyId: 'p1',
  tenancyId: 't1',
  title: 'Leaking tap',
  description: 'Kitchen tap drips',
  category: TicketCategory.plumbing,
  status: TicketStatus.open,
  createdAt: DateTime(2026, 10, 1),
  updatedAt: DateTime(2026, 10, 1),
  apartmentName: 'A1',
  tenantName: 'Tina',
);

void main() {
  group('caretaker permissions', () {
    test('no switches: basic access only', () {
      const access = PropertyAccess(role: MembershipRole.caretaker);
      expect(access.canSeeMoney, isFalse);
      expect(access.canManageTenancies, isFalse);
      expect(access.canManageMembers, isFalse);
      expect(access.canDeleteProperty, isFalse);
    });

    test('full access = like an owner, but never deletes the property', () {
      const access = PropertyAccess(
        role: MembershipRole.caretaker,
        permissions: CaretakerPermissions.full,
      );
      expect(access.canSeeMoney, isTrue);
      expect(access.canRecordPayments, isTrue);
      expect(access.canVoidPayments, isTrue);
      expect(access.canManageApartments, isTrue);
      expect(access.canManageTenancies, isTrue);
      expect(access.canManageMembers, isTrue);
      expect(access.canDeleteProperty, isFalse);
      expect(CaretakerPermissions.full.summary, 'Full access');
    });

    test('managers keep everything except the team', () {
      const access = PropertyAccess(role: MembershipRole.manager);
      expect(access.canSeeMoney && access.canManageTenancies, isTrue);
      expect(access.canManageMembers, isFalse);
    });
  });

  test('bill status from dates: paid, unpaid, overdue', () {
    expect(
      BillStatus.of(paidAt: DateTime(2026, 1, 1), dueDate: today()),
      BillStatus.paid,
    );
    expect(BillStatus.of(paidAt: null, dueDate: today()), BillStatus.unpaid);
    expect(
      BillStatus.of(
        paidAt: null,
        dueDate: today().subtract(const Duration(days: 1)),
      ),
      BillStatus.overdue,
    );
    expect(
      bill.status,
      BillStatus.overdue,
    ); // one apartment hasn't paid, due date passed
    expect(bill.paidCount, 1);
    expect(bill.collected, 4500);
  });

  testWidgets('bills list shows paid count and status', (tester) async {
    await pumpPage(
      tester,
      const BillsPage(propertyId: 'p1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => fakeProperty(MembershipRole.owner),
        ),
        propertyBillsProvider.overrideWith((ref, id) async => [bill]),
      ],
    );
    expect(find.text('Water - October'), findsOneWidget);
    expect(find.textContaining('1/2 paid'), findsOneWidget);
    expect(find.text('Overdue'), findsOneWidget);
    expect(find.byTooltip('Bill types'), findsOneWidget); // owner sets up types
  });

  testWidgets('a caretaker without setup rights does not see "Bill types"', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const BillsPage(propertyId: 'p1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => caretakerWith(CaretakerPermissions.none),
        ),
        propertyBillsProvider.overrideWith((ref, id) async => [bill]),
      ],
    );
    expect(find.byTooltip('Bill types'), findsNothing);
    expect(find.text('New bill'), findsOneWidget); // but may create bills
  });

  testWidgets('bill page: tick boxes only with the payments permission', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const BillPage(propertyId: 'p1', billId: 'b1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => caretakerWith(CaretakerPermissions.none),
        ),
        billProvider.overrideWith((ref, id) async => bill),
      ],
    );
    expect(find.text('Unit A1'), findsOneWidget);
    expect(find.byType(Checkbox), findsNothing);
  });

  testWidgets('new bill: only switched-on types, and the type is required', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const NewBillPage(propertyId: 'p1'),
      overrides: [
        myPropertyProvider.overrideWith(
          (ref, id) async => fakeProperty(MembershipRole.owner),
        ),
        billTypesProvider.overrideWith(
          (ref, id) async => const [
            BillType(id: 'w', name: 'Water', isStandard: true, enabled: false),
            BillType(
              id: 'e',
              name: 'Electricity',
              isStandard: true,
              enabled: true,
            ),
            BillType(
              id: 'i',
              name: 'Internet',
              isStandard: false,
              enabled: true,
            ),
          ],
        ),
        apartmentsProvider.overrideWith(
          (ref, id) async => [
            ApartmentWithTenancy(
              apartment: const Apartment(
                id: 'a1',
                propertyId: 'p1',
                name: 'A1',
              ),
              activeTenancy: fakeTenancy(),
            ),
          ],
        ),
      ],
      screen: const Size(360, 1400),
    );
    expect(
      find.widgetWithText(ChoiceChip, 'Water'),
      findsNothing,
    ); // switched off
    expect(find.widgetWithText(ChoiceChip, 'Electricity'), findsOneWidget);
    expect(find.widgetWithText(ChoiceChip, 'Internet'), findsOneWidget);
    expect(find.text('All occupied (1)'), findsOneWidget);

    await tester.tap(find.text('Create bill'));
    await tester.pumpAndSettle();
    expect(find.text('Choose the type of bill'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Electricity'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Electricity - '),
      findsOneWidget,
    ); // suggested title
  });

  testWidgets(
    'bill types: standard ones switch, custom ones can also be deleted',
    (tester) async {
      await pumpPage(
        tester,
        const BillTypesPage(propertyId: 'p1'),
        overrides: [
          billTypesProvider.overrideWith(
            (ref, id) async => const [
              BillType(
                id: 'w',
                name: 'Water',
                isStandard: true,
                enabled: false,
              ),
              BillType(
                id: 'i',
                name: 'Internet',
                isStandard: false,
                enabled: true,
              ),
            ],
          ),
        ],
      );
      expect(find.byType(Switch), findsNWidgets(2));
      expect(find.byTooltip('Delete'), findsOneWidget); // only Internet
      expect(find.text('Custom bill type'), findsOneWidget);
    },
  );

  testWidgets('tickets list and filter', (tester) async {
    await pumpPage(
      tester,
      const PropertyTicketsPage(propertyId: 'p1'),
      overrides: [
        propertyTicketsProvider.overrideWith((ref, id) async => [ticket]),
      ],
    );
    expect(find.text('Leaking tap'), findsOneWidget);
    expect(find.textContaining('Unit A1 · Tina'), findsOneWidget);
    await tester.ensureVisible(find.text('Resolved (0)'));
    await tester.tap(find.text('Resolved (0)'));
    await tester.pumpAndSettle();
    expect(find.text('Leaking tap'), findsNothing);
  });

  testWidgets('ticket page: team can change status; conversation shows', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const TicketPage(ticketId: 'k1'),
      overrides: [
        ticketProvider.overrideWith((ref, id) async => ticket),
        ticketMessagesProvider.overrideWith(
          (ref, id) async => [
            TicketMessage(
              id: 'm1',
              body: 'It is getting worse',
              fromStaff: false,
              createdAt: DateTime(2026, 10, 1),
            ),
          ],
        ),
        myPropertiesProvider.overrideWith(
          (ref) async => [fakeProperty(MembershipRole.caretaker)],
        ),
      ],
      screen: const Size(360, 1000),
    );
    expect(find.text('Leaking tap'), findsOneWidget);
    expect(find.byType(SegmentedButton<TicketStatus>), findsOneWidget);
    expect(find.text('It is getting worse'), findsOneWidget);
    expect(find.text('Write a reply'), findsOneWidget);
  });

  testWidgets('ticket page: the tenant cannot change the status', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const TicketPage(ticketId: 'k1'),
      overrides: [
        ticketProvider.overrideWith((ref, id) async => ticket),
        ticketMessagesProvider.overrideWith((ref, id) async => []),
        myPropertiesProvider.overrideWith((ref) async => []),
      ],
    );
    expect(find.byType(SegmentedButton<TicketStatus>), findsNothing);
  });

  testWidgets(
    'announcements: list shows who it went to; compose needs chosen tenants',
    (tester) async {
      await pumpPage(
        tester,
        const AnnouncementsPage(propertyId: 'p1'),
        overrides: [
          propertyAnnouncementsProvider.overrideWith(
            (ref, id) async => [
              Announcement(
                id: 'n1',
                propertyId: 'p1',
                title: 'Water cut',
                body: 'Saturday 8-12',
                toEveryone: true,
                createdAt: DateTime(2026, 10, 1),
              ),
            ],
          ),
        ],
      );
      expect(find.text('Water cut'), findsOneWidget);
      expect(find.text('All tenants'), findsOneWidget);
    },
  );

  testWidgets('new announcement: choosing tenants', (tester) async {
    await pumpPage(
      tester,
      const NewAnnouncementPage(propertyId: 'p1'),
      overrides: [
        apartmentsProvider.overrideWith(
          (ref, id) async => [
            ApartmentWithTenancy(
              apartment: const Apartment(
                id: 'a1',
                propertyId: 'p1',
                name: 'A1',
              ),
              activeTenancy: fakeTenancy(),
            ),
          ],
        ),
      ],
      screen: const Size(360, 1200),
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Title'),
      'Hello',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Message'),
      'Hi all',
    );
    await tester.tap(find.text('Choose'));
    await tester.pumpAndSettle();
    expect(find.text('Tina Tenant'), findsOneWidget);
    await tester.tap(find.text('Send announcement'));
    await tester.pumpAndSettle();
    expect(find.text('Choose at least one tenant'), findsOneWidget);
  });
}
