import 'package:flutter_test/flutter_test.dart';
import 'package:rental_app/shared/utils/money.dart';

void main() {
  group('formatMoney', () {
    test('CFA francs have no decimals', () {
      expect(formatMoney(150000, 'XAF'), 'XAF 150,000');
    });
    test('dollars show cents', () {
      expect(formatMoney(15000050, 'USD'), 'USD 150,000.50');
      expect(formatMoney(5, 'USD'), 'USD 0.05');
    });
  });

  group('parseMoney', () {
    test('accepts thousands separators and spaces', () {
      expect(parseMoney('150,000', 'XAF'), 150000);
      expect(parseMoney(' 150 000 ', 'XAF'), 150000);
    });
    test('converts to cents without rounding errors', () {
      expect(parseMoney('25.5', 'USD'), 2550);
      expect(
        parseMoney('0.29', 'USD'),
        29,
      ); // 0.29 * 100 is 28.999... as a double
      expect(parseMoney('100', 'USD'), 10000);
    });
    test('rejects invalid amounts', () {
      expect(parseMoney('', 'XAF'), isNull);
      expect(parseMoney('abc', 'USD'), isNull);
      expect(parseMoney('12.5', 'XAF'), isNull); // no decimals in XAF
      expect(parseMoney('1.234', 'USD'), isNull); // too many decimals
      expect(parseMoney('-5', 'USD'), isNull);
    });
    test('moneyToInput round-trips', () {
      expect(parseMoney(moneyToInput(2550, 'USD'), 'USD'), 2550);
      expect(moneyToInput(2550, 'USD'), '25.50');
      expect(moneyToInput(150000, 'XAF'), '150000');
    });
  });
}
