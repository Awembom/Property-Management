import 'package:flutter/material.dart';
import 'package:rental_app/shared/utils/error_messages.dart';

/// Shows a short message at the bottom of the screen.
void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// Shows any error as a friendly red message.
void showError(BuildContext context, Object error) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(friendlyErrorMessage(error)),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
}
