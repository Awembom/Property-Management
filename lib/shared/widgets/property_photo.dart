import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// Stands in for a property photo until real photos are added: a painted
/// "sky" in the property's colour with a simple house and trees.
class PropertyPhoto extends StatelessWidget {
  const PropertyPhoto({
    super.key,
    required this.seed,
    this.height = 140,
    this.borderRadius = 18,
    this.child,
    this.color,
  });

  /// Usually the property id: picks the colour, so it never changes.
  final String seed;

  /// Use this colour instead of the one picked from [seed].
  final Color? color;
  final double height;
  final double borderRadius;

  /// Shown on top (e.g. a status label).
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final color = this.color ?? AppColors.forId(seed);
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CustomPaint(painter: _HousePainter(color)),
            if (child != null) Padding(padding: const EdgeInsets.all(10), child: child),
          ],
        ),
      ),
    );
  }
}

class _HousePainter extends CustomPainter {
  _HousePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hsl = HSLColor.fromColor(color);

    // Sky: a light tint of the colour fading to warm white.
    final sky = Rect.fromLTWH(0, 0, w, h);
    canvas.drawRect(
      sky,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            hsl.withLightness(0.86).withSaturation(0.55).toColor(),
            const Color(0xFFFBF7F2),
          ],
        ).createShader(sky),
    );

    // Sun
    final small = math.min(w, h);
    canvas.drawCircle(Offset(w * 0.85, h * 0.2), small * 0.09,
        Paint()..color = Colors.white.withValues(alpha: 0.8));

    // Lawn
    final lawn = Path()
      ..moveTo(0, h * 0.8)
      ..quadraticBezierTo(w * 0.5, h * 0.72, w, h * 0.8)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();
    canvas.drawPath(lawn, Paint()..color = const Color(0xFF8DBB6A));

    // House body, centred, scaled to the height.
    final houseW = math.min(w * 0.42, h * 0.95);
    final houseH = houseW * 0.55;
    final left = (w - houseW) / 2;
    final bottom = h * 0.82;
    final top = bottom - houseH;
    final wall = hsl.withLightness(0.96).withSaturation(0.2).toColor();
    final roof = hsl.withLightness(0.42).toColor();
    canvas.drawRect(Rect.fromLTRB(left, top, left + houseW, bottom), Paint()..color = wall);

    // Roof
    final roofPath = Path()
      ..moveTo(left - houseW * 0.08, top + 2)
      ..lineTo(left + houseW / 2, top - houseH * 0.6)
      ..lineTo(left + houseW * 1.08, top + 2)
      ..close();
    canvas.drawPath(roofPath, Paint()..color = roof);

    // Door and windows
    final glass = Paint()..color = hsl.withLightness(0.72).withSaturation(0.5).toColor();
    final doorW = houseW * 0.16;
    canvas.drawRect(
        Rect.fromLTWH(left + houseW / 2 - doorW / 2, bottom - houseH * 0.55, doorW, houseH * 0.55),
        Paint()..color = roof);
    final winW = houseW * 0.18;
    final winH = houseH * 0.28;
    for (final x in [left + houseW * 0.12, left + houseW * 0.70]) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, top + houseH * 0.22, winW, winH), const Radius.circular(2)),
          glass);
    }

    // Trees on both sides
    final leaf = Paint()..color = const Color(0xFF5E9A4A);
    final trunk = Paint()..color = const Color(0xFF7A5A3A);
    for (final x in [w * 0.14, w * 0.88]) {
      final r = small * 0.1;
      canvas.drawRect(Rect.fromLTWH(x - 2, bottom - r * 1.3, 4, r * 1.3), trunk);
      canvas.drawCircle(Offset(x, bottom - r * 1.8), r, leaf);
    }
  }

  @override
  bool shouldRepaint(_HousePainter old) => old.color != color;
}
