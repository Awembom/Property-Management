import 'package:rental_app/features/tenancies/data/tenancy.dart';

/// A row from the `apartments` table.
class Apartment {
  const Apartment({
    required this.id,
    required this.propertyId,
    required this.name,
    this.description,
    this.monthlyRent,
    this.agreementText,
  });

  final String id;
  final String propertyId;

  /// e.g. "A1", "Flat 3". Unique within the property.
  final String name;
  final String? description;

  /// The standard monthly rent, in the currency's smallest unit. Pre-filled
  /// when starting a tenancy. null for caretakers (they never get money
  /// figures) and for apartments created before rents were added.
  final int? monthlyRent;

  /// This unit's own tenancy agreement; null = the property's.
  final String? agreementText;

  static const columns = 'id, property_id, name, description, agreement_text';

  factory Apartment.fromJson(Map<String, dynamic> json) {
    return Apartment(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      agreementText: json['agreement_text'] as String?,
    );
  }

  /// A copy with the monthly rent filled in (it comes from another table).
  Apartment withMonthlyRent(int? rent) {
    return Apartment(
      id: id,
      propertyId: propertyId,
      name: name,
      description: description,
      monthlyRent: rent,
      agreementText: agreementText,
    );
  }
}

/// An apartment together with its current (active) tenancy, if any.
class ApartmentWithTenancy {
  const ApartmentWithTenancy({required this.apartment, this.activeTenancy});

  final Apartment apartment;
  final TenancyOverview? activeTenancy;

  bool get isVacant => activeTenancy == null;
}

/// Sorts names the way people expect: "A2" before "A10" (plain text sorting
/// would put "A10" first because '1' < '2').
int compareNatural(String a, String b) {
  final chunk = RegExp(r'\d+|\D+');
  final partsA = chunk
      .allMatches(a.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();
  final partsB = chunk
      .allMatches(b.toLowerCase())
      .map((m) => m.group(0)!)
      .toList();

  for (var i = 0; i < partsA.length && i < partsB.length; i++) {
    final numberA = int.tryParse(partsA[i]);
    final numberB = int.tryParse(partsB[i]);
    final result = (numberA != null && numberB != null)
        ? numberA.compareTo(numberB)
        : partsA[i].compareTo(partsB[i]);
    if (result != 0) return result;
  }
  return partsA.length.compareTo(partsB.length);
}
