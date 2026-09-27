import 'package:flutter/material.dart';
import 'package:rental_app/shared/utils/error_messages.dart';

/// Full-screen "something went wrong" message with a Try again button.
/// Used as the `error:` case of `AsyncValue.when(...)`.
class AsyncErrorView extends StatelessWidget {
  const AsyncErrorView({super.key, required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(friendlyErrorMessage(error), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
