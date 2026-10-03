import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/properties/data/member.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/presentation/pages/members_page.dart';
import 'package:rental_app/features/admin/providers/admin_providers.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/dashboard/presentation/pages/home_page.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/auth/data/auth_repository.dart';
import 'package:rental_app/features/tenancies/data/tenant.dart';
import 'package:rental_app/features/tenant_access/data/my_rental.dart';
import 'package:rental_app/features/tenant_access/data/tenant_access_repository.dart';
import 'package:rental_app/features/tenant_access/data/tenant_invite.dart';
import 'package:rental_app/features/tenant_access/presentation/pages/join_with_code_page.dart';
import 'package:rental_app/features/tenant_access/presentation/widgets/tenant_app_access_card.dart';
import 'package:rental_app/features/tenant_access/providers/tenant_access_providers.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../helpers/fakes.dart';

/// Records calls instead of talking to Supabase.
class FakeTenantAccessRepository extends Fake
    implements TenantAccessRepository {
  final calls = <String>[];
  RedeemResult redeemResult = const RedeemResult(
    ok: true,
    propertyName: 'Sunset Court',
  );

  @override
  Future<TenantInvite> createInvite(String tenantId) async {
    calls.add('create $tenantId');
    return TenantInvite(code: 'TEN-4K7Q9M', expiresAt: DateTime(2026, 10, 8));
  }

  @override
  Future<RedeemResult> redeemInvite(String code) async {
    calls.add('redeem $code');
    return redeemResult;
  }

  @override
  Future<String> resetPassword({
    required String? propertyId,
    required String userId,
  }) async {
    calls.add('reset $propertyId $userId');
    return 'K7QM-4XP2-RTAB';
  }
}

class FakeAuthRepository extends Fake implements AuthRepository {
  @override
  User? get currentUser => null;
}

/// Shows [child] on a page inside a router (needed for context.pop()).
Future<void> pumpWithRouter(
  WidgetTester tester,
  Widget child,
  List overrides,
) async {
  final router = GoRouter(
    initialLocation: '/page',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: Text('Home screen')),
        routes: [GoRoute(path: 'page', builder: (_, _) => child)],
      ),
    ],
  );
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  const unlinked = Tenant(id: 'x1', fullName: 'Tina Tenant');
  const linked = Tenant(id: 'x1', fullName: 'Tina Tenant', userId: 'u9');

  Widget card(Tenant tenant) => Scaffold(
    body: TenantAppAccessCard(
      propertyId: 'p1',
      tenant: tenant,
      onChanged: () {},
    ),
  );

  testWidgets('not linked, no code yet: create one', (tester) async {
    final fake = FakeTenantAccessRepository();
    await pumpWithRouter(tester, card(unlinked), [
      tenantAccessRepositoryProvider.overrideWithValue(fake),
      openInviteProvider.overrideWith((ref, id) async => null),
    ]);
    expect(find.text('Not using the app yet'), findsOneWidget);
    await tester.tap(find.text('Create invite code'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['create x1']);
  });

  testWidgets('open code is shown with its expiry', (tester) async {
    await pumpWithRouter(tester, card(unlinked), [
      openInviteProvider.overrideWith(
        (ref, id) async =>
            TenantInvite(code: 'TEN-4K7Q9M', expiresAt: DateTime(2026, 10, 8)),
      ),
    ]);
    expect(find.text('TEN-4K7Q9M'), findsOneWidget);
    expect(find.text('Works once, until 8 Oct 2026.'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets('linked tenant: reset password shows the temporary password', (
    tester,
  ) async {
    final fake = FakeTenantAccessRepository();
    await pumpWithRouter(tester, card(linked), [
      tenantAccessRepositoryProvider.overrideWithValue(fake),
    ]);
    expect(find.text('Uses the app'), findsOneWidget);
    await tester.tap(find.text('Reset password'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['reset p1 u9']);
    expect(find.text('K7QM-4XP2-RTAB'), findsOneWidget);
  });

  testWidgets('join: a good code links and goes back', (tester) async {
    final fake = FakeTenantAccessRepository();
    await pumpWithRouter(tester, const JoinWithCodePage(), [
      tenantAccessRepositoryProvider.overrideWithValue(fake),
    ]);
    await tester.enterText(find.byType(TextFormField), 'ten-4k7q9m');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(fake.calls, ['redeem ten-4k7q9m']);
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.textContaining('linked to Sunset Court'), findsOneWidget);
  });

  testWidgets('join: a wrong code shows the reason and stays', (tester) async {
    final fake = FakeTenantAccessRepository()
      ..redeemResult = const RedeemResult(
        ok: false,
        error: 'That code is wrong, used or expired.',
      );
    await pumpWithRouter(tester, const JoinWithCodePage(), [
      tenantAccessRepositoryProvider.overrideWithValue(fake),
    ]);
    await tester.enterText(find.byType(TextFormField), 'TEN-XXXXXX');
    await tester.tap(find.text('Join'));
    await tester.pumpAndSettle();
    expect(find.text('That code is wrong, used or expired.'), findsOneWidget);
    expect(find.text('Home screen'), findsNothing);
  });

  testWidgets('home shows "My home" for a linked tenant', (tester) async {
    await pumpPage(
      tester,
      const HomePage(),
      overrides: [
        myPropertiesProvider.overrideWith((ref) async => []),
        myRentalsProvider.overrideWith(
          (ref) async => [
            MyRental(tenancy: fakeTenancy(), propertyName: 'Sunset Court'),
          ],
        ),
        profileOf(AccountType.tenant),
        isAppAdminProvider.overrideWith((ref) async => false),
      ],
      screen: const Size(360, 1200),
    );
    expect(find.text('My home'), findsOneWidget);
    expect(find.text('Apartment A1'), findsOneWidget);
    expect(find.text('Sunset Court'), findsOneWidget);
    expect(find.text('Have another invite code?'), findsOneWidget);
  });

  List teamOverrides(Member member) => [
    authRepositoryProvider.overrideWithValue(FakeAuthRepository()),
    myPropertyProvider.overrideWith(
      (ref, id) async => fakeProperty(MembershipRole.owner),
    ),
    propertyMembersProvider.overrideWith((ref, id) async => [member]),
  ];

  testWidgets('caretaker passwords: no reset for the owner, only the admin', (
    tester,
  ) async {
    await pumpPage(
      tester,
      const MembersPage(propertyId: 'p1'),
      overrides: teamOverrides(
        const Member(
          membershipId: 'm2',
          userId: 'u2',
          role: MembershipRole.caretaker,
          canRecordPayments: false,
          fullName: 'Carl Caretaker',
          username: 'carl',
        ),
      ),
      screen: const Size(360, 1400),
    );
    expect(find.textContaining('@carl'), findsOneWidget);
    await tester.tap(find.text('Carl Caretaker'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsNothing);
    expect(
      find.textContaining('app admin can reset a caretaker'),
      findsOneWidget,
    );
    // The permission switches, with "Full access" first.
    expect(find.text('Full access (same as owner)'), findsOneWidget);
    expect(find.text('See money'), findsOneWidget);

    // "Full access" turns every switch on.
    await tester.tap(find.text('Full access (same as owner)'));
    await tester.pumpAndSettle();
    final switches = tester.widgetList<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switches.every((s) => s.value), isTrue);
  });

  testWidgets('owner can still reset a manager\'s password', (tester) async {
    await pumpPage(
      tester,
      const MembersPage(propertyId: 'p1'),
      overrides: teamOverrides(
        const Member(
          membershipId: 'm3',
          userId: 'u3',
          role: MembershipRole.manager,
          canRecordPayments: false,
          fullName: 'Mia Manager',
          username: 'mia',
        ),
      ),
      screen: const Size(360, 1200),
    );
    await tester.tap(find.text('Mia Manager'));
    await tester.pumpAndSettle();
    expect(find.text('Reset password'), findsOneWidget);
  });
}
