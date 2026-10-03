import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';
import 'package:rental_app/shared/widgets/app_card.dart';
import 'package:rental_app/shared/widgets/icon_bubble.dart';

/// "Total collected this month" with an eye button. The amount starts hidden
/// (people often open the app where others can see the screen); tapping the
/// eye shows it until the page is left.
class CollectedCard extends StatefulWidget {
  const CollectedCard({super.key, required this.amountText, this.label = 'Total collected this month'});

  /// e.g. "XAF 450,000" (or several currencies joined with " + ").
  final String amountText;
  final String label;

  @override
  State<CollectedCard> createState() => _CollectedCardState();
}

class _CollectedCardState extends State<CollectedCard> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AppCard(
      onTap: () => setState(() => _visible = !_visible),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      child: Row(
        children: [
          const IconBubble(icon: Icons.account_balance_wallet_rounded, color: AppColors.paid, size: 48),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label, style: text.bodySmall),
                const SizedBox(height: 2),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    _visible ? widget.amountText : '••••••',
                    key: ValueKey(_visible),
                    style: text.titleLarge?.copyWith(color: AppColors.paid, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: _visible ? 'Hide amount' : 'Show amount',
            icon: Icon(_visible ? Icons.visibility_off_rounded : Icons.visibility_rounded),
            onPressed: () => setState(() => _visible = !_visible),
          ),
        ],
      ),
    );
  }
}
