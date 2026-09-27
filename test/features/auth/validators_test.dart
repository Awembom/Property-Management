import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/features/auth/presentation/validators.dart';

void main() {
  test('email', () {
    expect(validateEmail(''), isNotNull);
    expect(validateEmail('not-an-email'), isNotNull);
    expect(validateEmail('a@b'), isNotNull);
    expect(validateEmail('  jane@example.com  '), isNull);
  });

  test('new password needs 8+ characters', () {
    expect(validateNewPassword('1234567'), isNotNull);
    expect(validateNewPassword('12345678'), isNull);
  });

  test('signup code must be exactly 6 digits', () {
    expect(validateSignupCode('12345'), isNotNull);
    expect(validateSignupCode('12345a'), isNotNull);
    expect(validateSignupCode('123456'), isNull);
  });

  test('full name', () {
    expect(validateFullName('   '), isNotNull);
    expect(validateFullName('Jane Doe'), isNull);
  });
}
