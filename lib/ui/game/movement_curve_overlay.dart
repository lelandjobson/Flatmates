import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/flatmates/movement_curve.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';

/// Debug draw of median, stride knots, and the final walk curve.
class MovementCurveOverlay extends StatelessWidget {
  const MovementCurveOverlay({
    super.key,
    required this.curve,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.lift = 0.22,
  });

  final MovementCurve? curve;
  final Camera camera;
  final Size viewport;
  final Scene? listenable;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    final curve = this.curve;
    if (curve == null || curve.points.isEmpty) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _CurvePainter(
          curve: curve,
          camera: camera,
          viewport: viewport,
          lift: lift,
        ),
      ),
    );
  }
}

class _CurvePainter extends CustomPainter {
  _CurvePainter({
    required this.curve,
    required this.camera,
    required this.viewport,
    required this.lift,
  });

  final MovementCurve curve;
  final Camera camera;
  final Size viewport;
  final double lift;

  Offset? _project(Offset xz) {
    return camera.projectToScreen(Vector3(xz.dx, lift, xz.dy), viewport);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final median = <Offset>[];
    for (final p in curve.medianPoints) {
      final s = _project(p);
      if (s != null) median.add(s);
    }
    if (curve.isClosed && median.isNotEmpty) median.add(median.first);

    final walk = <Offset>[];
    for (final p in curve.points) {
      final s = _project(p);
      if (s != null) walk.add(s);
    }

    if (median.length >= 2) {
      final path = Path()..moveTo(median.first.dx, median.first.dy);
      for (var i = 1; i < median.length; i++) {
        path.lineTo(median[i].dx, median[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x99FFFFFF)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }
    if (walk.length >= 2) {
      final path = Path()..moveTo(walk.first.dx, walk.first.dy);
      for (var i = 1; i < walk.length; i++) {
        path.lineTo(walk[i].dx, walk[i].dy);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xE6FF8A65)
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
    }

    final knotFill = Paint()..color = const Color(0xFFFFD54F);
    final knotStroke = Paint()
      ..color = const Color(0xFF212121)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final knot in curve.knots) {
      final s = _project(knot.position);
      if (s == null) continue;
      canvas.drawCircle(s, knot.isCorner ? 5 : 3.5, knotFill);
      canvas.drawCircle(s, knot.isCorner ? 5 : 3.5, knotStroke);
    }
  }

  @override
  bool shouldRepaint(covariant _CurvePainter oldDelegate) => true;
}
