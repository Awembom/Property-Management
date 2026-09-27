/// A row from the `profiles` table.
///
/// Database columns are snake_case (`full_name`); Dart fields are camelCase
/// (`fullName`). fromJson/toUpdateJson are the only places that know the
/// database names.
class Profile {
  const Profile({required this.id, this.fullName, this.phone});

  final String id;
  final String? fullName;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      phone: json['phone'] as String?,
    );
  }

  /// Only the columns users may edit (the database also enforces this).
  Map<String, dynamic> toUpdateJson() {
    return {'full_name': fullName, 'phone': phone};
  }
}
