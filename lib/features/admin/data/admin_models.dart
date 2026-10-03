import 'package:rental_app/features/auth/data/account_type.dart';

/// A person (account) as the admin sees it.
class AdminPerson {
  const AdminPerson({
    required this.id,
    required this.createdAt,
    this.username,
    this.fullName,
    this.accountType,
    this.propertyCount = 0,
    this.rentalCount = 0,
  });

  final String id;
  final String? username;
  final String? fullName;
  final AccountType? accountType;
  final DateTime createdAt;

  /// Properties where they're owner, manager or caretaker.
  final int propertyCount;

  /// Tenant contacts their account is linked to.
  final int rentalCount;

  String get displayName => fullName ?? (username == null ? 'Unknown' : '@$username');
}

/// A property as the admin sees it: name, currency, owners, size.
class AdminProperty {
  const AdminProperty({
    required this.id,
    required this.name,
    required this.currency,
    this.address,
    this.owners = const [],
    this.apartmentCount = 0,
  });

  final String id;
  final String name;
  final String? address;
  final String currency;

  /// Owner names (with @username).
  final List<String> owners;
  final int apartmentCount;
}
