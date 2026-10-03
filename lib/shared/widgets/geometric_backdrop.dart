import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// The app's background: the plain background colour with a few faint
/// geometric shapes (circles, a ring, a rounded square, dots) in the brand
/// colours. Kept very light so it never competes with the content.
///
/// Every page gets it through AppRoute (app_router.dart); screens and app
/// bars are transparent (app_theme.dart) so it shows through.
class GeometricBackdrop extends StatelessWidget {
  const GeometricBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return CustomPaint(
      painter: _ShapesPainter(dark: dark),
      // Painted once and cached: the shapes never change while scrolling.
      isComplex: true,
      child: child,
    );
  }
}

class _ShapesPainter extends CustomPainter {
  const _ShapesPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    // A little stronger on dark backgrounds, where faint colours vanish.
    final k = dark ? 1.6 : 1.0;
    Paint fill(Color c, double alpha) => Paint()..color = c.withValues(alpha: alpha * k);
    Paint stroke(Color c, double alpha, double width) => Paint()
      ..color = c.withValues(alpha: alpha * k)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    canvas.drawRect(Offset.zero & size, Paint()..color = dark ? AppColors.darkBackground : AppColors.background);

    // Top right: a big soft circle half off the screen, and a thin ring.
    canvas.drawCircle(Offset(w * 0.98, h * 0.02), w * 0.36, fill(AppColors.primary, 0.07));
    canvas.drawCircle(Offset(w * 0.78, h * 0.13), w * 0.2, stroke(AppColors.accent, 0.12, 1.5));

    // Left, middle: a small outlined triangle.
    final triangle = Path()
      ..moveTo(w * 0.05, h * 0.47)
      ..lineTo(w * 0.12, h * 0.44)
      ..lineTo(w * 0.11, h * 0.515)
      ..close();
    canvas.drawPath(triangle, stroke(AppColors.primary, 0.16, 1.4));

    // Right: a small filled dot.
    canvas.drawCircle(Offset(w * 0.93, h * 0.55), 5, fill(AppColors.accent, 0.14));

    // Bottom right: a little grid of dots.
    final dots = fill(AppColors.primary, 0.16);
    for (var row = 0; row < 3; row++) {
      for (var col = 0; col < 4; col++) {
        canvas.drawCircle(Offset(w * 0.72 + col * 14, h * 0.72 + row * 14), 2, dots);
      }
    }

    // Bottom left: a large rounded square, turned a little, half off screen.
    canvas.save();
    canvas.translate(w * 0.02, h * 0.9);
    canvas.rotate(math.pi / 9);
    final side = w * 0.42;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromCenter(center: Offset.zero, width: side, height: side), Radius.circular(side * 0.22)),
      fill(AppColors.accent, 0.05),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_ShapesPainter old) => old.dark != dark;
}
