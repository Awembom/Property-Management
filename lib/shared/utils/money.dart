import 'package:intl/intl.dart';
import 'package:rental_app/core/constants/currencies.dart';

// Money is always an `int` in the currency's smallest unit (see CLAUDE.md).
// These helpers convert between that and what people read and type, using
// whole-number maths only, so there are never floating-point rounding errors.

/// 15000050, 'USD' -> 'USD 150,000.50'.   150000, 'XAF' -> 'XAF 150,000'.
String formatMoney(int minorUnits, String currency) {
  final decimals = currencyDecimals(currency);
  final factor = _powerOfTen(decimals);
  final sign = minorUnits < 0 ? '-' : '';
  final absolute = minorUnits.abs();

  final whole = NumberFormat('#,##0').format(absolute ~/ factor);
  if (decimals == 0) return '$currency $sign$whole';

  final fraction = (absolute % factor).toString().padLeft(decimals, '0');
  return '$currency $sign$whole.$fraction';
}

/// The number as someone would type it, for pre-filling a form field:
/// 15000050, 'USD' -> '150000.50'.
String moneyToInput(int minorUnits, String currency) {
  final decimals = currencyDecimals(currency);
  if (decimals == 0) return '$minorUnits';
  final factor = _powerOfTen(decimals);
  final fraction = (minorUnits % factor).toString().padLeft(decimals, '0');
  return '${minorUnits ~/ factor}.$fraction';
}

/// What someone typed -> smallest units, or null if it isn't a valid amount.
/// '150,000' XAF -> 150000.  '25.5' USD -> 2550.  '25.555' USD -> null.
int? parseMoney(String text, String currency) {
  final decimals = currencyDecimals(currency);
  // Allow thousands separators and spaces: "150 000" or "150,000".
  final cleaned = text.replaceAll(RegExp(r'[\s,]'), '');
  final pattern = decimals == 0
      ? RegExp(r'^\d+$')
      : RegExp('^(\\d+)(\\.(\\d{1,$decimals}))?\$');
  final match = pattern.firstMatch(cleaned);
  if (match == null) return null;
  if (decimals == 0) return int.tryParse(cleaned);

  final whole = int.parse(match.group(1)!);
  final fraction = (match.group(3) ?? '').padRight(decimals, '0');
  return whole * _powerOfTen(decimals) + int.parse(fraction);
}

int _powerOfTen(int exponent) {
  var result = 1;
  for (var i = 0; i < exponent; i++) {
    result *= 10;
  }
  return result;
}
