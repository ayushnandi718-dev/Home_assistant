import 'package:aura_hub/core/theme/aura_colors.dart';
import 'package:flutter/material.dart';

/// A small brand mark drawn in code so it scales cleanly and ships no assets.
class AuraLogo extends StatelessWidget {
  const AuraLogo({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: const _AuraMarkPainter()),
    );
  }
}

class _AuraMarkPainter extends CustomPainter {
  const _AuraMarkPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    final double side = size.shortestSide;
    final Offset center = size.center(Offset.zero);

    final Paint background = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: <Color>[AuraColors.primary, AuraColors.secondary],
      ).createShader(bounds);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        bounds,
        Radius.circular(side * 0.30),
      ),
      background,
    );

    final Paint cut = Paint()
      ..color = AuraColors.background
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = side * 0.075;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: side * 0.26),
      -2.35,
      3.55,
      false,
      cut,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: side * 0.15),
      0.75,
      3.5,
      false,
      cut,
    );

    canvas.drawCircle(
      center,
      side * 0.045,
      Paint()..color = AuraColors.background,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
