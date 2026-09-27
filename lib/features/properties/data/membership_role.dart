/// A staff member's role on a property (the `membership_role` enum in Postgres).
enum MembershipRole {
  owner,
  manager,
  caretaker;

  /// Database value -> enum. Throws if the database has a value we don't know.
  static MembershipRole fromJson(String value) {
    return MembershipRole.values.byName(value);
  }

  /// Enum -> database value ('owner', 'manager', 'caretaker').
  String toJson() => name;

  /// Label shown in the app.
  String get label => switch (this) {
        MembershipRole.owner => 'Owner',
        MembershipRole.manager => 'Manager',
        MembershipRole.caretaker => 'Caretaker',
      };
}

/// What the current user may do on one property, based on their role.
///
/// IMPORTANT: this only decides which buttons to SHOW. The real protection is
/// the RLS policies in the database (see CLAUDE.md, "Roles and Permissions").
/// If the UI got this wrong, the database would still refuse the action.
class PropertyAccess {
  const PropertyAccess({required this.role, required this.canRecordPaymentsFlag});

  final MembershipRole role;

  /// The caretaker `can_record_payments` toggle from the membership.
  final bool canRecordPaymentsFlag;

  bool get _ownerOrManager =>
      role == MembershipRole.owner || role == MembershipRole.manager;

  bool get canEditProperty => _ownerOrManager;
  bool get canDeleteProperty => role == MembershipRole.owner;
  bool get canManageMembers => role == MembershipRole.owner;
  bool get canManageApartments => _ownerOrManager;
  bool get canManageTenancies => _ownerOrManager;
  bool get canRecordPayments => _ownerOrManager || canRecordPaymentsFlag;

  /// Rent amounts, totals, repair costs. Caretakers never see money.
  bool get canSeeMoney => _ownerOrManager;
}
