import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// One entry in the bell list (`notifications`). The same text was (or will
/// be) sent to the phone as a push notification.
class AppNotification {
  const AppNotification({
    required this.id,
    required this.kind,
    required this.title,
    required this.body,
    required this.createdAt,
    this.route,
    this.readAt,
  });

  final String id;

  /// rent, rent_manual, bill, receipt, message, issue, dispute, joined
  final String kind;
  final String title;
  final String body;

  /// The app screen to open, e.g. '/my-bills'.
  final String? route;
  final DateTime createdAt;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  static const columns = 'id, kind, title, body, route, created_at, read_at';

  factory AppNotification.fromJson(Map<String, dynamic> json) =>
      AppNotification(
        id: json['id'] as String,
        kind: json['kind'] as String,
        title: json['title'] as String,
        body: json['body'] as String,
        route: json['route'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
        readAt: json['read_at'] == null
            ? null
            : DateTime.parse(json['read_at'] as String).toLocal(),
      );

  IconData get icon => switch (kind) {
    'rent' || 'rent_manual' => Icons.home_rounded,
    'bill' => Icons.receipt_rounded,
    'receipt' => Icons.receipt_long_rounded,
    'message' => Icons.campaign_rounded,
    'dispute' => Icons.report_problem_rounded,
    'joined' => Icons.person_add_alt_1_rounded,
    _ => Icons.build_circle_rounded,
  };

  Color get color => switch (kind) {
    'rent' || 'rent_manual' => AppColors.primary,
    'bill' => AppColors.dueSoon,
    'receipt' || 'joined' => AppColors.paid,
    'message' => AppColors.accent,
    'dispute' => AppColors.overdue,
    _ => AppColors.overdue,
  };
}
