import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/apartments/data/apartment.dart';
import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';
import 'package:rental_app/shared/utils/dates.dart';

void main() {
  final tenancy = TenancyOverview.fromJson({
    'id': 't1',
    'property_id': 'p1',
    'apartment_id': 'a1',
    'apartment_name': 'A1',
    'tenant_id': 'x1',
    'tenant_name': 'Tina',
    'payment_interval_months': 3,
    'start_date': '2026-01-31',
    'end_date': null,
    'billing_start_date': '2026-01-31',
    'paid_until': '2026-04-30',
    'paid_months': 3,
    'status': 'active',
    'rent_status': 'due_soon',
  });

  test('TenancyOverview reads a tenancy_overview row', () {
    expect(tenancy.paymentIntervalMonths, 3);
    expect(tenancy.startDate, DateTime(2026, 1, 31));
    expect(tenancy.paidUntil, DateTime(2026, 4, 30));
    expect(tenancy.paidMonths, 3);
    expect(tenancy.isActive, isTrue);
    expect(tenancy.rentStatus, RentStatus.dueSoon);
  });

  test(
    'paid-until preview counts from the billing start, like the database',
    () {
      // 3 months paid from 31 Jan. Paying 2 more gives 31 Jan + 5 months = 30 Jun,
      // not 30 Apr + 2 months = 30 Jun... and 1 more gives 31 May (not 30 May).
      expect(tenancy.paidUntilAfter(1), DateTime(2026, 5, 31));
      expect(tenancy.paidUntilAfter(2), DateTime(2026, 6, 30));
    },
  );

  test('addMonths clamps to the end of shorter months', () {
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(
      addMonths(DateTime(2028, 1, 31), 1),
      DateTime(2028, 2, 29),
    ); // leap year
    expect(addMonths(DateTime(2026, 11, 15), 3), DateTime(2027, 2, 15));
    expect(addMonths(DateTime(2026, 1, 31), 12), DateTime(2027, 1, 31));
  });

  test('payment interval labels', () {
    expect(PaymentInterval.label(1), 'Monthly');
    expect(PaymentInterval.label(6), 'Every 6 months');
    expect(PaymentInterval.label(12), 'Yearly');
    expect(PaymentInterval.label(2), 'Every 2 months'); // custom
  });

  test('NewTenancy sends monthly rent, interval and ID number', () {
    final params = NewTenancy(
      apartmentId: 'a1',
      monthlyRent: 50000,
      paymentIntervalMonths: 6,
      startDate: DateTime(2026, 10, 1),
      tenantName: 'Nina',
      tenantIdNumber: 'ID-1',
      paidUntil: DateTime(2026, 11, 1),
    ).toRpcParams();
    expect(params['p_start_date'], '2026-10-01');
    expect(params['p_billing_start_date'], '2026-11-01');
    expect(params['p_monthly_rent'], 50000);
    expect(params['p_payment_interval_months'], 6);
    expect(params['p_tenant_id_number'], 'ID-1');
    expect(params['p_tenant_id'], isNull);
  });

  test('apartment names sort naturally (A2 before A10)', () {
    final names = ['A10', 'b1', 'A2', 'A1'];
    names.sort(compareNatural);
    expect(names, ['A1', 'A2', 'A10', 'b1']);
  });
}
