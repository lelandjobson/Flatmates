import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'camera.dart';
import 'measure.dart';
import 'models.dart';
import 'paper.dart';
import 'safe_zone.dart';

class PapercutPainter extends CustomPainter {
  PapercutPainter({
    required this.camera,
    required this.step,
    required this.sheet,
    required this.showScissors,
    required this.scissorsAllowed,
    required this.scissorJoint,
    required this.cutJoints,
    required this.showRuler,
    required this.showBlueprintZones,
    required this.showCutZones,
    required this.measure,
    required this.showOutlineMeasure,
    required this.showGraphMeasure,
    required this.showNearestMeasure,
    required this.showIssueMeasure,
    required this.liveStroke,
  });

  final PapercutCamera camera;
  final PapercutStep step;
  final PapercutSheet sheet;
  final bool showScissors;
  final bool scissorsAllowed;
  final Offset? scissorJoint;
  final List<Offset> cutJoints;
  final bool showRuler;
  final bool showBlueprintZones;
  final bool showCutZones;
  final PapercutMeasure? measure;
  final bool showOutlineMeasure;
  final bool showGraphMeasure;
  final bool showNearestMeasure;
  final bool showIssueMeasure;
  final List<Offset>? liveStroke;

  @override
  void paint(Canvas canvas, Size size) {
    final geometry = step.geometry;
    if (geometry is PapercutMeshGeometry) {
      _paintMesh(canvas, size, geometry);
    } else if (geometry is PapercutCurveGeometry) {
      _paintPieces(canvas, size);
      if (showBlueprintZones) {
        _paintCurveZones(canvas, size, geometry.cutCurves, kPapercutGuide);
        _paintCurveZones(canvas, size, geometry.foldCurves, kPapercutFold);
      }
      if (showCutZones) {
        _paintStrokeZones(canvas, size, sheet.cutStrokes, kPapercutCut);
        _paintStrokeZones(
          canvas,
          size,
          [
            for (final crease in sheet.creases) [crease.a, crease.b],
          ],
          kPapercutFold,
          capsuleFraction: kPapercutFoldCapsuleFraction,
        );
      }
      _paintCurves(
        canvas,
        size,
        geometry.curves.where((curve) => curve.role == PapercutCurveRole.cut),
        const Color(0xFF1565C0),
        dashed: false,
      );
      _paintCurves(
        canvas,
        size,
        geometry.foldCurves,
        const Color(0xFFE53935),
        dashed: true,
      );
      _paintCreases(canvas, size);
      _paintCuts(canvas, size);
      _paintJoints(canvas, size);
      _paintMeasure(canvas, size);
    }
    if (showRuler) _paintRuler(canvas, size);
    if (showScissors) _paintScissors(canvas, size);
    final stroke = liveStroke;
    if (stroke != null && stroke.length >= 2) {
      _paintScreenStroke(canvas, stroke, kPapercutCut);
    }
  }

  void _paintCurveZones(
    Canvas canvas,
    Size size,
    Iterable<PapercutCurve> curves,
    Color color,
  ) {
    for (final curve in curves) {
      final fraction = curve.role == PapercutCurveRole.fold
          ? kPapercutFoldCapsuleFraction
          : kPapercutCutCapsuleFraction;
      _paintBand(
        canvas,
        size,
        safeZoneBand(
          curve.points,
          closed: curve.closed,
          capsuleFraction: fraction,
        ),
        color.withValues(alpha: 0.28),
      );
    }
  }

  void _paintStrokeZones(
    Canvas canvas,
    Size size,
    List<List<Offset>> strokes,
    Color color, {
    double capsuleFraction = kPapercutCutCapsuleFraction,
  }) {
    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      _paintBand(
        canvas,
        size,
        safeZoneBand(stroke, closed: false, capsuleFraction: capsuleFraction),
        color.withValues(alpha: 0.28),
      );
    }
  }

  void _paintBand(
    Canvas canvas,
    Size size,
    PapercutSafeZoneBand band,
    Color color,
  ) {
    if (band.left.length < 2 || band.right.length < 2) return;
    final left = _projectRing(band.left, size);
    final right = _projectRing(band.right, size);
    if (left == null || right == null) return;
    final path = Path()..moveTo(left.first.dx, left.first.dy);
    for (final point in left.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (band.open) {
      for (final point in right.reversed) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
    } else {
      path.close();
      final hole = Path()..moveTo(right.first.dx, right.first.dy);
      for (final point in right.skip(1)) {
        hole.lineTo(point.dx, point.dy);
      }
      hole.close();
      path
        ..addPath(hole, Offset.zero)
        ..fillType = PathFillType.evenOdd;
    }
    canvas.drawPath(path, Paint()..color = color);
    if (!band.open || band.capRadius <= 0) return;
    _paintDisk(canvas, size, band.start!, band.capRadius, color);
    _paintDisk(canvas, size, band.end!, band.capRadius, color);
  }

  void _paintDisk(
    Canvas canvas,
    Size size,
    Offset center,
    double radius,
    Color color,
  ) {
    final ring = <Offset>[];
    for (var i = 0; i < 16; i++) {
      final angle = i / 16 * math.pi * 2;
      ring.add(
        Offset(
          center.dx + math.cos(angle) * radius,
          center.dy + math.sin(angle) * radius,
        ),
      );
    }
    final projected = _projectRing(ring, size);
    if (projected == null) return;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color);
  }

  void _paintPieces(Canvas canvas, Size size) {
    final pieces = [...sheet.pieces]
      ..sort((a, b) {
        final areaA = _ringArea(a.vertices);
        final areaB = _ringArea(b.vertices);
        return areaB.compareTo(areaA);
      });
    for (final piece in pieces) {
      final path = _ringPath(piece.vertices, size);
      if (path == null) continue;
      for (final hole in piece.holes) {
        final holePath = _ringPath(hole, size);
        if (holePath != null) path.addPath(holePath, Offset.zero);
      }
      path.fillType = PathFillType.evenOdd;
      canvas.drawPath(path, Paint()..color = piece.color);
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0xFF1A1A2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );
    }
  }

  void _paintMesh(Canvas canvas, Size size, PapercutMeshGeometry mesh) {
    final triangles = [
      for (final triangle in mesh.triangles)
        if (triangle.length >= 3)
          [
            for (final vertex in triangle.take(3))
              _orient(vertex, mesh.targetEulerDegrees),
          ],
    ];
    final eye = camera.camera.position;
    triangles.sort((a, b) {
      final depthA = (_centroid(a) - eye).length2;
      final depthB = (_centroid(b) - eye).length2;
      return depthB.compareTo(depthA);
    });
    for (final triangle in triangles) {
      final projected = [
        for (final vertex in triangle)
          camera.camera.projectToScreen(vertex, size),
      ];
      if (projected.any((point) => point == null)) continue;
      final path = Path()
        ..moveTo(projected[0]!.dx, projected[0]!.dy)
        ..lineTo(projected[1]!.dx, projected[1]!.dy)
        ..lineTo(projected[2]!.dx, projected[2]!.dy)
        ..close();
      final normal = (triangle[1] - triangle[0]).cross(
        triangle[2] - triangle[0],
      );
      var shade = 0.55;
      if (normal.length2 > 1e-8) {
        normal.normalize();
        final view = eye - _centroid(triangle);
        if (view.length2 > 1e-8) {
          shade = 0.45 + 0.55 * normal.dot(view.normalized()).abs();
        }
      }
      canvas.drawPath(
        path,
        Paint()..color = Color.lerp(kPapercutYellow, Colors.white, shade)!,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = const Color(0x661A1A2E)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
  }

  void _paintCurves(
    Canvas canvas,
    Size size,
    Iterable<PapercutCurve> curves,
    Color color, {
    required bool dashed,
  }) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (final curve in curves) {
      final projected = _projectRing(curve.points, size);
      if (projected == null || projected.length < 2) continue;
      if (dashed) {
        _paintDashed(canvas, projected, paint);
        if (curve.role == PapercutCurveRole.fold) {
          _paintLabel(
            canvas,
            projected[projected.length ~/ 2],
            '${curve.foldAngleDegrees.round()}°',
          );
        }
      } else {
        final path = Path()..moveTo(projected.first.dx, projected.first.dy);
        for (final point in projected.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        if (curve.closed) path.close();
        canvas.drawPath(path, paint);
      }
    }
  }

  void _paintCreases(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kPapercutFold
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;
    for (final crease in sheet.creases) {
      final projected = _projectRing([crease.a, crease.b], size);
      if (projected == null || projected.length < 2) continue;
      _paintDashed(canvas, projected, paint);
      _paintLabel(
        canvas,
        projected[projected.length ~/ 2] + const Offset(0, -14),
        '${crease.angleDegrees.round()}°',
      );
    }
  }

  void _paintCuts(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = kPapercutCut
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    for (final stroke in sheet.cutStrokes) {
      final projected = _projectRing(stroke, size);
      if (projected == null || projected.length < 2) continue;
      final path = Path()..moveTo(projected.first.dx, projected.first.dy);
      for (final point in projected.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  void _paintScissors(Canvas canvas, Size size) {
    final tail = Offset(size.width / 2, size.height);
    final tip = Offset(size.width / 2, size.height / 2);
    final allowed = Paint()
      ..color = kPapercutScissorAllowed
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final denied = Paint()
      ..color = kPapercutScissorDenied
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    if (!scissorsAllowed) {
      canvas.drawLine(tail, tip, denied);
      return;
    }
    final joint = scissorJoint;
    final screen = joint == null
        ? null
        : camera.camera.projectToScreen(Vector3(joint.dx, joint.dy, 0), size);
    if (screen == null) {
      canvas.drawLine(tail, tip, allowed);
      return;
    }
    canvas.drawLine(tip, screen, allowed);
    canvas.drawLine(screen, tail, denied);
  }

  void _paintMeasure(Canvas canvas, Size size) {
    final report = measure;
    if (report == null) return;
    final labels = <_MeasureLabel>[];
    if (showOutlineMeasure) {
      _paintMeasureEdges(
        canvas,
        size,
        report.blueprint,
        const Color(0xFF4FC3F7),
        labels,
      );
    }
    if (showGraphMeasure) {
      for (var i = 0; i < report.graph.length; i++) {
        _paintMeasureEdges(
          canvas,
          size,
          [report.graph[i]],
          i.isEven ? const Color(0xFFFFB74D) : const Color(0xFFFF8A65),
          labels,
        );
      }
    }
    if (showNearestMeasure) {
      _paintMeasureEdges(
        canvas,
        size,
        report.nearest,
        const Color(0xFF69F0AE),
        labels,
      );
    }
    if (showIssueMeasure) {
      for (final issue in report.issues) {
        final color = issue.gap
            ? const Color(0xFFFF5252)
            : const Color(0xFFFFAB40);
        _paintWorldStroke(canvas, size, issue.span, color, 4);
        final from = _projectPoint(issue.mark, size);
        final to = _projectPoint(issue.nearest, size);
        if (from != null && to != null) {
          canvas.drawLine(
            from,
            to,
            Paint()
              ..color = color
              ..strokeWidth = 1,
          );
          canvas.drawCircle(from, 3.5, Paint()..color = color);
          if (issue.millimeters >= 0) {
            labels.add(
              _MeasureLabel(
                at: Offset((from.dx + to.dx) / 2, (from.dy + to.dy) / 2),
                text: '${issue.millimeters}',
                color: color,
                rank: 1000 + issue.millimeters,
              ),
            );
          }
        }
      }
    }
    labels.sort((a, b) => b.rank.compareTo(a.rank));
    final occupied = <Rect>[];
    for (final label in labels) {
      final rect = _paintChip(canvas, label, occupied);
      if (rect != null) occupied.add(rect);
    }
  }

  void _paintMeasureEdges(
    Canvas canvas,
    Size size,
    List<PapercutMeasureEdge> edges,
    Color color,
    List<_MeasureLabel> labels,
  ) {
    for (final edge in edges) {
      _paintWorldStroke(canvas, size, edge.points, color, 3);
      if (edge.millimeters <= 0) continue;
      final anchor = _edgeLabelAnchor(edge.points, size);
      if (anchor == null) continue;
      labels.add(
        _MeasureLabel(
          at: anchor,
          text: '${edge.millimeters}',
          color: color,
          rank: edge.millimeters,
        ),
      );
    }
  }

  void _paintWorldStroke(
    Canvas canvas,
    Size size,
    List<Offset> points,
    Color color,
    double width,
  ) {
    final projected = _projectRing(points, size);
    if (projected == null || projected.length < 2) return;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  Offset? _edgeLabelAnchor(List<Offset> points, Size size) {
    var longest = 0.0;
    Offset? a;
    Offset? b;
    for (var i = 0; i < points.length - 1; i++) {
      final length = (points[i + 1] - points[i]).distance;
      if (length <= longest) continue;
      longest = length;
      a = points[i];
      b = points[i + 1];
    }
    if (a == null || b == null) return null;
    final screenA = _projectPoint(a, size);
    final screenB = _projectPoint(b, size);
    if (screenA == null || screenB == null) return null;
    if ((screenB - screenA).distance < 22 && longest < 15) return null;
    final mid = _projectPoint(
      Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2),
      size,
    );
    if (mid == null) return null;
    final delta = screenB - screenA;
    final len = delta.distance;
    if (len < 1) return mid;
    final normal = Offset(-delta.dy / len, delta.dx / len);
    return mid + normal * 12;
  }

  Rect? _paintChip(Canvas canvas, _MeasureLabel label, List<Rect> occupied) {
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: TextStyle(
          color: label.color,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 48);
    final rect = Rect.fromCenter(
      center: label.at,
      width: painter.width + 6,
      height: painter.height + 2,
    );
    for (final taken in occupied) {
      if (taken.overlaps(rect.inflate(2))) return null;
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = const Color(0xE6101018),
    );
    painter.paint(canvas, Offset(rect.left + 3, rect.top + 1));
    return rect;
  }

  Offset? _projectPoint(Offset point, Size size) {
    return camera.camera.projectToScreen(Vector3(point.dx, point.dy, 0), size);
  }

  void _paintJoints(Canvas canvas, Size size) {
    for (final joint in cutJoints) {
      final screen = camera.camera.projectToScreen(
        Vector3(joint.dx, joint.dy, 0),
        size,
      );
      if (screen == null) continue;
      canvas.drawCircle(screen, 4, Paint()..color = Colors.white);
      canvas.drawCircle(screen, 2.5, Paint()..color = kPapercutCut);
    }
  }

  void _paintRuler(Canvas canvas, Size size) {
    final edge = size.height / 2;
    final rect = Rect.fromLTRB(0, edge - 28, size.width, edge);
    canvas.drawRect(rect, Paint()..color = const Color(0xCC1A1A1A));
    canvas.drawLine(
      Offset(0, edge),
      Offset(size.width, edge),
      Paint()
        ..color = kPapercutRuler
        ..strokeWidth = 2,
    );
    final tick = Paint()
      ..color = Colors.white70
      ..strokeWidth = 1;
    for (var x = 16.0; x < size.width; x += 16) {
      final tall = ((x / 16).round() % 4) == 0;
      canvas.drawLine(Offset(x, edge), Offset(x, edge - (tall ? 14 : 8)), tick);
    }
  }

  void _paintScreenStroke(Canvas canvas, List<Offset> stroke, Color color) {
    final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
    for (final point in stroke.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintDashed(Canvas canvas, List<Offset> points, Paint paint) {
    for (var i = 0; i < points.length - 1; i++) {
      final a = points[i];
      final b = points[i + 1];
      final delta = b - a;
      final len = delta.distance;
      if (len < 1) continue;
      final dir = delta / len;
      var traveled = 0.0;
      while (traveled < len) {
        final end = math.min(traveled + 8, len);
        canvas.drawLine(a + dir * traveled, a + dir * end, paint);
        traveled = end + 6;
      }
    }
  }

  void _paintLabel(Canvas canvas, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: kPapercutFold, fontSize: 12),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at + const Offset(6, -8));
  }

  Path? _ringPath(List<Offset> ring, Size size) {
    final projected = _projectRing(ring, size);
    if (projected == null || projected.length < 3) return null;
    final path = Path()..moveTo(projected.first.dx, projected.first.dy);
    for (final point in projected.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  List<Offset>? _projectRing(List<Offset> ring, Size size) {
    final projected = <Offset>[];
    for (final point in ring) {
      final screen = camera.camera.projectToScreen(
        Vector3(point.dx, point.dy, 0),
        size,
      );
      if (screen == null) return null;
      projected.add(screen);
    }
    return projected;
  }

  Vector3 _orient(Vector3 vertex, Vector3 eulerDegrees) {
    final matrix = Matrix4.identity()
      ..rotateY(eulerDegrees.y * math.pi / 180)
      ..rotateX(eulerDegrees.x * math.pi / 180)
      ..rotateZ(eulerDegrees.z * math.pi / 180);
    return matrix.transform3(Vector3.copy(vertex));
  }

  Vector3 _centroid(List<Vector3> triangle) =>
      (triangle[0] + triangle[1] + triangle[2]) / 3;

  double _ringArea(List<Offset> ring) {
    var area = 0.0;
    for (var i = 0; i < ring.length; i++) {
      final next = ring[(i + 1) % ring.length];
      area += ring[i].dx * next.dy - next.dx * ring[i].dy;
    }
    return area.abs() * 0.5;
  }

  @override
  bool shouldRepaint(covariant PapercutPainter oldDelegate) => true;
}

class _MeasureLabel {
  const _MeasureLabel({
    required this.at,
    required this.text,
    required this.color,
    required this.rank,
  });

  final Offset at;
  final String text;
  final Color color;
  final int rank;
}
