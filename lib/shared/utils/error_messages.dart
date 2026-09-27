import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into a short message that is safe to show to users.
/// The full technical error is also printed to the `flutter run` console.
///
/// Supabase Auth errors carry a `code`; the full list is at
/// https://supabase.com/docs/guides/auth/debugging/error-codes
String friendlyErrorMessage(Object error) {
  debugPrint('Error shown to user: $error');

  // Careful: Supabase uses this ONE exception type for two different things.
  //  - statusCode == null -> the request never got an answer (no internet).
  //  - statusCode 500+    -> the server answered with an error of its own.
  if (error is AuthRetryableFetchException) {
    if (error.statusCode == null) {
      return 'Could not reach the server. Check your internet connection.';
    }
    return _serverErrorMessage(error.message);
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

/// Message for a 500-type error from Supabase Auth. [body] is the raw
/// response, usually JSON like {"code":500,"msg":"Error sending confirmation email"}.
String _serverErrorMessage(String body) {
  String detail = body;
  try {
    final json = jsonDecode(body);
    if (json is Map) {
      detail = (json['msg'] ?? json['message'] ?? json['error_description'] ?? body).toString();
    }
  } catch (_) {
    // Not JSON: keep the raw text.
  }

  if (detail.toLowerCase().contains('sending') && detail.toLowerCase().contains('email')) {
    return 'The server could not send the email. Check the SMTP settings in '
        'Supabase (Authentication -> Emails -> SMTP Settings).';
  }
  return 'The server had a problem: $detail';
}
