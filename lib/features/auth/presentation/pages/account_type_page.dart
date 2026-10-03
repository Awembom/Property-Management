import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:rental_app/core/router/app_router.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/features/auth/data/account_type.dart';
import 'package:rental_app/shared/widgets/app_card.dart';

/// Sign-up, step 1 of 2: "How will you use the app?" The next screen asks
/// for name, username and password.
class AccountTypePage extends StatefulWidget {
  const AccountTypePage({super.key});

  @override
  State<AccountTypePage> createState() => _AccountTypePageState();
}

class _AccountTypePageState extends State<AccountTypePage> {
  AccountType? _selected;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Create account')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            const _StepDots(step: 1),
            const SizedBox(height: 20),
            Text('How will you use the app?', style: text.headlineSmall),
            const SizedBox(height: 6),
            Text(
              'Choose the one that fits you best.',
              style: text.bodyMedium?.copyWith(color: AppColors.muted),
            ),
            const SizedBox(height: 24),
            for (final type in AccountType.values)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: AccountTypeCard(
                  type: type,
                  selected: _selected == type,
                  onTap: () => setState(() => _selected = type),
                ),
              ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _selected == null
                  ? null
                  : () => context.push(AppRoutes.signupDetailsFor(_selected!)),
              child: const Text('Continue'),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => context.go(AppRoutes.login),
              child: const Text('Already have an account? Log in'),
            ),
          ],
        ),
      ),
    );
  }
}

/// One account type: icon in a coloured circle, title, explanation; an
/// orange border and tick when selected.
class AccountTypeCard extends StatelessWidget {
  const AccountTypeCard({super.key, required this.type, required this.selected, required this.onTap});

  final AccountType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selected ? AppColors.primary : Colors.transparent, width: 2),
      ),
      child: AppCard(
        onTap: onTap,
        color: selected ? AppColors.soft(AppColors.primary).withValues(alpha: 0.08) : null,
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.soft(type.color)),
              child: Icon(type.icon, color: type.color, size: 26),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(type.label, style: text.titleMedium),
                  const SizedBox(height: 2),
                  Text(type.description, style: text.bodySmall),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: selected ? AppColors.primary : AppColors.line,
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

/// "Step 1 of 2" as two little bars.
class _StepDots extends StatelessWidget {
  const _StepDots({required this.step});

  final int step;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 1; i <= 2; i++) ...[
          Expanded(
            child: Container(
              height: 5,
              decoration: BoxDecoration(
                color: i <= step ? AppColors.primary : AppColors.line,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 8),
        ],
      ],
    );
  }
}

/// Exposed so step 2 shows the same progress bars.
class SignupStepDots extends StatelessWidget {
  const SignupStepDots({super.key, required this.step});

  final int step;

  @override
  Widget build(BuildContext context) => _StepDots(step: step);
}
