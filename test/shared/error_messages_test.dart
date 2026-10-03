import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/shared/utils/error_messages.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('no response at all = internet problem', () {
    expect(
      friendlyErrorMessage(
        AuthRetryableFetchException(
          message: 'SocketException: Failed host lookup',
        ),
      ),
      contains('internet'),
    );
  });

  test('server 500 while sending email = SMTP problem, not internet', () {
    final message = friendlyErrorMessage(
      AuthRetryableFetchException(
        message: '{"code":500,"error_code":"unexpected_failure","msg":"Error sending confirmation email"}',
        statusCode: '500',
      ),
    );
    expect(message, contains('SMTP'));
    expect(message, isNot(contains('internet')));
  });

  test('other server errors show the server message', () {
    expect(
      friendlyErrorMessage(
        AuthRetryableFetchException(
          message: '{"msg":"Database error saving new user"}',
          statusCode: '500',
        ),
      ),
      'The server had a problem: Database error saving new user',
    );
  });

  test('missing table = a migration was not run', () {
    expect(
      friendlyErrorMessage(
        const PostgrestException(
          message: "Could not find the table 'public.apartment_rents' in the schema cache",
          code: 'PGRST205',
        ),
      ),
      contains('supabase/migrations'),
    );
  });
}
