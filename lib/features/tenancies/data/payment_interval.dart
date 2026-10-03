/// How often a tenant pays rent, in months (`tenancies.payment_interval_months`).
///
/// Rent itself is always stored per month. The interval says how many months
/// the tenant usually pays at once, and rent reminders (Phase 11) follow it.
class PaymentInterval {
  PaymentInterval._();

  /// The choices shown as buttons. Anything else is "Custom".
  static const List<int> presets = [1, 3, 6, 12];

  /// Allowed range for a custom interval (the database checks the same).
  static const int minMonths = 1;
  static const int maxMonths = 24;

  static bool isPreset(int months) => presets.contains(months);

  /// 'Monthly', 'Every 3 months', 'Every 6 months', 'Yearly', 'Every 2 months'.
  static String label(int months) => switch (months) {
        1 => 'Monthly',
        12 => 'Yearly',
        _ => 'Every $months months',
      };

  /// '1 month', '3 months'.
  static String monthsText(int months) => months == 1 ? '1 month' : '$months months';
}
