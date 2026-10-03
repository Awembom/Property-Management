import 'package:rental_app/features/payments/data/payment.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';

/// Everything a tenant sees about one of their rentals.
class MyRentalDetails {
  const MyRentalDetails({
    required this.tenancy,
    required this.tenantName,
    required this.propertyName,
    required this.currency,
    required this.monthlyRent,
    required this.balance,
    required this.payments,
    this.propertyAddress,
    this.contactPhone,
  });

  final TenancyOverview tenancy;
  final String tenantName;
  final String propertyName;
  final String? propertyAddress;
  final String currency;

  /// The landlord's number for this property (tap to call).
  final String? contactPhone;

  /// Rent per month (smallest currency unit).
  final int monthlyRent;

  /// Money still owed from part payments (negative = paid in advance).
  final int balance;

  /// Their payments, newest first.
  final List<Payment> payments;

  /// What one regular payment is: monthly rent x payment interval.
  int get regularPayment => monthlyRent * tenancy.paymentIntervalMonths;
}
