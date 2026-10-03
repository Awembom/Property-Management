import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/shared/utils/dates.dart';

/// A kind of bill in a property (`bill_types`): Water and Electricity come
/// as standard (can be switched off); landlords add their own.
class BillType {
  const BillType({required this.id, required this.name, required this.isStandard, required this.enabled});

  final String id;
  final String name;
  final bool isStandard;
  final bool enabled;

  static const columns = 'id, name, is_standard, enabled';

  factory BillType.fromJson(Map<String, dynamic> json) => BillType(
        id: json['id'] as String,
        name: json['name'] as String,
        isStandard: json['is_standard'] as bool,
        enabled: json['enabled'] as bool,
      );

  IconData get icon => switch (name.toLowerCase()) {
        'water' => Icons.water_drop_rounded,
        'electricity' => Icons.bolt_rounded,
        _ => Icons.receipt_rounded,
      };
}

/// Paid, waived (doesn't have to be paid), not paid yet, or not paid and
/// past the due date. Worked out from dates, never stored (CLAUDE.md,
/// business rule 7).
enum BillStatus {
  paid('Paid', AppColors.paid, Icons.check_circle_rounded),
  waived('Waived', AppColors.ended, Icons.do_not_disturb_on_rounded),
  unpaid('Unpaid', AppColors.dueSoon, Icons.schedule_rounded),
  overdue('Overdue', AppColors.overdue, Icons.error_rounded);

  const BillStatus(this.label, this.color, this.icon);

  final String label;
  final Color color;
  final IconData icon;

  static BillStatus of({required DateTime? paidAt, required DateTime dueDate, DateTime? waivedAt}) {
    if (paidAt != null) return BillStatus.paid;
    if (waivedAt != null) return BillStatus.waived;
    return daysUntil(dueDate) < 0 ? BillStatus.overdue : BillStatus.unpaid;
  }
}

/// One apartment's part of a bill (`bill_assignments`).
class BillAssignment {
  const BillAssignment({
    required this.id,
    required this.tenancyId,
    required this.amount,
    this.paidAt,
    this.waivedAt,
    this.waiveReason,
    this.apartmentName,
    this.tenantName,
  });

  final String id;
  final String tenancyId;
  final int amount;
  final DateTime? paidAt;

  /// Waived: the tenant doesn't have to pay this (with the reason).
  final DateTime? waivedAt;
  final String? waiveReason;

  /// Filled in for the team's view.
  final String? apartmentName;
  final String? tenantName;

  bool get isPaid => paidAt != null;
  bool get isWaived => waivedAt != null;

  /// Paid or waived: nothing left to pay.
  bool get isSettled => isPaid || isWaived;

  factory BillAssignment.fromJson(Map<String, dynamic> json, {String? apartmentName, String? tenantName}) {
    return BillAssignment(
      id: json['id'] as String,
      tenancyId: json['tenancy_id'] as String,
      amount: json['amount'] as int,
      paidAt: _time(json['paid_at']),
      waivedAt: _time(json['waived_at']),
      waiveReason: json['waive_reason'] as String?,
      apartmentName: apartmentName,
      tenantName: tenantName,
    );
  }
}

/// A bill (`bills`) with its apartments' parts.
class Bill {
  const Bill({
    required this.id,
    required this.propertyId,
    required this.billTypeId,
    required this.title,
    required this.dueDate,
    required this.createdAt,
    this.notes,
    this.assignments = const [],
  });

  final String id;
  final String propertyId;
  final String billTypeId;
  final String title;
  final String? notes;
  final DateTime dueDate;
  final DateTime createdAt;
  final List<BillAssignment> assignments;

  static const columns =
      'id, property_id, bill_type_id, title, notes, due_date, created_at, '
      'assignments:bill_assignments(id, tenancy_id, amount, paid_at, waived_at, waive_reason)';

  int get paidCount => assignments.where((a) => a.isPaid).length;

  /// Paid or waived.
  int get settledCount => assignments.where((a) => a.isSettled).length;
  int get total => assignments.fold(0, (sum, a) => sum + a.amount);
  int get collected => assignments.where((a) => a.isPaid).fold(0, (sum, a) => sum + a.amount);

  /// Overall: paid when everyone paid (or was let off); overdue when someone
  /// hasn't and the due date passed.
  BillStatus get status => settledCount == assignments.length && assignments.isNotEmpty
      ? BillStatus.paid
      : BillStatus.of(paidAt: null, dueDate: dueDate);

  factory Bill.fromJson(Map<String, dynamic> json, {Map<String, Map<String, dynamic>> names = const {}}) {
    return Bill(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      billTypeId: json['bill_type_id'] as String,
      title: json['title'] as String,
      notes: json['notes'] as String?,
      dueDate: parseDbDate(json['due_date'] as String),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      assignments: [
        for (final a in (json['assignments'] as List? ?? const []).cast<Map<String, dynamic>>())
          BillAssignment.fromJson(
            a,
            apartmentName: names[a['tenancy_id']]?['apartment_name'] as String?,
            tenantName: names[a['tenancy_id']]?['tenant_name'] as String?,
          ),
      ],
    );
  }
}

/// One apartment's part of a bill, with the bill's details: a tenant's own
/// bills, and a unit's bills on the unit page.
class MyBill {
  const MyBill({
    required this.assignmentId,
    required this.title,
    required this.amount,
    required this.dueDate,
    this.paidAt,
    this.waivedAt,
    this.waiveReason,
    this.notes,
    this.billId,
    this.tenancyId,
  });

  final String assignmentId;
  final String title;
  final int amount;
  final DateTime dueDate;
  final DateTime? paidAt;
  final DateTime? waivedAt;
  final String? waiveReason;
  final String? notes;

  /// Filled in on the unit page (to open the bill).
  final String? billId;
  final String? tenancyId;

  /// Still to be paid (not paid, not waived).
  bool get isOpen => paidAt == null && waivedAt == null;

  BillStatus get status => BillStatus.of(paidAt: paidAt, dueDate: dueDate, waivedAt: waivedAt);

  /// Columns for [MyBill.fromJson], from bill_assignments.
  static const columns = 'id, tenancy_id, amount, paid_at, waived_at, waive_reason, '
      'bill:bills(id, title, notes, due_date, created_at)';

  factory MyBill.fromJson(Map<String, dynamic> json) {
    final bill = json['bill'] as Map<String, dynamic>;
    return MyBill(
      assignmentId: json['id'] as String,
      amount: json['amount'] as int,
      paidAt: _time(json['paid_at']),
      waivedAt: _time(json['waived_at']),
      waiveReason: json['waive_reason'] as String?,
      billId: bill['id'] as String?,
      tenancyId: json['tenancy_id'] as String?,
      title: bill['title'] as String,
      notes: bill['notes'] as String?,
      dueDate: parseDbDate(bill['due_date'] as String),
    );
  }
}

DateTime? _time(Object? value) => value == null ? null : DateTime.parse(value as String).toLocal();
