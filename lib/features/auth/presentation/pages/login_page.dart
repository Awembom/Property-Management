import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Login')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.home_work_rounded, size: 72),
              const SizedBox(height: 24),
              const Text(
                'Rental App',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text(
                'Manage properties, tenants, and payments in one place.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                // Placeholder: real email/password login comes in Phase 2.
                onPressed: () => context.go(AppRoutes.properties),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Continue'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
