import 'package:rental_app/features/properties/data/property.dart';
import 'package:rental_app/features/tenancies/data/rent_status.dart';
import 'package:rental_app/features/tenancies/data/tenancy.dart';

/// Numbers for one property: apartments, occupancy, rent status.
class PropertyStats {
  const PropertyStats({
    this.apartments = 0,
    this.occupied = 0,
    this.overdue = 0,
    this.dueSoon = 0,
    this.collectedThisMonth,
  });

  final int apartments;
  final int occupied;
  final int overdue;
  final int dueSoon;

  /// Rent received this month (smallest unit); null if I can't see money here.
  final int? collectedThisMonth;

  int get vacant => apartments - occupied;

  /// 0-100.
  int get occupancyPercent => apartments == 0 ? 0 : (occupied * 100 / apartments).round();
}

/// Everything the landlord/team Home tab shows.
class Dashboard {
  const Dashboard({required this.properties, required this.stats, required this.active});

  final List<MyProperty> properties;

  /// property id -> its numbers.
  final Map<String, PropertyStats> stats;

  /// Active tenancies across all my properties.
  final List<TenancyOverview> active;

  PropertyStats statsFor(String propertyId) => stats[propertyId] ?? const PropertyStats();

  int get apartments => stats.values.fold(0, (sum, s) => sum + s.apartments);
  int get occupied => stats.values.fold(0, (sum, s) => sum + s.occupied);
  int get overdue => stats.values.fold(0, (sum, s) => sum + s.overdue);
  int get dueSoon => stats.values.fold(0, (sum, s) => sum + s.dueSoon);

  /// Rent collected this month per currency (only properties where I may
  /// see money). Empty if I can't see money anywhere.
  Map<String, int> get collectedByCurrency {
    final totals = <String, int>{};
    for (final my in properties) {
      final collected = statsFor(my.property.id).collectedThisMonth;
      if (collected == null) continue;
      totals[my.property.currency] = (totals[my.property.currency] ?? 0) + collected;
    }
    return totals;
  }

  /// Tenancies that need a look: overdue first, then due soon.
  List<TenancyOverview> get needsAttention {
    final list = active
        .where((t) => t.rentStatus == RentStatus.overdue || t.rentStatus == RentStatus.dueSoon)
        .toList()
      ..sort((a, b) {
        final byStatus = (a.rentStatus == RentStatus.overdue ? 0 : 1)
            .compareTo(b.rentStatus == RentStatus.overdue ? 0 : 1);
        return byStatus != 0 ? byStatus : a.paidUntil.compareTo(b.paidUntil);
      });
    return list;
  }

  String propertyName(String propertyId) => properties
      .firstWhere((p) => p.property.id == propertyId, orElse: () => properties.first)
      .property
      .name;
}
