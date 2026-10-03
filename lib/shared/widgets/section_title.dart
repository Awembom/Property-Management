import 'package:flutter/material.dart';

/// A bold heading between groups of cards, e.g. "Current tenant".
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 22, 2, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, fontSize: 17),
            ),
          ),
          ?trailing, // "?" = only added when not null
        ],
      ),
    );
  }
}
