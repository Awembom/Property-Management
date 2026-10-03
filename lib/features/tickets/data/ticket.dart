import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// Where a ticket is in its life (`ticket_status` in Postgres).
enum TicketStatus {
  open('open', 'Open', AppColors.overdue, Icons.error_outline_rounded),
  inProgress('in_progress', 'In progress', AppColors.dueSoon, Icons.autorenew_rounded),
  resolved('resolved', 'Resolved', AppColors.paid, Icons.check_circle_rounded);

  const TicketStatus(this.value, this.label, this.color, this.icon);

  final String value;
  final String label;
  final Color color;
  final IconData icon;

  static TicketStatus fromJson(String value) =>
      values.firstWhere((s) => s.value == value, orElse: () => TicketStatus.open);
}

/// What kind of issue (`tickets.category`).
enum TicketCategory {
  plumbing('plumbing', 'Plumbing', Icons.plumbing_rounded),
  electrical('electrical', 'Electrical', Icons.electrical_services_rounded),
  water('water', 'Water', Icons.water_drop_rounded),
  security('security', 'Security', Icons.shield_rounded),
  cleaning('cleaning', 'Cleaning', Icons.cleaning_services_rounded),

  /// A problem with a receipt. Only opened from the receipt itself
  /// (dispute_receipt), never picked by hand.
  receipt('receipt', 'Receipt', Icons.receipt_long_rounded),
  other('other', 'Other', Icons.help_outline_rounded);

  const TicketCategory(this.value, this.label, this.icon);

  final String value;
  final String label;
  final IconData icon;

  static TicketCategory fromJson(String value) =>
      values.firstWhere((c) => c.value == value, orElse: () => TicketCategory.other);

  /// What a tenant can choose when reporting an issue.
  static List<TicketCategory> get pickable => values.where((c) => c != receipt).toList();
}

/// An issue a tenant reported (`tickets`).
class Ticket {
  const Ticket({
    required this.id,
    required this.propertyId,
    required this.tenancyId,
    required this.title,
    required this.category,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.paymentId,
    this.apartmentName,
    this.apartmentId,
    this.tenantName,
    this.pending = false,
  });

  final String id;
  final String propertyId;
  final String tenancyId;
  final String title;
  final String? description;
  final TicketCategory category;
  final TicketStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Receipt tickets: the payment whose receipt is disputed.
  final String? paymentId;

  /// Created offline and not sent yet (lives in the outbox, has no real id).
  final bool pending;

  /// Filled in for the team's lists (from the tenancy).
  final String? apartmentName;
  final String? apartmentId;
  final String? tenantName;

  static const columns =
      'id, property_id, tenancy_id, title, description, category, status, created_at, updated_at, '
      'payment_id';

  factory Ticket.fromJson(
    Map<String, dynamic> json, {
    String? apartmentName,
    String? apartmentId,
    String? tenantName,
  }) {
    return Ticket(
      id: json['id'] as String,
      propertyId: json['property_id'] as String,
      tenancyId: json['tenancy_id'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      category: TicketCategory.fromJson(json['category'] as String),
      status: TicketStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
      paymentId: json['payment_id'] as String?,
      apartmentName: apartmentName,
      apartmentId: apartmentId,
      tenantName: tenantName,
    );
  }
}

/// One reply in a ticket's conversation.
class TicketMessage {
  const TicketMessage({
    required this.id,
    required this.body,
    required this.fromStaff,
    required this.createdAt,
    this.pending = false,
  });

  final String id;
  final String body;

  /// Written offline, waiting to be sent.
  final bool pending;

  /// true = written by the team; false = by the tenant.
  final bool fromStaff;
  final DateTime createdAt;

  factory TicketMessage.fromJson(Map<String, dynamic> json) {
    return TicketMessage(
      id: json['id'] as String,
      body: json['body'] as String,
      fromStaff: json['from_staff'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }
}
