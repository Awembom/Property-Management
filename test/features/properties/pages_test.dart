import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/properties/presentation/pages/members_page.dart';
import 'package:rental_app/features/properties/presentation/pages/properties_page.dart';
import 'package:rental_app/features/properties/presentation/pages/property_detail_page.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class FakeAuthRepository extends Fake implements AuthRepository {
  @override
  User? get currentUser => null;
}

MyProperty fakeProperty(MembershipRole role) => MyProperty(
      property: const Property(
        id: 'p1',
        name: 'Sunset Court',
        address: '1 Main St',
        currency: 'XAF',
        gracePeriodDays: 7,
      ),
      access: PropertyAccess(role: role, canRecordPaymentsFlag: false),
    );

/// Shows [page] in a router with the data providers replaced by fakes.
Future<void> pumpPage(WidgetTester tester, Widget page, {required List overrides}) async {
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => page)]);
  await tester.pumpWidget(ProviderScope(
    overrides: [authRepositoryProvider.overrideWithValue(FakeAuthRepository()), ...overrides.cast()],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('properties list shows each property with my role', (tester) async {
    await pumpPage(tester, const PropertiesPage(), overrides: [
      myPropertiesProvider.overrideWith((ref) async => [fakeProperty(MembershipRole.manager)]),
    ]);
    expect(find.text('Sunset Court'), findsOneWidget);
    expect(find.text('Manager'), findsOneWidget);
  });

  testWidgets('empty list explains what to do', (tester) async {
    await pumpPage(tester, const PropertiesPage(), overrides: [
      myPropertiesProvider.overrideWith((ref) async => []),
    ]);
    expect(find.text('No properties yet'), findsOneWidget);
    expect(find.text('Add property'), findsOneWidget);
  });

  testWidgets('owner sees edit and delete on property page', (tester) async {
    await pumpPage(tester, const PropertyDetailPage(propertyId: 'p1'), overrides: [
      myPropertyProvider.overrideWith((ref, id) async => fakeProperty(MembershipRole.owner)),
    ]);
    expect(find.byTooltip('Edit'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
  });

  testWidgets('caretaker sees no edit or delete on property page', (tester) async {
    await pumpPage(tester, const PropertyDetailPage(propertyId: 'p1'), overrides: [
      myPropertyProvider.overrideWith((ref, id) async => fakeProperty(MembershipRole.caretaker)),
    ]);
    expect(find.text('Sunset Court'), findsOneWidget);
    expect(find.byTooltip('Edit'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
  });

  final members = [
    const Member(membershipId: 'm1', userId: 'u1', role: MembershipRole.owner,
        canRecordPayments: false, fullName: 'Olivia Owner', email: 'o@x.com'),
    const Member(membershipId: 'm2', userId: 'u2', role: MembershipRole.caretaker,
        canRecordPayments: true, fullName: 'Carl Caretaker', email: 'c@x.com'),
  ];

  testWidgets('owner can add members', (tester) async {
    await pumpPage(tester, const MembersPage(propertyId: 'p1'), overrides: [
      myPropertyProvider.overrideWith((ref, id) async => fakeProperty(MembershipRole.owner)),
      propertyMembersProvider.overrideWith((ref, id) async => members),
    ]);
    expect(find.text('Olivia Owner'), findsOneWidget);
    expect(find.textContaining('Can record payments'), findsOneWidget);
    expect(find.text('Add member'), findsOneWidget);

    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    expect(find.text('Their email'), findsOneWidget);
  });

  testWidgets('manager sees the team but cannot add members', (tester) async {
    await pumpPage(tester, const MembersPage(propertyId: 'p1'), overrides: [
      myPropertyProvider.overrideWith((ref, id) async => fakeProperty(MembershipRole.manager)),
      propertyMembersProvider.overrideWith((ref, id) async => members),
    ]);
    expect(find.text('Carl Caretaker'), findsOneWidget);
    expect(find.text('Add member'), findsNothing);
  });
}
