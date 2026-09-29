import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'blueprint.dart';

const _eps = 1e-4;

/// Fixed flashlight cone, measured from the facing axis to each side.
const double flashlightHalfAngle = 25 * math.pi / 180;

double sideOfLine(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final ap = point - a;
  return ab.dx * ap.dy - ab.dy * ap.dx;
}

Offset reflectAcrossLine(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < _eps) return point;
  final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
  final foot = Offset(a.dx + ab.dx * t, a.dy + ab.dy * t);
  return foot * 2 - point;
}

bool foldApplies(Offset point, FoldJoint joint) {
  if (joint.facing == FoldFacing.unfolded) return false;
  final side = sideOfLine(point, joint.a, joint.b);
  if (side.abs() < _eps) return false;
  return side.sign == joint.side.sign;
}

/// Unfolded [point] moved onto the face the player sees.
Offset displayPoint(Offset point, List<FoldJoint> joints) {
  var current = point;
  for (final joint in joints) {
    if (!foldApplies(current, joint)) continue;
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return current;
}

List<Offset> displayRing(List<Offset> ring, List<FoldJoint> joints) {
  return [for (final point in ring) displayPoint(point, joints)];
}

/// Positive draws above the sheet. Negative draws underneath.
int foldDepth(Offset point, List<FoldJoint> joints) {
  var depth = 0;
  var current = point;
  for (final joint in joints) {
    if (!foldApplies(current, joint)) continue;
    depth += joint.facing == FoldFacing.toward ? 1 : -1;
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return depth;
}

bool showingBack(Offset point, List<FoldJoint> joints) {
  var flips = 0;
  var current = point;
  for (final joint in joints) {
    if (!foldApplies(current, joint)) continue;
    flips++;
    current = reflectAcrossLine(current, joint.a, joint.b);
  }
  return flips.isOdd;
}

/// Maps a point on the displayed sheet back to unfolded coordinates.
Offset localPoint(Offset visual, List<FoldJoint> joints) {
  var current = visual;
  for (final joint in joints.reversed) {
    if (joint.facing == FoldFacing.unfolded) continue;
    final reflected = reflectAcrossLine(current, joint.a, joint.b);
    if (foldApplies(reflected, joint)) current = reflected;
  }
  return current;
}

int topPieceIndex(Offset visual, PapercutSheet sheet) {
  var best = -1;
  var bestDepth = -1 << 30;
  for (var i = 0; i < sheet.pieces.length; i++) {
    final piece = sheet.pieces[i];
    final local = localPoint(visual, sheet.folds);
    if (!isInsidePolygon(local, piece.vertices)) continue;
    var inHole = false;
    for (final hole in piece.holes) {
      if (isInsidePolygon(local, hole)) inHole = true;
    }
    if (inHole) continue;
    final depth = foldDepth(polygonCentroid(piece.vertices), sheet.folds);
    if (depth >= bestDepth) {
      bestDepth = depth;
      best = i;
    }
  }
  return best;
}

PapercutSheet addPaperMark(PapercutSheet sheet, List<Offset> visualStroke) {
  if (visualStroke.length < 2) return sheet;
  final index = topPieceIndex(visualStroke.first, sheet);
  if (index < 0) return sheet;
  final local = [for (final point in visualStroke) localPoint(point, sheet.folds)];
  if (!isInsidePolygon(local.first, sheet.pieces[index].vertices)) return sheet;
  return sheet.copyWith(marks: [...sheet.marks, PaperMark(points: local)]);
}

/// Screen-vertical crease through [through], clipped to [bounds].
(Offset, Offset)? creaseSpan(Offset through, Offset direction, Rect bounds) {
  final length = direction.distance;
  if (length < _eps) return null;
  final ray = direction / length;
  final hits = <Offset>[];
  void add(double t) {
    hits.add(through + ray * t);
  }

  if (ray.dx.abs() > _eps) {
    add((bounds.left - through.dx) / ray.dx);
    add((bounds.right - through.dx) / ray.dx);
  }
  if (ray.dy.abs() > _eps) {
    add((bounds.top - through.dy) / ray.dy);
    add((bounds.bottom - through.dy) / ray.dy);
  }
  final inside = [
    for (final point in hits)
      if (_inRect(point, bounds)) point,
  ];
  if (inside.length < 2) return null;
  inside.sort((a, b) {
    final ta = (a - through).dx * ray.dx + (a - through).dy * ray.dy;
    final tb = (b - through).dx * ray.dx + (b - through).dy * ray.dy;
    return ta.compareTo(tb);
  });
  final span = (inside.last - inside.first);
  if (span.distance < _eps) return null;
  return (inside.first, inside.last);
}

bool _inRect(Offset point, Rect rect) {
  return point.dx >= rect.left - 1e-3 &&
      point.dx <= rect.right + 1e-3 &&
      point.dy >= rect.top - 1e-3 &&
      point.dy <= rect.bottom + 1e-3;
}

/// Folds the side of [span] indicated by [flapPoint].
///
/// Returns null when the fold meets a no-fold zone or a blueprint piece that
/// overlaps one. [record] is false so the crease is a joint, not a cut.
PapercutSheet? foldSheet({
  required PapercutSheet sheet,
  required Offset spanA,
  required Offset spanB,
  required Offset flapPoint,
  required FoldFacing facing,
  List<List<Offset>> noFold = const [],
  List<List<Offset>> blueprintPieces = const [],
}) {
  if (facing == FoldFacing.unfolded) return null;
  final side = sideOfLine(flapPoint, spanA, spanB);
  if (side.abs() < _eps) return null;
  if (_foldBlocked(
    sheet: sheet,
    a: spanA,
    b: spanB,
    side: side,
    noFold: noFold,
    blueprintPieces: blueprintPieces,
  )) {
    return null;
  }
  final split = applyPapercutCut(sheet, [spanA, spanB], recordStroke: false);
  final next = split ?? sheet;
  return next.copyWith(
    folds: [
      ...next.folds,
      FoldJoint(a: spanA, b: spanB, side: side, facing: facing),
    ],
  );
}

PapercutSheet? unfoldAt(PapercutSheet sheet, Offset point, {double reach = 0.45}) {
  for (var i = sheet.folds.length - 1; i >= 0; i--) {
    final joint = sheet.folds[i];
    if (joint.facing == FoldFacing.unfolded) continue;
    if (_distanceToSegment(point, joint.a, joint.b) > reach) continue;
    final folds = [...sheet.folds];
    folds[i] = joint.copyWith(facing: FoldFacing.unfolded);
    return sheet.copyWith(
      folds: folds,
      scores: [...sheet.scores, ScoreLine(joint.a, joint.b)],
    );
  }
  return null;
}

bool _foldBlocked({
  required PapercutSheet sheet,
  required Offset a,
  required Offset b,
  required double side,
  required List<List<Offset>> noFold,
  required List<List<Offset>> blueprintPieces,
}) {
  if (sheet.pieces.isEmpty) return false;
  for (final zone in noFold) {
    if (zone.length < 3) continue;
    if (_segmentHitsRing(a, b, zone)) return true;
    for (final point in zone) {
      final signed = sideOfLine(point, a, b);
      if (signed.abs() > _eps && signed.sign == side.sign) return true;
    }
    for (final ring in blueprintPieces) {
      if (ring.length < 3) continue;
      if (!_ringsOverlap(ring, zone)) continue;
      if (sideOfLine(polygonCentroid(ring), a, b).sign == side.sign) {
        return true;
      }
    }
  }
  return false;
}

bool _ringsOverlap(List<Offset> a, List<Offset> b) {
  if (isInsidePolygon(polygonCentroid(a), b)) return true;
  if (isInsidePolygon(polygonCentroid(b), a)) return true;
  for (final point in a) {
    if (isInsidePolygon(point, b)) return true;
  }
  return _segmentHitsRing(a.first, a[1], b);
}

bool _segmentHitsRing(Offset a, Offset b, List<Offset> ring) {
  if (isInsidePolygon(a, ring) || isInsidePolygon(b, ring)) return true;
  for (var i = 0; i < ring.length; i++) {
    final c = ring[i];
    final d = ring[(i + 1) % ring.length];
    if (_segmentsCross(a, b, c, d)) return true;
  }
  return false;
}

bool _segmentsCross(Offset a, Offset b, Offset c, Offset d) {
  final ab = b - a;
  final cd = d - c;
  final denom = ab.dx * cd.dy - ab.dy * cd.dx;
  if (denom.abs() < 1e-10) return false;
  final ac = c - a;
  final t = (ac.dx * cd.dy - ac.dy * cd.dx) / denom;
  final u = (ac.dx * ab.dy - ac.dy * ab.dx) / denom;
  return t > _eps && t < 1 - _eps && u > _eps && u < 1 - _eps;
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final len2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (len2 < 1e-12) return (point - a).distance;
  final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  final closest = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
  return (point - closest).distance;
}

/// Cuts [visualStroke] through every displayed layer it crosses.
PapercutSheet? cutThroughFolds(
  PapercutSheet sheet,
  List<Offset> visualStroke, {
  double thickCut = 0,
  List<List<Offset>> blueprintPieces = const [],
}) {
  if (visualStroke.length < 2) return null;
  final local = [for (final point in visualStroke) localPoint(point, sheet.folds)];
  if (thickCut > 0) {
    return applyThickCut(
      sheet,
      local,
      thickCut,
      blueprintPieces: blueprintPieces,
    );
  }
  final layers = <List<Offset>>[local];
  for (final joint in sheet.folds) {
    if (joint.facing == FoldFacing.unfolded) continue;
    layers.add([
      for (final point in local) reflectAcrossLine(point, joint.a, joint.b),
    ]);
  }
  PapercutSheet? current = sheet;
  var any = false;
  for (final stroke in layers) {
    final next = applyPapercutCut(current!, stroke);
    if (next == null) continue;
    any = true;
    current = next;
  }
  return any ? current : null;
}

List<Offset> capsule(Offset a, Offset b, double radius) {
  if (radius <= 0) return const [];
  final delta = b - a;
  final len = delta.distance;
  if (len < _eps) return _circle(a, radius);
  final dir = delta / len;
  const steps = 8;
  final points = <Offset>[];
  for (var i = 0; i <= steps; i++) {
    final angle = -math.pi / 2 + math.pi * i / steps;
    points.add(b + _rotate(dir, angle) * radius);
  }
  for (var i = 0; i <= steps; i++) {
    final angle = math.pi / 2 + math.pi * i / steps;
    points.add(a + _rotate(dir, angle) * radius);
  }
  return points;
}

List<Offset> _circle(Offset center, double radius) {
  const steps = 16;
  return [
    for (var i = 0; i < steps; i++)
      center +
          Offset(
            math.cos(2 * math.pi * i / steps),
            math.sin(2 * math.pi * i / steps),
          ) *
              radius,
  ];
}

Offset _rotate(Offset vector, double angle) {
  final c = math.cos(angle);
  final s = math.sin(angle);
  return Offset(vector.dx * c - vector.dy * s, vector.dx * s + vector.dy * c);
}

PapercutSheet? applyThickCut(
  PapercutSheet sheet,
  List<Offset> centerline,
  double halfWidth, {
  List<List<Offset>> blueprintPieces = const [],
}) {
  if (halfWidth <= 0 || centerline.length < 2) return null;
  PapercutSheet? current = sheet;
  var any = false;
  for (var i = 0; i < centerline.length - 1; i++) {
    final a = centerline[i];
    final b = centerline[i + 1];
    final regions = _stripRegions(a, b, halfWidth, blueprintPieces);
    for (final region in regions) {
      final next = subtractRegion(current!, region);
      if (next == null) continue;
      any = true;
      current = next;
    }
  }
  return any ? current : null;
}

List<List<Offset>> _stripRegions(
  Offset a,
  Offset b,
  double halfWidth,
  List<List<Offset>> blueprintPieces,
) {
  final strip = capsule(a, b, halfWidth);
  if (strip.length < 3) return const [];
  var sheet = PapercutSheet(
    pieces: [
      PapercutPiece(
        id: 'strip',
        color: const Color(0x00000000),
        vertices: strip,
      ),
    ],
  );
  for (final ring in blueprintPieces) {
    if (ring.length < 3) continue;
    if (_rides(a, b, ring)) continue;
    final next = subtractRegion(sheet, ring);
    if (next != null) sheet = next;
  }
  return [for (final piece in sheet.pieces) piece.vertices];
}

bool _rides(Offset a, Offset b, List<Offset> ring) {
  for (var i = 0; i < ring.length; i++) {
    final c = ring[i];
    final d = ring[(i + 1) % ring.length];
    if (_distanceToSegment(a, c, d) > 1e-2) continue;
    if (_distanceToSegment(b, c, d) > 1e-2) continue;
    return true;
  }
  return false;
}

enum PunchShape { circle, square, triangle }

const List<double> punchSizes = [0.5, 1, 2];

List<Offset> punchOutline(Offset center, PunchShape shape, double size) {
  final half = size / 2;
  return switch (shape) {
    PunchShape.circle => _circle(center, half),
    PunchShape.square => [
      center + Offset(-half, -half),
      center + Offset(half, -half),
      center + Offset(half, half),
      center + Offset(-half, half),
    ],
    PunchShape.triangle => [
      center + Offset(0, -half),
      center + Offset(half, half),
      center + Offset(-half, half),
    ],
  };
}

bool punchCrossesBlueprint(List<Offset> punch, List<List<Offset>> pieces) {
  for (final ring in pieces) {
    if (ring.length < 3) continue;
    for (final point in punch) {
      if (isInsidePolygon(point, ring)) return true;
    }
    if (punch.isNotEmpty && isInsidePolygon(polygonCentroid(punch), ring)) {
      return true;
    }
    for (final vertex in ring) {
      if (isInsidePolygon(vertex, punch)) return true;
    }
  }
  return false;
}

Offset reflectPoint(Offset point, Offset center, {required bool acrossX, required bool acrossY}) {
  var x = point.dx;
  var y = point.dy;
  if (acrossX) x = center.dx * 2 - x;
  if (acrossY) y = center.dy * 2 - y;
  return Offset(x, y);
}

List<List<Offset>> mirroredPolylines(
  List<Offset> path,
  Offset center, {
  required bool mirrorX,
  required bool mirrorY,
}) {
  final images = <List<Offset>>[];
  void add({required bool acrossX, required bool acrossY}) {
    images.add([
      for (final point in path)
        reflectPoint(point, center, acrossX: acrossX, acrossY: acrossY),
    ]);
  }

  if (mirrorX) add(acrossX: true, acrossY: false);
  if (mirrorY) add(acrossX: false, acrossY: true);
  if (mirrorX && mirrorY) add(acrossX: true, acrossY: true);
  return images;
}

/// Unit-cell center inside [ring] closest to the piece centroid.
Offset collisionAnchor(List<Offset> ring) {
  if (ring.length < 3) return ring.isEmpty ? Offset.zero : ring.first;
  final centroid = polygonCentroid(ring);
  var minX = ring.first.dx;
  var maxX = ring.first.dx;
  var minY = ring.first.dy;
  var maxY = ring.first.dy;
  for (final point in ring) {
    minX = math.min(minX, point.dx);
    maxX = math.max(maxX, point.dx);
    minY = math.min(minY, point.dy);
    maxY = math.max(maxY, point.dy);
  }
  Offset? best;
  var bestDistance = double.infinity;
  for (var x = minX.floor(); x <= maxX.ceil(); x++) {
    for (var y = minY.floor(); y <= maxY.ceil(); y++) {
      final center = Offset(x + 0.5, y + 0.5);
      if (!isInsidePolygon(center, ring)) continue;
      final distance = (center - centroid).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = center;
      }
    }
  }
  return best ?? centroid;
}

/// The paper under a hits piece may leave only when [hitsLeft] is already 0.
/// A positive count means that paper was removed too soon.
bool paperRemovedEarly(int? hitsLeft, {required bool cutOut}) {
  if (hitsLeft == null || hitsLeft <= 0) return false;
  return cutOut;
}

bool blueprintPieceCutOut(List<Offset> ring, PapercutSheet sheet) {
  if (ring.length < 3) return false;
  final target = polygonSignedArea(ring).abs();
  if (target < 1e-6) return false;
  final center = polygonCentroid(ring);
  for (final piece in sheet.pieces) {
    if (!isInsidePolygon(center, piece.vertices)) continue;
    var buried = false;
    for (final hole in piece.holes) {
      if (isInsidePolygon(center, hole)) buried = true;
    }
    if (buried) continue;
    final area = polygonSignedArea(piece.vertices).abs();
    if ((area - target).abs() <= target * 0.25 + 0.35) return true;
  }
  return false;
}

/// Blueprint piece indexes whose perimeter the segment meets.
List<int> piecesTouched(
  List<List<Offset>> pieces,
  Offset a,
  Offset b, {
  List<bool> closed = const [],
}) {
  final hits = <int>[];
  for (var i = 0; i < pieces.length; i++) {
    if (i < closed.length && !closed[i]) continue;
    final ring = pieces[i];
    if (ring.length < 3) continue;
    for (var e = 0; e < ring.length; e++) {
      final c = ring[e];
      final d = ring[(e + 1) % ring.length];
      if (_segmentsNear(a, b, c, d)) {
        hits.add(i);
        break;
      }
    }
  }
  return hits;
}

bool _segmentsNear(Offset a, Offset b, Offset c, Offset d) {
  if (_segmentsCross(a, b, c, d)) return true;
  if (_distanceToSegment(a, c, d) <= 1e-2) return true;
  if (_distanceToSegment(b, c, d) <= 1e-2) return true;
  if (_distanceToSegment(c, a, b) <= 1e-2) return true;
  if (_distanceToSegment(d, a, b) <= 1e-2) return true;
  return false;
}

/// True when [edge] is penciled and another blueprint piece has a penned
/// edge on the same line.
bool penciledRidesPennedNeighbor(
  List<List<Offset>> pieces,
  List<List<EdgeStyle>> styles,
  Offset a,
  Offset b, {
  List<bool> closed = const [],
}) {
  var penciled = false;
  var pennedNeighbor = false;
  for (var i = 0; i < pieces.length; i++) {
    final ring = pieces[i];
    final ringClosed = i >= closed.length || closed[i];
    final edges = ringClosed ? ring.length : ring.length - 1;
    if (edges < 1) continue;
    final style = i < styles.length && styles[i].length == ring.length
        ? styles[i]
        : List<EdgeStyle>.filled(ring.length, EdgeStyle.penned);
    for (var e = 0; e < edges; e++) {
      final c = ring[e];
      final d = ring[(e + 1) % ring.length];
      if (!_sameSpan(a, b, c, d) && !_collinearOverlap(a, b, c, d)) continue;
      if (style[e] == EdgeStyle.penciled && _sameSpan(a, b, c, d)) {
        penciled = true;
      } else if (style[e] == EdgeStyle.penned && _collinearOverlap(a, b, c, d)) {
        pennedNeighbor = true;
      }
    }
  }
  return penciled && pennedNeighbor;
}

bool _sameSpan(Offset a, Offset b, Offset c, Offset d) {
  return ((a - c).distance < 1e-3 && (b - d).distance < 1e-3) ||
      ((a - d).distance < 1e-3 && (b - c).distance < 1e-3);
}

bool _collinearOverlap(Offset a, Offset b, Offset c, Offset d) {
  if (_distanceToSegment(a, c, d) > 1e-2 && _distanceToSegment(c, a, b) > 1e-2) {
    return false;
  }
  if (_distanceToSegment(b, c, d) > 1e-2 && _distanceToSegment(d, a, b) > 1e-2) {
    return false;
  }
  final ab = b - a;
  final cd = d - c;
  final cross = ab.dx * cd.dy - ab.dy * cd.dx;
  if (cross.abs() > 1e-2 * math.max(ab.distance, 1)) return false;
  return true;
}
