import 'package:flutter/material.dart';
import 'package:rental_app/shared/utils/dates.dart';

/// Looks like a text field; tapping it opens a calendar to pick a date.
///
/// The parent screen keeps the chosen date in its own state and passes it in
/// as [value]. If [onCleared] is given, an X button lets the user remove an
/// optional date.
class DateField extends StatelessWidget {
  const DateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.onCleared,
    this.helperText,
    this.errorText,
    this.firstDate,
    this.lastDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;
  final VoidCallback? onCleared;
  final String? helperText;
  final String? errorText;
  final DateTime? firstDate;
  final DateTime? lastDate;

  Future<void> _pick(BuildContext context) async {
    final now = today();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? now,
      firstDate: firstDate ?? DateTime(now.year - 20),
      lastDate: lastDate ?? DateTime(now.year + 20),
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _pick(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          errorText: errorText,
          prefixIcon: const Icon(Icons.calendar_month_rounded),
          suffixIcon: value != null && onCleared != null
              ? IconButton(
                  tooltip: 'Clear',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onCleared,
                )
              : null,
        ),
        isEmpty: value == null,
        child: value == null ? null : Text(formatDate(value!)),
      ),
    );
  }
}
