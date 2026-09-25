import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'models.dart';

/// In-memory blueprint. Not loaded from craft.json.
PapercutBlueprint papercutSampleBlueprint() {
  return PapercutBlueprint(
    id: 'papercut-samples',
    name: 'Papercut samples',
    steps: [
      PapercutStep(
        id: 'square',
        label: 'One square',
        paperColor: kPapercutPink,
        geometry: PapercutCurveGeometry(
          id: 'square-1',
          curves: [
            PapercutCurve(
              id: 'square-cut',
              role: PapercutCurveRole.cut,
              points: const [
                Offset(-40, -40),
                Offset(40, -40),
                Offset(40, 40),
                Offset(-40, 40),
              ],
            ),
          ],
        ),
        goals: const [PapercutGoal.cutPerimeters],
      ),
      PapercutStep(
        id: 'two-shapes',
        label: 'Two shapes',
        paperColor: kPapercutYellow,
        geometry: PapercutCurveGeometry(
          id: 'shapes-1',
          curves: [
            PapercutCurve(
              id: 'rounded-cut',
              role: PapercutCurveRole.cut,
              points: _roundedRect(cx: -30, cy: 5, hw: 42, hh: 48, radius: 16),
            ),
            PapercutCurve(
              id: 'triangle-cut',
              role: PapercutCurveRole.cut,
              points: const [Offset(18, -52), Offset(78, -8), Offset(22, 58)],
            ),
          ],
        ),
        goals: const [PapercutGoal.cutPerimeters],
      ),
      PapercutStep(
        id: 'card',
        label: 'Card',
        paperColor: kPapercutGreen,
        geometry: const PapercutCurveGeometry(
          id: 'card-1',
          curves: [
            PapercutCurve(
              id: 'card-cut',
              role: PapercutCurveRole.cut,
              points: [
                Offset(-75, -48),
                Offset(75, -48),
                Offset(75, 48),
                Offset(-75, 48),
              ],
            ),
            PapercutCurve(
              id: 'card-spine',
              role: PapercutCurveRole.fold,
              points: [Offset(-75, 0), Offset(75, 0)],
              closed: false,
              foldGroup: 'card-spine',
              foldAngleDegrees: 90,
            ),
          ],
        ),
        goals: const [PapercutGoal.cutPerimeters],
      ),
      PapercutStep(
        id: 'wedge',
        label: 'Wedge',
        geometry: PapercutMeshGeometry(
          id: 'wedge-1',
          targetEulerDegrees: Vector3(0, 18, 0),
          triangles: _wedgeTriangles(),
        ),
        goals: const [],
      ),
    ],
  );
}

List<Offset> _roundedRect({
  required double cx,
  required double cy,
  required double hw,
  required double hh,
  required double radius,
}) {
  final left = cx - hw;
  final right = cx + hw;
  final bottom = cy - hh;
  final top = cy + hh;
  final r = radius;
  const segments = 4;
  final points = <Offset>[];

  void arc(double ox, double oy, double a0, double a1) {
    for (var i = 0; i <= segments; i++) {
      final t = a0 + (a1 - a0) * (i / segments);
      final point = Offset(ox + math.cos(t) * r, oy + math.sin(t) * r);
      if (points.isEmpty || (points.last - point).distance > 0.05) {
        points.add(point);
      }
    }
  }

  arc(right - r, bottom + r, -math.pi / 2, 0);
  arc(right - r, top - r, 0, math.pi / 2);
  arc(left + r, top - r, math.pi / 2, math.pi);
  arc(left + r, bottom + r, math.pi, math.pi * 1.5);
  if (points.isNotEmpty && (points.first - points.last).distance < 0.05) {
    points.removeLast();
  }
  return points;
}

List<List<Vector3>> _wedgeTriangles() {
  final a = Vector3(-50, -35, 0);
  final b = Vector3(55, -35, 0);
  final c = Vector3(55, 35, 0);
  final d = Vector3(-50, 35, 0);
  final e = Vector3(-50, -35, 45);
  final f = Vector3(-50, 35, 45);
  return [
    [a, c, b],
    [a, d, c],
    [a, e, f],
    [a, f, d],
    [e, b, c],
    [e, c, f],
    [a, b, e],
    [d, f, c],
  ];
}
