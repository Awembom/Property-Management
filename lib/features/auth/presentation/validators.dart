import 'package:rental_app/features/auth/data/username.dart';

/// Form field validators. Each returns an error message, or null if the value
/// is fine (that's what Flutter's `TextFormField.validator` expects).

/// For login: only checks something was typed.
String? validateUsernameEntered(String? value) {
  if ((value?.trim() ?? '').isEmpty) return 'Enter your username';
  return null;
}

/// For sign-up and adding team members: the username rules.
String? validateUsername(String? value) {
  final username = normalizeUsername(value ?? '');
  if (username.isEmpty) return 'Enter a username';
  if (username.length < 3) return 'Use at least 3 characters';
  if (username.length > 30) return 'Use at most 30 characters';
  if (!kUsernamePattern.hasMatch(username)) {
    return 'Use only letters, numbers, dots and _ (start with a letter or number)';
  }
  return null;
}

/// For login: only checks something was typed (the server decides if it's right).
String? validatePasswordEntered(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password';
  return null;
}

/// For signup and new passwords: the rules a new password must meet.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.length < 8) return 'Use at least 8 characters';
  return null;
}

/// The "Confirm password" field: must be typed the same as [password].
String? validatePasswordsMatch(String password, String? confirmation) {
  if ((confirmation ?? '').isEmpty) return 'Type the password again';
  if (confirmation != password) return 'The passwords don\'t match';
  return null;
}

String? validateFullName(String? value) {
  if ((value?.trim() ?? '').isEmpty) return 'Enter your name';
  return null;
}
