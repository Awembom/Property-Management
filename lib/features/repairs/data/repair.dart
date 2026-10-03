import 'package:rental_app/shared/utils/dates.dart';

/// One repair in a unit's history (`repairs`, read through
/// apartment_repairs()).
class Repair {
  const Repair({
    required this.id,
    required this.apartmentId,
    required this.title,
    required this.repairedOn,
    required this.createdAt,
    this.details,
    this.cost,
    this.tenancyId,
    this.ticketId,
    this.billId,
  });

  final String id;
  final String apartmentId;
  final String title;
  final String? details;
  final DateTime repairedOn;
  final DateTime createdAt;

  /// What it cost the owner (smallest currency unit). null if not entered,
  /// or for staff who may not see money.
  final int? cost;

  /// Who lived there at the time, the issue it fixed, the bill to the tenant.
  final String? tenancyId;
  final String? ticketId;
  final String? billId;

  factory Repair.fromJson(Map<String, dynamic> json) => Repair(
        id: json['id'] as String,
        apartmentId: json['apartment_id'] as String,
        title: json['title'] as String,
        details: json['details'] as String?,
        repairedOn: parseDbDate(json['repaired_on'] as String),
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        cost: json['cost'] as int?,
        tenancyId: json['tenancy_id'] as String?,
        ticketId: json['ticket_id'] as String?,
        billId: json['bill_id'] as String?,
      );
}
