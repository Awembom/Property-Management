/// A tenant contact (`tenants` table). Created by staff; linked to a user
/// account later if the tenant signs up with the same email.
class Tenant {
  const Tenant({
    required this.id,
    required this.fullName,
    this.phone,
    this.email,
    this.userId,
    this.idNumber,
  });

  final String id;
  final String fullName;
  final String? phone;
  final String? email;

  /// The tenant's app account, once they joined with an invite code.
  final String? userId;

  /// True once the tenant signed up and their account was linked.
  bool get hasAccount => userId != null;

  /// ID card number. Kept in a separate table only owners and managers can
  /// read, so it's null for caretakers (and if none was entered).
  final String? idNumber;

  /// A copy with the ID number filled in (it comes from another table).
  Tenant withIdNumber(String? value) => Tenant(
        id: id,
        fullName: fullName,
        phone: phone,
        email: email,
        userId: userId,
        idNumber: value,
      );

  /// Columns to select for [Tenant.fromJson].
  static const columns = 'id, full_name, phone, email, user_id';

  factory Tenant.fromJson(Map<String, dynamic> json) {
    return Tenant(
      id: json['id'] as String,
      fullName: json['full_name'] as String,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      userId: json['user_id'] as String?,
    );
  }

  /// The editable columns, for updates. (user_id is never sent: only the
  /// database's linking function may set it.)
  Map<String, dynamic> toUpdateJson() {
    return {'full_name': fullName, 'phone': phone, 'email': email};
  }
}
