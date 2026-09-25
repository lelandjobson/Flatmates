import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'craft_v1.dart';
import 'models.dart';

/// One puzzle step per crafting step. Edges are the guides. Every step shares
/// one paper size: the largest step bounds, grown by the same margin.
PapercutBlueprint papercutBlueprintFromCraft(CraftV1 craft) {
  final steps = craft.craftingSteps;
  final drafts = [
    for (var i = 0; i < steps.length; i++)
      _draft(craft, steps[i], _colors[i % _colors.length]),
  ];
  final paper = _uniformPaper(drafts);
  return PapercutBlueprint(
    id: craft.craft,
    name: craft.craft,
    steps: [
      for (final draft in drafts) _finish(draft, paper),
    ],
  );
}

class _Draft {
  _Draft({
    required this.craftingStep,
    required this.color,
    required this.curves,
    required this.bounds,
    required this.craftId,
  });

  final int craftingStep;
  final Color color;
  final List<PapercutCurve> curves;
  final Rect? bounds;
  final String craftId;
}

const _colors = [kPapercutPink, kPapercutYellow, kPapercutGreen];

_Draft _draft(CraftV1 craft, int craftingStep, Color color) {
  final faces = [
    for (final face in craft.faces)
      if (face.craftingStep == craftingStep) face,
  ];
  final edges = [
    for (final edge in craft.edges)
      if (edge.craftingStep == craftingStep && (edge.isFold || edge.isCut))
        edge,
  ];
  final curves = <PapercutCurve>[
    for (final edge in edges)
      PapercutCurve(
        id: '${edge.role}-${edge.faceA ?? ''}-${edge.faceB ?? ''}',
        role: edge.isFold ? PapercutCurveRole.fold : PapercutCurveRole.cut,
        points: _loop(edge.curve),
        closed: false,
        foldAngleDegrees: edge.isFold ? _foldDegrees(craft, edge) : 90,
      ),
  ];
  curves.addAll(_boundaryCuts(faces, curves));
  final points = <Offset>[
    for (final curve in curves) ...curve.points,
    for (final face in faces)
      for (final loop in face.flatLoops) ..._loop(loop),
  ];
  return _Draft(
    craftingStep: craftingStep,
    color: color,
    curves: curves,
    bounds: _bounds(points),
    craftId: craft.craft,
  );
}

/// Same width and height on every step. [margin] is added on each side of the
/// content, then each sheet grows to the largest padded size in the craft.
({double width, double height, double margin})? _uniformPaper(List<_Draft> drafts) {
  final boxes = [for (final draft in drafts) draft.bounds].whereType<Rect>();
  if (boxes.isEmpty) return null;
  var span = 0.0;
  for (final box in boxes) {
    span = math.max(span, math.max(box.width, box.height));
  }
  final margin = math.max(4.0, span * 0.08);
  var width = 0.0;
  var height = 0.0;
  for (final box in boxes) {
    width = math.max(width, box.width + margin * 2);
    height = math.max(height, box.height + margin * 2);
  }
  return (width: width, height: height, margin: margin);
}

PapercutStep _finish(
  _Draft draft,
  ({double width, double height, double margin})? paper,
) {
  final bounds = draft.bounds;
  final nets = <PapercutNet>[];
  if (paper != null && bounds != null) {
    final sheet = Rect.fromCenter(
      center: bounds.center,
      width: paper.width,
      height: paper.height,
    );
    nets.add(
      PapercutNet(
        outer: [
          sheet.topLeft,
          sheet.topRight,
          sheet.bottomRight,
          sheet.bottomLeft,
        ],
      ),
    );
  }
  final hasCuts = draft.curves.any((curve) => curve.role == PapercutCurveRole.cut);
  return PapercutStep(
    id: '${draft.craftId}-${draft.craftingStep}',
    label: 'Step ${draft.craftingStep}',
    paperColor: draft.color,
    geometry: PapercutCurveGeometry(
      id: '${draft.craftId}-step-${draft.craftingStep}',
      curves: draft.curves,
      hasSheet: nets.isNotEmpty,
      nets: nets,
    ),
    goals: hasCuts ? const [PapercutGoal.cutPerimeters] : const [],
  );
}

Rect? _bounds(List<Offset> points) {
  if (points.isEmpty) return null;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in points) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Child face rotation, in degrees. The child is the face whose parent is the other.
double _foldDegrees(CraftV1 craft, CraftV1Edge edge) {
  final a = _face(craft, edge.faceA);
  final b = _face(craft, edge.faceB);
  final child = _child(a, b) ?? _child(b, a);
  final transform = child?.transform;
  if (transform is CraftV1Rotation) {
    return transform.angleRadians * 180 / 3.141592653589793;
  }
  return 90;
}

CraftV1Face? _child(CraftV1Face? face, CraftV1Face? other) {
  if (face == null || other == null) return null;
  if (face.foldParentSurfaceId == other.surfaceId) return face;
  return null;
}

CraftV1Face? _face(CraftV1 craft, String? id) {
  if (id == null) return null;
  for (final face in craft.faces) {
    if (face.id == id) return face;
  }
  return null;
}

/// Face-loop edges the export left out. One open side of each part is typical.
List<PapercutCurve> _boundaryCuts(
  List<CraftV1Face> faces,
  List<PapercutCurve> existing,
) {
  final covered = <String>{};
  for (final curve in existing) {
    final points = curve.points;
    for (var i = 0; i < points.length - 1; i++) {
      covered.add(_segmentKey(points[i], points[i + 1]));
    }
  }
  final counts = <String, int>{};
  final segments = <String, (Offset, Offset)>{};
  for (final face in faces) {
    for (final loop in face.flatLoops) {
      final ring = _loop(loop);
      if (ring.length < 2) continue;
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i];
        final b = ring[(i + 1) % ring.length];
        if ((a - b).distance < 1e-4) continue;
        final key = _segmentKey(a, b);
        counts[key] = (counts[key] ?? 0) + 1;
        segments[key] = (a, b);
      }
    }
  }
  final cuts = <PapercutCurve>[];
  for (final entry in segments.entries) {
    if (counts[entry.key] != 1 || covered.contains(entry.key)) continue;
    final (a, b) = entry.value;
    cuts.add(
      PapercutCurve(
        id: 'boundary-${entry.key}',
        role: PapercutCurveRole.cut,
        points: [a, b],
        closed: false,
      ),
    );
  }
  return cuts;
}

String _segmentKey(Offset a, Offset b) {
  String q(Offset point) =>
      '${(point.dx * 1000).round()},${(point.dy * 1000).round()}';
  final left = q(a);
  final right = q(b);
  return left.compareTo(right) <= 0 ? '$left|$right' : '$right|$left';
}

List<Offset> _loop(List<Vector3> points) {
  final offsets = [for (final point in points) Offset(point.x, point.y)];
  if (offsets.length > 1 && (offsets.first - offsets.last).distance < 1e-4) {
    offsets.removeLast();
  }
  return offsets;
}
