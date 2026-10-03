import 'package:flutter/material.dart';
import 'package:rental_app/shared/widgets/snackbars.dart';
import 'package:url_launcher/url_launcher.dart';

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
