import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/features/auth/data/profile.dart';
import 'package:rental_app/features/auth/providers/auth_providers.dart';
import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';

// Fake data and a helper to show one screen, shared by the widget tests.

MyProperty fakeProperty(MembershipRole role) => MyProperty(
  property: const Property(
    id: 'p1',
    name: 'Sunset Court',
    currency: 'XAF',
    gracePeriodDays: 7,
  ),
  access: PropertyAccess(role: role, canRecordPaymentsFlag: false),
);

const a1 = Apartment(id: 'a1', propertyId: 'p1', name: 'A1');
const a2 = Apartment(
  id: 'a2',
  propertyId: 'p1',
  name: 'A2',
  monthlyRent: 60000,
);

TenancyOverview fakeTenancy({
  bool active = true,
  RentStatus? status = RentStatus.overdue,
}) => TenancyOverview(
  id: active ? 't1' : 't0',
  propertyId: 'p1',
  apartmentId: 'a1',
  apartmentName: 'A1',
  tenantId: 'x1',
  tenantName: active ? 'Tina Tenant' : 'Old Oscar',
  paymentIntervalMonths: 3,
  startDate: DateTime(2026, 1, 1),
  endDate: active ? null : DateTime(2025, 12, 31),
  billingStartDate: DateTime(2026, 1, 1),
  paidUntil: DateTime(2026, 9, 1),
  paidMonths: 8,
  isActive: active,
  rentStatus: active ? status : null,
);

Future<void> pumpPage(
  WidgetTester tester,
  Widget page, {
  required List overrides,
  Size screen = const Size(360, 800),
}) async {
  // Phone-sized screen (360 x 800 by default, a common Android size), so layout
  // problems like text overflowing show up in tests.
  tester.view.physicalSize = screen * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, _) => page)],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides.cast(),
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

/// 3 months of a 50,000/month tenancy, but only 120,000 of 150,000 paid.
Payment fakePartPayment() => Payment(
  id: 'pay1',
  tenancyId: 't1',
  propertyId: 'p1',
  kind: PaymentKind.rent,
  amount: 120000,
  expectedAmount: 150000,
  balanceAfter: 30000,
  months: 3,
  periodStart: DateTime(2026, 6, 1),
  periodEnd: DateTime(2026, 9, 1),
  paidOn: DateTime(2026, 6, 2),
  method: 'mobile_money',
  receiptNumber: 'RCT-2026-0007',
  referenceCode: 'PAY-7K3QX9',
  issuedAt: DateTime(2026, 6, 2, 10),
);

/// Pays off the 30,000 left by [fakePartPayment]: same reference code.
Payment fakeCompletingPayment() => Payment(
  id: 'pay2',
  tenancyId: 't1',
  propertyId: 'p1',
  kind: PaymentKind.balance,
  amount: 30000,
  balanceAfter: 0,
  paidOn: DateTime(2026, 6, 20),
  method: 'cash',
  receiptNumber: 'RCT-2026-0009',
  referenceCode: 'PAY-7K3QX9',
  issuedAt: DateTime(2026, 6, 20, 9),
);

/// Stands in for the real profile loader.
class FakeProfileNotifier extends MyProfileNotifier {
  FakeProfileNotifier(this.profile);
  final Profile profile;
  @override
  Future<Profile> build() async => profile;
}

/// Override that makes the logged-in user's profile of [type].
dynamic profileOf(AccountType type, {String username = 'tina'}) =>
    myProfileProvider.overrideWith(
      () => FakeProfileNotifier(
        Profile(id: 'u1', username: username, accountType: type),
      ),
    );
