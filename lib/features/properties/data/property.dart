import 'package:rental_app/features/properties/data/caretaker_permissions.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';

/// A row from the `properties` table.
class Property {
  const Property({
    required this.id,
    required this.name,
    required this.currency,
    required this.gracePeriodDays,
    this.address,
    this.contactPhone,
    this.agreementText,
  });

  final String id;
  final String name;
  final String? address;

  /// ISO code, e.g. 'XAF'.
  final String currency;

  /// Days before the due date when rent shows as "Due soon".
  final int gracePeriodDays;

  /// The number tenants tap to call (owner's or a caretaker's).
  final String? contactPhone;

  /// The property's tenancy agreement; null = the app's default text.
  final String? agreementText;

  factory Property.fromJson(Map<String, dynamic> json) {
    return Property(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      currency: json['currency'] as String,
      gracePeriodDays: json['grace_period_days'] as int,
      contactPhone: json['contact_phone'] as String?,
      agreementText: json['agreement_text'] as String?,
    );
  }

  /// The editable columns, for updates.
  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name,
      'address': address,
      'currency': currency,
      'grace_period_days': gracePeriodDays,
      'contact_phone': contactPhone,
    };
  }
}

/// A property as seen by the current user: the property plus their role on it.
class MyProperty {
  const MyProperty({required this.property, required this.access});

  final Property property;
  final PropertyAccess access;

  /// Parses a `memberships` row with the property embedded, i.e. the result of
  /// `select('role, can_record_payments, property:properties(...)')`.
  factory MyProperty.fromMembershipJson(Map<String, dynamic> json) {
    return MyProperty(
      property: Property.fromJson(json['property'] as Map<String, dynamic>),
      access: PropertyAccess(
        role: MembershipRole.fromJson(json['role'] as String),
        canRecordPaymentsFlag: json['can_record_payments'] as bool,
        permissions: CaretakerPermissions.fromJson(json),
      ),
    );
  }
}
