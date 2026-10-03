import 'package:rental_app/features/properties/data/caretaker_permissions.dart';
import 'package:rental_app/features/properties/data/membership_role.dart';

/// A staff member of a property: a `memberships` row plus the person's
/// name and username from `profiles`.
class Member {
  const Member({
    required this.membershipId,
    required this.userId,
    required this.role,
    required this.canRecordPayments,
    this.permissions = CaretakerPermissions.none,
    this.fullName,
    this.username,
  });

  final String membershipId;
  final String userId;
  final MembershipRole role;
  final bool canRecordPayments;

  /// A caretaker's switches.
  final CaretakerPermissions permissions;
  final String? fullName;
  /// What they log in with, e.g. 'tina'.
  final String? username;

  /// Best available name to show.
  String get displayName => fullName ?? username ?? 'Unknown user';

  /// Parses `select('id, user_id, role, can_record_payments, ..., profile:profiles(full_name, username)')`.
  factory Member.fromJson(Map<String, dynamic> json) {
    final profile = json['profile'] as Map<String, dynamic>?;
    return Member(
      membershipId: json['id'] as String,
      userId: json['user_id'] as String,
      role: MembershipRole.fromJson(json['role'] as String),
      canRecordPayments: json['can_record_payments'] as bool,
      permissions: CaretakerPermissions.fromJson(json),
      fullName: profile?['full_name'] as String?,
      username: profile?['username'] as String?,
    );
  }
}
