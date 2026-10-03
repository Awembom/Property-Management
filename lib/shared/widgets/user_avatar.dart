import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// A round avatar with someone's initials ("Tina Tenant" -> "TT"), in a
/// colour that stays the same for the same name.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.name, this.size = 48});

  final String name;
  final double size;

  String get _initials {
    final words = name.trim().replaceAll('@', '').split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    final letters = words.take(2).map((w) => w.characters.first.toUpperCase()).join();
    return letters.isEmpty ? '?' : letters;
  }

  @override
  Widget build(BuildContext context) {
    final color = AppColors.forId(name);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: AppColors.gradientFor(color),
      ),
      child: Text(
        _initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
