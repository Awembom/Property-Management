import 'package:rental_app/features/tenancies/data/tenancy.dart';

/// A tenancy the logged-in user rents (as a tenant), with the property's
/// name and currency.
class MyRental {
  const MyRental({required this.tenancy, required this.propertyName, this.currency = 'XAF'});

  final TenancyOverview tenancy;
  final String propertyName;

  /// The property's currency, for showing bill amounts.
  final String currency;
}
