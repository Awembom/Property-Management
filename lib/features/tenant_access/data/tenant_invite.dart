/// An open invite code for a tenant contact (`tenant_invites`).
class TenantInvite {
  const TenantInvite({required this.code, required this.expiresAt});

  /// e.g. 'TEN-4K7Q9M'. The tenant types it after signing up.
  final String code;
  final DateTime expiresAt;

  factory TenantInvite.fromJson(Map<String, dynamic> json) {
    return TenantInvite(
      code: json['code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }
}

/// What happened when a tenant entered a code.
class RedeemResult {
  const RedeemResult({required this.ok, this.error, this.propertyName});

  final bool ok;

  /// Why it failed (readable, from the database).
  final String? error;

  /// The property they're now linked to.
  final String? propertyName;

  factory RedeemResult.fromJson(Map<String, dynamic> json) {
    return RedeemResult(
      ok: json['ok'] as bool,
      error: json['error'] as String?,
      propertyName: json['property_name'] as String?,
    );
  }
}
