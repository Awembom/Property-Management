import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into a short message that is safe to show to users.
///
/// Supabase Auth errors carry a `code`; the full list is at
/// https://supabase.com/docs/guides/auth/debugging/error-codes
String friendlyErrorMessage(Object error) {
  if (error is AuthRetryableFetchException) {
    return 'Could not reach the server. Check your internet connection.';
  }
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Wrong email or password.';
      case 'email_not_confirmed':
        return 'Please confirm your email first.';
      case 'otp_expired':
        return 'That code is wrong or has expired. Request a new one.';
      case 'over_email_send_rate_limit':
        return 'Too many emails sent. Please wait a few minutes and try again.';
      case 'user_already_exists':
      case 'weak_password':
        return error.message;
    }
    return error.message;
  }
  if (error is PostgrestException) {
    // Our database functions raise readable messages (e.g. the last-owner rule).
    return error.message;
  }
  final text = error.toString();
  if (text.contains('SocketException') || text.contains('ClientException')) {
    return 'Could not reach the server. Check your internet connection.';
  }
  return 'Something went wrong. Please try again.';
}
