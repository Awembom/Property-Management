import 'package:rental_app/features/properties/data/membership_role.dart';

/// A staff member of a property: a `memberships` row plus the person's
/// name and email from `profiles`.
class Member {
  const Member({
    required this.membershipId,
    required this.userId,
    required this.role,
    required this.canRecordPayments,
    this.fullName,
    this.email,
  });

  final String membershipId;
  final String userId;
  final MembershipRole role;
  final bool canRecordPayments;
  final String? fullName;
  final String? email;

  /// Best available name to show.
  String get displayName => fullName ?? email ?? 'Unknown user';

  /// Parses `select('id, user_id, role, can_record_payments, profile:profiles(full_name, email)')`.
  factory Member.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return Member(
      membershipId: json['id'] as String,
      userId: json['user_id'] as String,
      role: MembershipRole.fromJson(json['role'] as String),
      canRecordPayments: json['can_record_payments'] as bool,
      fullName: profile?['full_name'] as String?,
      email: profile?['email'] as String?,
    );
  }
}
