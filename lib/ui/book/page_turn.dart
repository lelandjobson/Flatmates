import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Perspective Y-rotation of a leaf around its left or right edge.
///
/// [progress] 0 = face-on showing [front]; 1 = flipped 180° showing [back].
/// After 90°, the child is swapped and pre-rotated so type is not mirrored.
class TurningLeaf extends StatelessWidget {
  const TurningLeaf({
    super.key,
    required this.progress,
    required this.front,
    required this.back,
    this.hingeLeft = true,
    this.perspective = 0.0012,
  });

  final double progress;
  final Widget front;
  final Widget back;

  /// `true` hinges on the left edge (forward page turn / front cover).
  final bool hingeLeft;
  final double perspective;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    final angle = (hingeLeft ? -math.pi : math.pi) * t;
    final showFront = t < 0.5;
    final alignment =
        hingeLeft ? Alignment.centerLeft : Alignment.centerRight;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, perspective)
      ..rotateY(angle);

    final shade = math.sin(t * math.pi) * 0.32;

    Widget face = showFront
        ? front
        : Transform(
            alignment: Alignment.center,
            transform: Matrix4.rotationY(math.pi),
            child: back,
          );

    face = Stack(
      fit: StackFit.expand,
      children: [
        face,
        IgnorePointer(
          child: ColoredBox(
            color: Colors.black.withValues(alpha: shade.clamp(0.0, 1.0)),
          ),
        ),
      ],
    );

    return Transform(
      alignment: alignment,
      transform: matrix,
      filterQuality: FilterQuality.medium,
      child: face,
    );
  }
}

/// Closed-book 180° flip around the vertical center, as a shallow 3D volume.
///
/// Both covers exist as opposite faces of a slab; spine and fore-edge stay
/// visible at 90° so it reads as a book, not a card. [progress] 0 = [back]
/// toward camera, 1 = [front] toward camera.
class BookVolumeFlip extends StatelessWidget {
  const BookVolumeFlip({
    super.key,
    required this.progress,
    required this.size,
    required this.front,
    required this.back,
    this.thickness = 18,
    this.perspective = 0.0022,
  });

  final double progress;
  final Size size;
  final Widget front;
  final Widget back;
  final double thickness;
  final double perspective;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    // Start showing the back (π) and rotate to the front (2π).
    final angle = math.pi * (1 + t);
    final depth = thickness;
    final w = size.width;
    final h = size.height;

    final matrix = Matrix4.identity()
      ..setEntry(3, 2, perspective)
      ..rotateY(angle);

    final facingBack = t < 0.5;

    final frontFace = _face(
      transform: Matrix4.identity()..translate(0.0, 0.0, depth / 2),
      child: SizedBox(width: w, height: h, child: front),
    );
    final backFace = _face(
      transform: Matrix4.identity()
        ..translate(0.0, 0.0, -depth / 2)
        ..rotateY(math.pi),
      child: SizedBox(width: w, height: h, child: back),
    );
    final spine = _face(
      transform: Matrix4.identity()
        ..translate(-w / 2, 0.0, 0.0)
        ..rotateY(math.pi / 2),
      child: SizedBox(
        width: depth,
        height: h,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFF0C0A14),
                Color(0xFF1A1630),
                Color(0xFF0C0A14),
              ],
            ),
          ),
        ),
      ),
    );
    final foreEdge = _face(
      transform: Matrix4.identity()
        ..translate(w / 2, 0.0, 0.0)
        ..rotateY(-math.pi / 2),
      child: SizedBox(
        width: depth,
        height: h,
        child: CustomPaint(painter: _ForeEdgePainter()),
      ),
    );
    final top = _face(
      transform: Matrix4.identity()
        ..translate(0.0, -h / 2, 0.0)
        ..rotateX(-math.pi / 2),
      child: SizedBox(
        width: w,
        height: depth,
        child: const ColoredBox(color: Color(0xFFC4B49A)),
      ),
    );
    final bottom = _face(
      transform: Matrix4.identity()
        ..translate(0.0, h / 2, 0.0)
        ..rotateX(math.pi / 2),
      child: SizedBox(
        width: w,
        height: depth,
        child: const ColoredBox(color: Color(0xFF1A1620)),
      ),
    );

    // Flutter does not depth-sort; paint far cover first, then the slab, then near.
    final faces = <Widget>[
      if (facingBack) frontFace else backFace,
      top,
      bottom,
      spine,
      foreEdge,
      if (facingBack) backFace else frontFace,
    ];

    return Transform(
      alignment: Alignment.center,
      transform: matrix,
      filterQuality: FilterQuality.medium,
      child: SizedBox(
        width: w,
        height: h,
        child: Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: faces,
        ),
      ),
    );
  }

  Widget _face({required Matrix4 transform, required Widget child}) {
    return Transform(
      alignment: Alignment.center,
      transform: transform,
      filterQuality: FilterQuality.medium,
      child: child,
    );
  }
}

class _ForeEdgePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFE8DCC8),
    );
    final line = Paint()
      ..color = const Color(0xFFC4B49A)
      ..strokeWidth = 1;
    final n = math.max(8, (size.width / 1.6).round());
    for (var i = 1; i < n; i++) {
      final x = size.width * i / n;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), line);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.18),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.22),
          ],
          stops: const [0, 0.5, 1],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
