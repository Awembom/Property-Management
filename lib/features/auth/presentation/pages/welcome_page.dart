import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/shared/widgets/property_photo.dart';

/// The first screen when logged out: a big picture, one sentence about the
/// app, "Get started" (create an account) and "I already have an account".
class WelcomePage extends StatelessWidget {
  const WelcomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    const Positioned.fill(
                      child: PropertyPhoto(
                        seed: 'welcome',
                        color: AppColors.primary,
                        height: double.infinity,
                        borderRadius: 28,
                      ),
                    ),
                    Positioned(
                      left: 20,
                      top: 20,
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(Icons.home_work_rounded, color: Colors.white),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            'Rental App',
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              Text(
                'Simplify property management in one app',
                textAlign: TextAlign.center,
                style: text.headlineSmall?.copyWith(height: 1.25),
              ),
              const SizedBox(height: 10),
              Text(
                'Rent collection, receipts, tenants and your team, all in one place.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(color: AppColors.muted),
              ),
              const SizedBox(height: 28),
              FilledButton.icon(
                onPressed: () => context.push(AppRoutes.signup),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Get started'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => context.push(AppRoutes.login),
                child: const Text('I already have an account'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}
