import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

/// Thrown when the phone is offline and the data was never saved on it
/// (e.g. a screen nobody opened while online).
class OfflineException implements Exception {
  const OfflineException();

  @override
  String toString() => 'OfflineException';
}

/// Did [error] happen because the server couldn't be reached (no internet,
/// bad signal), rather than because the server said no?
bool isNetworkError(Object error) {
  if (error is OfflineException ||
      error is SocketException ||
      error is TimeoutException ||
      error is HandshakeException ||
      error is http.ClientException) {
    return true;
  }
  // statusCode null = no answer at all (see error_messages.dart).
  if (error is AuthRetryableFetchException) return error.statusCode == null;
  final text = error.toString();
  return text.contains('SocketException') || text.contains('Failed host lookup');
}
