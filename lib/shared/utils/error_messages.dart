import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:rental_app/core/offline/network_errors.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any error into a short message that is safe to show to users.
/// The full technical error is also printed to the `flutter run` console.
///
/// Supabase Auth errors carry a `code`; the full list is at
/// https://supabase.com/docs/guides/auth/debugging/error-codes
String friendlyErrorMessage(Object error) {
  debugPrint('Error shown to user: $error');

  // Offline: nothing saved on the phone for this screen yet.
  if (error is OfflineException) {
    return 'You\'re offline, and this hasn\'t been saved on this phone yet. '
        'It will be once you\'re back online.';
  }

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
        return 'Wrong username or password.';
      case 'user_already_exists':
        return 'That username is taken. Choose another one.';
      case 'same_password':
        return 'Choose a password that is different from the old one.';
      case 'email_not_confirmed':
        return 'This account is waiting for email confirmation. Switch off '
            '"Confirm email" in Supabase (Authentication -> Sign In / Providers -> Email).';
      case 'email_address_invalid':
        // Supabase refused the hidden address behind usernames: see
        // kUsernameEmailDomain in features/auth/data/username.dart.
        return 'The server refused the account address. The app admin must '
            'change the username domain (kUsernameEmailDomain).';
      case 'over_request_rate_limit':
        return 'Too many attempts. Please wait a few minutes and try again.';
      case 'weak_password':
        return error.message;
    }
    return error.message;
  }
  if (error is PostgrestException) {
    // Postgres error codes: https://www.postgresql.org/docs/current/errcodes-appendix.html
    switch (error.code) {
      case '23505': // unique_violation: the message names the constraint
        if (error.message.contains('apartments_property_id_name_key')) {
          return 'An apartment with this name already exists in this property.';
        }
        if (error.message.contains('bill_types_property_name_key')) {
          return 'A bill type with this name already exists.';
        }
        return 'This already exists.';
      case '42501': // insufficient_privilege (blocked by RLS or grants)
        return 'You don\'t have permission to do this.';
      // The app asked for a table (PGRST205) or function (PGRST202) that the
      // database doesn't have: a migration in supabase/migrations wasn't run.
      case 'PGRST205':
      case 'PGRST202':
        return 'The database is missing an update. Run the newest files from '
            'supabase/migrations in the Supabase SQL editor.';
    }
    // Our database functions raise readable messages (e.g. the last-owner rule).
    return error.message;
  }
  if (error is StateError) {
    // Thrown by our own repositories with a readable message, e.g.
    // "Only owners can remove members."
    return error.message;
  }
  // Changes (payments, bills...) need a connection; only ticket messages
  // and receipt confirmations wait in the outbox.
  if (isNetworkError(error)) {
    return 'You\'re offline. Connect to the internet to do this.';
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
