import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';

void main() {
  test('username rules (same as the database)', () {
    expect(validateUsername(''), isNotNull);
    expect(validateUsername('ab'), isNotNull); // too short
    expect(validateUsername('tina k'), isNotNull); // space
    expect(
      validateUsername('_tina'),
      isNotNull,
    ); // must start with letter/digit
    expect(validateUsername('tina@x'), isNotNull);
    expect(validateUsername('a' * 31), isNotNull);
    expect(validateUsername('  Tina.K_2 '), isNull); // tidied to tina.k_2
  });

  test('login only checks that something was typed', () {
    expect(validateUsernameEntered('  '), isNotNull);
    expect(validateUsernameEntered('x'), isNull);
  });

  test('new password needs 8+ characters', () {
    expect(validateNewPassword('1234567'), isNotNull);
    expect(validateNewPassword('12345678'), isNull);
  });

  test('full name', () {
    expect(validateFullName('   '), isNotNull);
    expect(validateFullName('Jane Doe'), isNull);
  });
}
