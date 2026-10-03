import 'package:flutter/material.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:url_launcher/url_launcher.dart';

/// Every phone number in the app is a Cameroon number (decided 2026-10-03):
/// people type the 9 digits, the app adds +237 and saves '+237677000111'.
const kPhonePrefix = '+237';

/// The 9 digits someone types -> '+237677000111'; empty -> null.
/// Spaces and dashes are ignored; a pasted +237 or 237 is accepted too.
String? normalizePhone(String typed) {
  final digits = phoneLocalPart(typed);
  return digits.isEmpty ? null : '$kPhonePrefix$digits';
}

/// A saved number -> the 9 digits to show in the field (without +237).
String phoneLocalPart(String? phone) {
  var digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  if (digits.startsWith('237') && digits.length == 12) digits = digits.substring(3);
  return digits;
}

/// '+237677000111' -> '+237 677 00 01 11' (how Cameroon numbers are written).
String formatPhone(String phone) {
  final d = phoneLocalPart(phone);
  if (d.length != 9) return phone;
  return '$kPhonePrefix ${d.substring(0, 3)} ${d.substring(3, 5)} ${d.substring(5, 7)} ${d.substring(7)}';
}

/// 9 digits, starting with 6 (mobile) or 2 (landline). [required]: may it
/// be left empty?
String? Function(String?) phoneValidator({required bool required}) {
  return (value) {
    final digits = phoneLocalPart(value);
    if (digits.isEmpty) return required ? 'Enter your phone number' : null;
    if (digits.length != 9) return 'Enter the 9 digits after +237';
    if (!RegExp(r'^[26]').hasMatch(digits)) return 'Cameroon numbers start with 6 or 2';
    return null;
  };
}

/// Opens the phone's dialer with [number] filled in (the person still taps
/// the call button there). Shows a message if the phone can't do that.
Future<void> callNumber(BuildContext context, String number) async {
  // Keep digits and a leading +; spaces and dashes are fine to drop.
  final cleaned = number.replaceAll(RegExp(r'[^0-9+]'), '');
  final opened = await launchUrl(Uri(scheme: 'tel', path: cleaned));
  if (!opened && context.mounted) {
    showError(context, StateError('This phone can\'t make calls. The number is $number.'));
  }
}
