import 'package:flutter/material.dart';

/// Every colour the app uses, in one place.
///
/// The look: a warm off-white background, white cards, one orange brand
/// colour ([primary]) with a blue [accent], and "meaning" colours for rent
/// status (green = paid, amber = due soon, red = overdue, blue = vacant).
class AppColors {
  AppColors._();

  // Brand
  static const Color primary = Color(0xFFE8743B); // warm orange
  static const Color primaryDark = Color(0xFFC85A24);
  static const Color accent = Color(0xFF1F6FAE); // deep blue

  // Neutrals (light theme)
  static const Color background = Color(0xFFF4F2EF);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF1F1F24); // main text
  static const Color muted = Color(0xFF85848B); // secondary text
  static const Color line = Color(0xFFE7E4DF); // borders

  // Neutrals (dark theme)
  static const Color darkBackground = Color(0xFF131316);
  static const Color darkSurface = Color(0xFF1E1E23);
  static const Color darkLine = Color(0xFF2E2E35);

  // Rent / apartment status
  static const Color paid = Color(0xFF1E9E5A); // green
  static const Color dueSoon = Color(0xFFE0A100); // amber
  static const Color overdue = Color(0xFFE5484D); // red
  static const Color vacant = Color(0xFF2F80ED); // blue
  static const Color ended = Color(0xFF8A8F98); // grey

  /// One colour per property (picked from its id, so it never changes).
  static const List<Color> palette = [
    Color(0xFFE8743B), // orange
    Color(0xFF1F6FAE), // blue
    Color(0xFF14917F), // teal
    Color(0xFFB4532A), // terracotta
    Color(0xFF5B5BD6), // indigo
    Color(0xFF3F8F3A), // green
    Color(0xFFC98A12), // amber
    Color(0xFF9B4D8C), // plum
  ];

  /// The same text always gives the same colour.
  static Color forId(String id) {
    // A simple, stable hash: String.hashCode is NOT guaranteed to be the same
    // between app runs, so we add up the character codes instead.
    final sum = id.codeUnits.fold<int>(0, (total, unit) => total + unit);
    return palette[sum % palette.length];
  }

  /// A diagonal gradient from [color] to a slightly darker shade.
  static LinearGradient gradientFor(Color color) {
    final hsl = HSLColor.fromColor(color);
    final darker = hsl.withLightness((hsl.lightness - 0.12).clamp(0.0, 1.0)).toColor();
    final lighter = hsl.withLightness((hsl.lightness + 0.06).clamp(0.0, 1.0)).toColor();
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [lighter, darker],
    );
  }

  /// A soft tinted background for chips and icon circles.
  static Color soft(Color color) => color.withValues(alpha: 0.13);

  /// The same tint, but solid (mixed onto the card colour), for card
  /// backgrounds: the background shapes must not show through cards.
  static Color solidSoft(BuildContext context, Color color) =>
      Color.alphaBlend(soft(color), Theme.of(context).colorScheme.surface);

  /// The soft shadow under cards.
  static List<BoxShadow> cardShadow(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const []
          : [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(0, 6),
              ),
            ];
}
