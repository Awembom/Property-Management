import 'package:rental_app/features/properties/data/caretaker_permissions.dart';

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
  const PropertyAccess({
    required this.role,
    this.canRecordPaymentsFlag = false,
    this.permissions = CaretakerPermissions.none,
  });

  final MembershipRole role;

  /// The caretaker `can_record_payments` toggle (kept for older callers;
  /// also part of [permissions]).
  final bool canRecordPaymentsFlag;

  /// A caretaker's switches (ignored for owners and managers).
  final CaretakerPermissions permissions;

  bool get isOwner => role == MembershipRole.owner;
  bool get _ownerOrManager => isOwner || role == MembershipRole.manager;

  bool get canEditProperty => _ownerOrManager || permissions.manageApartments;
  bool get canDeleteProperty => isOwner;
  bool get canManageMembers => isOwner || permissions.manageTeam;
  bool get canManageApartments => _ownerOrManager || permissions.manageApartments;
  bool get canManageTenancies => _ownerOrManager || permissions.manageTenancies;
  bool get canRecordPayments =>
      _ownerOrManager || canRecordPaymentsFlag || permissions.recordPayments;

  /// Rent amounts, totals, receipts. Caretakers only with the switch.
  bool get canSeeMoney => _ownerOrManager || permissions.seeMoney;

  /// Voiding a payment needs both money and payments.
  bool get canVoidPayments => canSeeMoney && canRecordPayments;

  /// Water, Electricity and custom bill types = property setup.
  bool get canManageBillTypes => canManageApartments;
}
