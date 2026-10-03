/// The switches an owner can turn on for a caretaker (columns on
/// `memberships`). All of them together = "full access", the same as an
/// owner, except deleting the property and managing owners (always
/// owner-only). Managers and owners don't use these: their role decides.
class CaretakerPermissions {
  const CaretakerPermissions({
    this.recordPayments = false,
    this.seeMoney = false,
    this.manageApartments = false,
    this.manageTenancies = false,
    this.manageTeam = false,
  });

  /// Record rent payments and mark bills paid.
  final bool recordPayments;

  /// See rent amounts, payments, receipts, balances and ID numbers.
  final bool seeMoney;

  /// Add/edit apartments and their rent, edit the property, bill types.
  final bool manageApartments;

  /// Tenants and tenancies: start, renew, end, invite codes, tenant passwords.
  final bool manageTenancies;

  /// Add, change and remove managers and caretakers.
  final bool manageTeam;

  static const none = CaretakerPermissions();
  static const full = CaretakerPermissions(
    recordPayments: true,
    seeMoney: true,
    manageApartments: true,
    manageTenancies: true,
    manageTeam: true,
  );

  bool get isFull =>
      recordPayments && seeMoney && manageApartments && manageTenancies && manageTeam;

  /// Columns to select from `memberships`.
  static const columns =
      'can_record_payments, can_see_money, can_manage_apartments, can_manage_tenancies, can_manage_team';

  factory CaretakerPermissions.fromJson(Map<String, dynamic> json) {
    return CaretakerPermissions(
      recordPayments: json['can_record_payments'] as bool? ?? false,
      seeMoney: json['can_see_money'] as bool? ?? false,
      manageApartments: json['can_manage_apartments'] as bool? ?? false,
      manageTenancies: json['can_manage_tenancies'] as bool? ?? false,
      manageTeam: json['can_manage_team'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'can_record_payments': recordPayments,
        'can_see_money': seeMoney,
        'can_manage_apartments': manageApartments,
        'can_manage_tenancies': manageTenancies,
        'can_manage_team': manageTeam,
      };

  CaretakerPermissions copyWith({
    bool? recordPayments,
    bool? seeMoney,
    bool? manageApartments,
    bool? manageTenancies,
    bool? manageTeam,
  }) {
    return CaretakerPermissions(
      recordPayments: recordPayments ?? this.recordPayments,
      seeMoney: seeMoney ?? this.seeMoney,
      manageApartments: manageApartments ?? this.manageApartments,
      manageTenancies: manageTenancies ?? this.manageTenancies,
      manageTeam: manageTeam ?? this.manageTeam,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CaretakerPermissions &&
      other.recordPayments == recordPayments &&
      other.seeMoney == seeMoney &&
      other.manageApartments == manageApartments &&
      other.manageTenancies == manageTenancies &&
      other.manageTeam == manageTeam;

  @override
  int get hashCode => Object.hash(recordPayments, seeMoney, manageApartments, manageTenancies, manageTeam);

  /// Short summary for the team list, e.g. "Full access" or "Payments, Money".
  String get summary {
    if (isFull) return 'Full access';
    final parts = [
      if (recordPayments) 'Payments',
      if (seeMoney) 'Money',
      if (manageApartments) 'Apartments',
      if (manageTenancies) 'Tenancies',
      if (manageTeam) 'Team',
    ];
    return parts.isEmpty ? 'Basic access' : parts.join(', ');
  }
}
