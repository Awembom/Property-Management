import 'package:rental_app/features/auth/data/account_type.dart';

/// A row from the `profiles` table.
///
/// Database columns are snake_case (`full_name`); Dart fields are camelCase
/// (`fullName`). fromJson/toUpdateJson are the only places that know the
/// database names.
class Profile {
  const Profile({required this.id, this.fullName, this.phone, this.username, this.accountType});

  final String id;

  /// Chosen at sign-up; can't be changed.
  final String? username;

  /// "How will you use the app?" from sign-up (guides first steps only).
  final AccountType? accountType;
  final String? fullName;
  final String? phone;

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      fullName: json['full_name'] as String?,
      phone: json['phone'] as String?,
      username: json['username'] as String?,
      accountType: AccountType.fromJson(json['account_type'] as String?),
    );
  }

  /// The whole row, as the database returns it (to save it on the phone).
  Map<String, dynamic> toJson() => {
        'id': id,
        'full_name': fullName,
        'phone': phone,
        'username': username,
        'account_type': accountType?.value,
      };

  /// Only the columns users may edit (the database also enforces this).
  Map<String, dynamic> toUpdateJson() {
    return {'full_name': fullName, 'phone': phone};
  }
}
