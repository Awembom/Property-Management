import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/shared/utils/phone.dart';

void main() {
  test('every number is saved as +237 and 9 digits', () {
    expect(normalizePhone('677000111'), '+237677000111');
    expect(normalizePhone('677 00 01 11'), '+237677000111');
    expect(normalizePhone('+237 677 000 111'), '+237677000111');
    expect(normalizePhone(''), isNull);
  });

  test('saved numbers are shown the Cameroon way and edited without +237', () {
    expect(formatPhone('+237677000111'), '+237 677 00 01 11');
    expect(phoneLocalPart('+237677000111'), '677000111');
    expect(phoneLocalPart(null), '');
  });

  test('9 digits starting with 6 or 2', () {
    final required = phoneValidator(required: true);
    final optional = phoneValidator(required: false);
    expect(required(''), 'Enter your phone number');
    expect(optional(''), isNull);
    expect(required('67700011'), 'Enter the 9 digits after +237');
    expect(required('977000111'), 'Cameroon numbers start with 6 or 2');
    expect(required('677000111'), isNull);
    expect(required('222000111'), isNull);
  });
}
