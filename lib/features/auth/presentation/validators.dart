import 'package:rental_app/features/auth/data/auth_repository.dart';

/// Form field validators. Each returns an error message, or null if the value
/// is fine (that's what Flutter's `TextFormField.validator` expects).

String? validateEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return 'Enter your email';
  // Deliberately simple: Supabase does the real check when it sends the email.
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email';
  }
  return null;
}

/// For login: only checks something was typed (the server decides if it's right).
String? validatePasswordEntered(String? value) {
  if (value == null || value.isEmpty) return 'Enter your password';
  return null;
}

/// For signup: the rules a new password must meet.
String? validateNewPassword(String? value) {
  final password = value ?? '';
  if (password.length < 8) return 'Use at least 8 characters';
  return null;
}

String? validateFullName(String? value) {
  if ((value?.trim() ?? '').isEmpty) return 'Enter your name';
  return null;
}

String? validateSignupCode(String? value) {
  final code = value?.trim() ?? '';
  if (code.length != kSignupCodeLength || int.tryParse(code) == null) {
    return 'Enter the $kSignupCodeLength-digit code from the email';
  }
  return null;
}
