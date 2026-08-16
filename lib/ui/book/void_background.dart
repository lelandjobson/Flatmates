import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Slow, low-amplitude navy/purple wash over near-black. Loops forever.
class VoidBackground extends StatefulWidget {
  const VoidBackground({super.key});

  @override
  State<VoidBackground> createState() => _VoidBackgroundState();
}

class _VoidBackgroundState extends State<VoidBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 16),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return CustomPaint(
          painter: _VoidPainter(t: _controller.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _VoidPainter extends CustomPainter {
  _VoidPainter({required this.t});

  final double t;

  static const _black = Color(0xFF050508);
  static const _navyA = Color(0xFF0A1224);
  static const _navyB = Color(0xFF101A32);
  static const _purpleA = Color(0xFF160E28);
  static const _purpleB = Color(0xFF1C1234);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _black);

    final breathe = (math.sin(t * math.pi) * 0.5) + 0.5;
    final phase = t * math.pi;

    final navy = Color.lerp(_navyA, _navyB, breathe)!;
    final purple = Color.lerp(_purpleA, _purpleB, 1 - breathe)!;

    final cx = size.width * (0.42 + 0.08 * math.sin(phase));
    final cy = size.height * (0.38 + 0.10 * math.cos(phase * 0.7));
    final r = size.longestSide * (0.72 + 0.06 * math.sin(phase * 0.5));

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (cx / size.width) * 2 - 1,
            (cy / size.height) * 2 - 1,
          ),
          radius: r / size.longestSide,
          colors: [
            navy.withValues(alpha: 0.55),
            _black.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Offset.zero & size),
    );

    final px = size.width * (0.62 + 0.07 * math.cos(phase * 0.85));
    final py = size.height * (0.58 + 0.08 * math.sin(phase * 0.6));
    final pr = size.longestSide * (0.64 + 0.05 * math.cos(phase * 0.4));

    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (px / size.width) * 2 - 1,
            (py / size.height) * 2 - 1,
          ),
          radius: pr / size.longestSide,
          colors: [
            purple.withValues(alpha: 0.42),
            _black.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 1.0],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant _VoidPainter oldDelegate) => oldDelegate.t != t;
}
