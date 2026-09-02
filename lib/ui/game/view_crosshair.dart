import 'package:flutter/material.dart';

/// Center-fixed pointer: a thick-stroke circle, scaled down.
class ViewCrosshair extends StatelessWidget {
  const ViewCrosshair({
    super.key,
    this.diameter = 14,
    this.strokeWidth = 3.5,
    this.color = const Color(0xF2FFFFFF),
  });

  final double diameter;
  final double strokeWidth;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: CustomPaint(
          size: Size.square(diameter + strokeWidth),
          painter: _CrosshairPainter(
            diameter: diameter,
            strokeWidth: strokeWidth,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  _CrosshairPainter({
    required this.diameter,
    required this.strokeWidth,
    required this.color,
  });

  final double diameter;
  final double strokeWidth;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;
    canvas.drawCircle(Offset(size.width * 0.5, size.height * 0.5), diameter * 0.5, paint);
  }

  @override
  bool shouldRepaint(covariant _CrosshairPainter oldDelegate) {
    return oldDelegate.diameter != diameter ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.color != color;
  }
}
