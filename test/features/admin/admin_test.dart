import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/admin/data/activity_entry.dart';
import 'package:rental_app/features/admin/data/admin_models.dart';
import 'package:rental_app/features/admin/data/describe_activity.dart';
import 'package:rental_app/features/admin/presentation/pages/admin_page.dart';
import 'package:rental_app/features/admin/providers/admin_providers.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/dashboard/data/dashboard.dart';
import 'package:rental_app/features/dashboard/presentation/pages/home_page.dart';
import 'package:rental_app/features/dashboard/providers/dashboard_providers.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';

import '../../helpers/fakes.dart';

ActivityEntry entry(
  String table,
  String action, {
  Map<String, dynamic>? before,
  Map<String, dynamic>? after,
}) => ActivityEntry(
  id: 1,
  happenedAt: DateTime.now().subtract(const Duration(minutes: 5)),
  tableName: table,
  action: action,
  actorId: 'u2',
  propertyId: 'p1',
  oldData: before,
  newData: after,
);

void main() {
  group('activity sentences', () {
    test('payment, with part payment noted', () {
      final text = describeActivity(
        entry(
          'payments',
          'INSERT',
          after: {'kind': 'rent', 'amount': 120000, 'expected_amount': 150000},
        ),
        currency: 'XAF',
      );
      expect(
        text.title,
        'Recorded a payment of XAF 120,000 (part payment, due XAF 150,000)',
      );
    });

    test('rent change shows before and after', () {
      final e = entry(
        'tenancies',
        'UPDATE',
        before: {'monthly_rent': 50000, 'status': 'active', 'notes': null},
        after: {'monthly_rent': 55000, 'status': 'active', 'notes': null},
      );
      expect(
        describeActivity(e, currency: 'XAF').title,
        'Changed the rent from XAF 50,000 to XAF 55,000',
      );
      expect(e.changes, [('monthly_rent', 50000, 55000)]);
    });

    test('tenant joining with a code, void, team change', () {
      expect(
        describeActivity(
          entry(
            'tenants',
            'UPDATE',
            before: {'full_name': 'Tina', 'user_id': null},
            after: {'full_name': 'Tina', 'user_id': 'u9'},
          ),
        ).title,
        'Tina joined the app with an invite code',
      );
      expect(
        describeActivity(
          entry('payment_voids', 'INSERT', after: {'reason': 'Twice'}),
        ).title,
        'Voided a payment: "Twice"',
      );
      expect(
        describeActivity(
          entry('memberships', 'INSERT', after: {'role': 'caretaker'}),
        ).title,
        'Added a team member as caretaker',
      );
    });
  });

  final adminOverrides = [
    isAppAdminProvider.overrideWith((ref) async => true),
    activityProvider.overrideWith(
      (ref) async => [
        entry('payments', 'INSERT', after: {'kind': 'rent', 'amount': 50000}),
      ],
    ),
    adminPropertiesProvider.overrideWith(
      (ref) async => const [
        AdminProperty(
          id: 'p1',
          name: 'Sunset Court',
          currency: 'XAF',
          owners: ['Olivia @olivia'],
          apartmentCount: 4,
        ),
      ],
    ),
    adminPeopleProvider.overrideWith(
      (ref) async => [
        AdminPerson(
          id: 'u2',
          username: 'mike',
          fullName: 'Mike Manager',
          accountType: AccountType.team,
          createdAt: DateTime(2026, 10, 1),
          propertyCount: 1,
        ),
      ],
    ),
  ];

  testWidgets('admin sees activity with who and where', (tester) async {
    await pumpPage(tester, const AdminPage(), overrides: adminOverrides);
    expect(find.text('Recorded a payment of XAF 50,000'), findsOneWidget);
    expect(
      find.textContaining('Mike Manager · Sunset Court · 5 min ago'),
      findsOneWidget,
    );
  });

  testWidgets('admin properties tab offers transfer of ownership', (
    tester,
  ) async {
    await pumpPage(tester, const AdminPage(), overrides: adminOverrides);
    await tester.tap(find.text('Properties'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Owner: Olivia @olivia'), findsOneWidget);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    expect(find.text('Transfer ownership'), findsOneWidget);
  });

  testWidgets('admin people tab: tap to reset a password', (tester) async {
    await pumpPage(tester, const AdminPage(), overrides: adminOverrides);
    await tester.tap(find.text('People'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mike Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Reset Mike Manager\'s password?'), findsOneWidget);
  });

  testWidgets('non-admins are kept out', (tester) async {
    await pumpPage(
      tester,
      const AdminPage(),
      overrides: [isAppAdminProvider.overrideWith((ref) async => false)],
    );
    expect(find.text('Admins only'), findsOneWidget);
  });

  group('home: first steps by account type', () {
    List homeOverrides(AccountType type, {bool admin = false}) => [
      myPropertiesProvider.overrideWith((ref) async => []),
      myRentalsProvider.overrideWith((ref) async => []),
      dashboardProvider.overrideWith(
        (ref) async => const Dashboard(properties: [], stats: {}, active: []),
      ),
      isAppAdminProvider.overrideWith((ref) async => admin),
      profileOf(type),
    ];

    testWidgets('tenant is asked for the invite code', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: homeOverrides(AccountType.tenant),
      );
      expect(find.text('Connect to your home'), findsOneWidget);
      expect(find.text('Enter invite code'), findsOneWidget);
    });

    testWidgets('team member is told to share their username', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: homeOverrides(AccountType.team),
      );
      expect(find.text('Waiting to be added'), findsOneWidget);
      expect(find.textContaining('@tina'), findsOneWidget);
      expect(find.textContaining('invite code'), findsNothing);
    });

    testWidgets('landlord is invited to add a property; no admin button', (
      tester,
    ) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: homeOverrides(AccountType.landlord),
      );
      expect(find.text('Add your first property'), findsOneWidget);
      expect(find.byTooltip('Admin'), findsNothing);
      // Landlords never see invite-code prompts.
      expect(find.textContaining('invite code'), findsNothing);
    });

    testWidgets('the app admin gets an Admin button', (tester) async {
      await pumpPage(
        tester,
        const HomePage(),
        overrides: homeOverrides(AccountType.landlord, admin: true),
      );
      expect(find.byTooltip('Admin'), findsOneWidget);
    });
  });
}
