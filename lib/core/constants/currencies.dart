/// Currencies a property can use. Every amount in a property is stored in
/// the smallest unit of its currency (see CLAUDE.md), so the currency is
/// chosen once, when the property is created.
///
/// Add more here if needed: code must be the 3-letter ISO 4217 code.
const Map<String, String> kCurrencies = {
  'XAF': 'Central African CFA franc',
  'XOF': 'West African CFA franc',
  'NGN': 'Nigerian naira',
  'GHS': 'Ghanaian cedi',
  'KES': 'Kenyan shilling',
  'ZAR': 'South African rand',
  'USD': 'US dollar',
  'EUR': 'Euro',
  'GBP': 'British pound',
};

/// How many digits after the decimal point each currency uses.
/// CFA francs have no cents, so 150000 XAF is stored as 150000.
/// The others have cents: 25.50 USD is stored as 2550.
const Map<String, int> kCurrencyDecimals = {
  'XAF': 0,
  'XOF': 0,
};

/// Decimal digits for [currency]; 2 unless listed in [kCurrencyDecimals].
int currencyDecimals(String currency) => kCurrencyDecimals[currency] ?? 2;
