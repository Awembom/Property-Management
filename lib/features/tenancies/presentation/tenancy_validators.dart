import 'package:rental_app/shared/utils/money.dart';

/// Form validators for tenancy screens. Each returns an error message, or
/// null when the value is fine.

String? validateTenantName(String? value) {
  if ((value?.trim() ?? '').isEmpty) return 'Enter the tenant\'s name';
  return null;
}

/// Email is optional for tenants, but must look right if given.
String? validateOptionalEmail(String? value) {
  final email = value?.trim() ?? '';
  if (email.isEmpty) return null;
  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
    return 'Enter a valid email, or leave it empty';
  }
  return null;
}

/// Returns a validator for a rent amount in [currency].
String? Function(String?) rentAmountValidator(String currency) {
  return (value) {
    final amount = parseMoney(value ?? '', currency);
    if (amount == null) return 'Enter an amount, e.g. 50000';
    if (amount <= 0) return 'Rent must be more than zero';
    return null;
  };
}

/// '' -> null, '  text ' -> 'text'.
String? trimToNull(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}
