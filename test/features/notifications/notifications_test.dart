import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/apartments/presentation/pages/apartment_detail_page.dart';
import 'package:rental_app/features/apartments/providers/apartments_providers.dart';
import 'package:rental_app/features/notifications/data/app_notification.dart';
import 'package:rental_app/features/notifications/data/notifications_repository.dart';
import 'package:rental_app/features/notifications/presentation/notifications_page.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';
import 'package:rental_app/features/properties/providers/properties_providers.dart';
import 'package:rental_app/features/repairs/data/repairs_repository.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/features/tenancies/providers/tenancies_providers.dart';
import 'package:rental_app/shared/utils/dates.dart';

import '../../helpers/fakes.dart';

class FakeNotificationsRepository extends Fake implements NotificationsRepository {
  final calls = <String>[];

  @override
  Future<void> markAllRead() async => calls.add('read');

  @override
  Future<DateTime?> setRemindersPaused(String tenancyId, int days) async {
    calls.add('pause $tenancyId $days');
    return days == 0 ? null : today().add(Duration(days: days));
  }
}

/// [fakeTenancy] with an app account and, optionally, paused reminders.
TenancyOverview tenancyWithAccount({DateTime? pausedUntil}) {
  final t = fakeTenancy();
  return TenancyOverview(
    id: t.id,
    propertyId: t.propertyId,
    apartmentId: t.apartmentId,
    apartmentName: t.apartmentName,
    tenantId: t.tenantId,
    tenantName: t.tenantName,
    paymentIntervalMonths: t.paymentIntervalMonths,
    startDate: t.startDate,
    billingStartDate: t.billingStartDate,
    paidUntil: t.paidUntil,
    paidMonths: t.paidMonths,
    isActive: true,
    rentStatus: t.rentStatus,
    remindersPausedUntil: pausedUntil,
    tenantHasAccount: true,
  );
}

List unitOverrides(TenancyOverview tenancy, FakeNotificationsRepository repository) => [
      myPropertyProvider.overrideWith((ref, id) async => fakeProperty(MembershipRole.caretaker)),
      apartmentProvider.overrideWith((ref, id) async => a1),
      apartmentTenanciesProvider.overrideWith((ref, id) async => [tenancy]),
      unitTicketsProvider.overrideWith((ref, id) async => []),
      unitBillsProvider.overrideWith((ref, id) async => []),
      unitRepairsProvider.overrideWith((ref, id) async => []),
      notificationsRepositoryProvider.overrideWithValue(repository),
    ];

void main() {
  testWidgets('bell list: newest first, unread marked, all marked read on opening', (tester) async {
    final repository = FakeNotificationsRepository();
    await pumpPage(tester, const NotificationsPage(), overrides: [
      notificationsRepositoryProvider.overrideWithValue(repository),
      myNotificationsProvider.overrideWith((ref) async => [
            AppNotification(
              id: 'n1',
              kind: 'rent',
              title: 'Rent due in 5 days',
              body: 'Your rent for apartment A1 is due on 6 Oct 2026: XAF 150,000.',
              createdAt: DateTime.now(),
              route: '/home/my-home/t1',
            ),
            AppNotification(
              id: 'n2',
              kind: 'bill',
              title: 'New bill: Water - October',
              body: 'XAF 4,500 to pay by 15 Oct 2026.',
              createdAt: DateTime.now().subtract(const Duration(days: 1)),
              readAt: DateTime.now(),
            ),
          ]),
    ]);
    expect(find.text('Rent due in 5 days'), findsOneWidget);
    expect(find.text('Yesterday'), findsOneWidget);
    expect(repository.calls, contains('read'));
  });

  testWidgets('unit: reminders are on; a caretaker pauses them for a week', (tester) async {
    final repository = FakeNotificationsRepository();
    await pumpPage(
      tester,
      const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
      screen: const Size(360, 2000),
      overrides: unitOverrides(tenancyWithAccount(), repository),
    );
    expect(find.text('Rent reminders on'), findsOneWidget);
    await tester.tap(find.byTooltip('Rent reminders'));
    await tester.pumpAndSettle();
    expect(find.text('Turn back on'), findsNothing);
    await tester.tap(find.text('Pause for a week'));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('pause t1 7'));
  });

  testWidgets('unit: paused reminders say until when and can be turned back on', (tester) async {
    final repository = FakeNotificationsRepository();
    await pumpPage(
      tester,
      const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
      screen: const Size(360, 2000),
      overrides: unitOverrides(tenancyWithAccount(pausedUntil: today().add(const Duration(days: 5))), repository),
    );
    expect(find.text('Rent reminders paused'), findsOneWidget);
    expect(find.text('Until ${formatDate(today().add(const Duration(days: 5)))}.'), findsOneWidget);
    await tester.tap(find.byTooltip('Rent reminders'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Turn back on'));
    await tester.pumpAndSettle();
    expect(repository.calls, contains('pause t1 0'));
  });

  testWidgets('unit: a tenant without the app can\'t get reminders (and the page says so)', (tester) async {
    await pumpPage(
      tester,
      const ApartmentDetailPage(propertyId: 'p1', apartmentId: 'a1'),
      screen: const Size(360, 2000),
      overrides: unitOverrides(fakeTenancy(), FakeNotificationsRepository()),
    );
    expect(find.text('No rent reminders yet'), findsOneWidget);
    expect(find.byTooltip('Rent reminders'), findsNothing);
  });
}
