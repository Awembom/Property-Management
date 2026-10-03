import 'package:rental_app/features/tenancies/data/payment_interval.dart';
import 'package:rental_app/shared/utils/dates.dart';
import 'package:rental_app/shared/utils/money.dart';

/// The tenancy agreement the tenant accepts in the app.
///
/// Owners write it themselves (per property, optionally per unit) in the
/// agreement editor; until then [defaultAgreementTemplate] is used. The text
/// is plain: a line starting with "# " is a heading, and these fields are
/// filled in for each tenant:
const agreementFields = {
  '{tenant}': 'Tenant\'s name',
  '{unit}': 'Apartment',
  '{property}': 'Property',
  '{rent}': 'Monthly rent',
  '{pays}': 'How often rent is paid',
  '{start}': 'Start date',
  '{end}': 'End date',
};

/// A simple starting text. Not legal advice: owners should adapt it to
/// local law and their own rules.
const defaultAgreementTemplate = '''# 1. The home
{property} rents Apartment {unit} to {tenant} from {start} to {end}.

# 2. Rent
The rent is {rent} per month, paid {pays}, in advance. Rent is due on the first day of the period it covers. Every payment gets a receipt in the app.

# 3. Bills
Water, electricity and other bills are paid by the tenant when the landlord shares them in the app, unless the landlord waives them.

# 4. Looking after the home
The tenant keeps the home clean and in good condition and reports any damage or repairs needed through the app as soon as possible. The landlord carries out repairs that are not caused by the tenant.

# 5. Changes and visits
The tenant does not make major changes to the home without the landlord's agreement. The landlord gives notice before visiting, except in an emergency.

# 6. Ending the tenancy
Either side gives notice before the tenancy ends. The tenant returns the keys and leaves the home in the condition it was received, apart from normal wear.''';

/// The agreement as sections (heading, text): first a summary made from the
/// tenancy, then the owner's [template] (or the default) with the fields
/// filled in.
List<(String, String)> agreementSections({
  required String propertyName,
  required String apartmentName,
  required String tenantName,
  required int monthlyRent,
  required String currency,
  required int paymentIntervalMonths,
  required DateTime startDate,
  DateTime? endDate,
  String? template,
}) {
  final pays = PaymentInterval.label(paymentIntervalMonths).toLowerCase();
  final values = {
    '{tenant}': tenantName,
    '{unit}': apartmentName,
    '{property}': propertyName,
    '{rent}': formatMoney(monthlyRent, currency),
    '{pays}': pays,
    '{start}': formatDate(startDate),
    '{end}': endDate == null ? 'no fixed end date' : formatDate(endDate),
  };
  return [
    (
      'Summary',
      'Tenant: $tenantName\n'
          'Home: Apartment $apartmentName, $propertyName\n'
          'Rent: ${formatMoney(monthlyRent, currency)} per month, paid $pays\n'
          'Starts: ${formatDate(startDate)}'
          '${endDate == null ? '' : '\nEnds: ${formatDate(endDate)}'}',
    ),
    ...parseAgreement(fillAgreementFields(template ?? defaultAgreementTemplate, values)),
  ];
}

/// Replaces {tenant}, {rent}... with [values].
String fillAgreementFields(String text, Map<String, String> values) {
  var result = text;
  values.forEach((field, value) => result = result.replaceAll(field, value));
  return result;
}

/// Splits agreement text into (heading, text) sections at lines starting
/// with "# ". Text before the first heading gets an empty heading.
List<(String, String)> parseAgreement(String text) {
  final sections = <(String, String)>[];
  var heading = '';
  final body = <String>[];
  void flush() {
    final content = body.join('\n').trim();
    if (heading.isNotEmpty || content.isNotEmpty) sections.add((heading, content));
    body.clear();
  }

  for (final line in text.split('\n')) {
    if (line.startsWith('# ')) {
      flush();
      heading = line.substring(2).trim();
    } else {
      body.add(line);
    }
  }
  flush();
  return sections;
}
