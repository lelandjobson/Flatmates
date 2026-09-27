import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import 'blueprint.dart';

const _eps = 1e-4;

/// A scissor parked on the grid. [path] grows until a piece splits off.
class ScissorMarch {
  const ScissorMarch({
    required this.path,
    required this.direction,
    this.locked = false,
  });

  final List<Offset> path;
  final Offset direction;
  final bool locked;

  Offset get position => path.last;

  /// Where the next click will cut to, or null when the ray leaves the sheet.
  ///
  /// [direction] overrides the parked direction. The view passes screen-up so
  /// a roll changes the glowing segment.
  Offset? previewEnd(GridStep step, PapercutSheet sheet, {Offset? direction}) {
    return nextOutlineHit(
      from: position,
      direction: direction ?? this.direction,
      closed: cutOutlines(step, sheet),
      open: sheet.cutStrokes,
    );
  }
}

/// Blueprint outlines and piece boundaries the blade must not cross.
List<List<Offset>> cutOutlines(GridStep step, PapercutSheet sheet) {
  return [
    ...step.polygons,
    for (final piece in sheet.pieces) piece.vertices,
    for (final piece in sheet.pieces) ...piece.holes,
  ];
}

/// First outline hit in front of [from].
///
/// A crossing edge stops the ray. A vertex past that edge is not a target.
/// Traveling along an edge reaches that edge's next vertex.
Offset? nextOutlineHit({
  required Offset from,
  required Offset direction,
  required List<List<Offset>> closed,
  List<List<Offset>> open = const [],
}) {
  final length = direction.distance;
  if (length < 1e-8) return null;
  final ray = direction / length;
  Offset? best;
  var bestT = double.infinity;
  void consider(double t, Offset point) {
    if (t <= _eps || t >= bestT) return;
    bestT = t;
    best = point;
  }

  void walk(List<Offset> ring, {required bool close}) {
    if (ring.length < 2) return;
    final count = close ? ring.length : ring.length - 1;
    for (var i = 0; i < count; i++) {
      _raySegment(from, ray, ring[i], ring[(i + 1) % ring.length], consider);
    }
  }

  for (final ring in closed) {
    walk(ring, close: true);
  }
  for (final stroke in open) {
    walk(stroke, close: false);
  }
  return best;
}

/// Place the blade on a paper-edge grid point, facing into the sheet.
ScissorMarch? placeScissor(Offset point, Rect paper) {
  final direction = _inward(point, paper);
  if (direction == null) return null;
  return ScissorMarch(path: [point], direction: direction);
}

/// Place the blade on [ring], facing into that piece.
ScissorMarch? placeOnRing(Offset point, List<Offset> ring) {
  final direction = inwardOnRing(point, ring);
  if (direction == null) return null;
  return ScissorMarch(path: [point], direction: direction);
}

/// Grid points along a piece outline.
List<Offset> pieceEdgeGridPoints(List<Offset> ring, double spacing) {
  if (spacing <= 0 || ring.length < 2) return const [];
  final points = <Offset>[];
  void add(Offset point) {
    if (points.any((other) => (other - point).distance < _eps)) return;
    points.add(point);
  }

  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final delta = b - a;
    final length = delta.distance;
    if (length < _eps) continue;
    final steps = (length / spacing).round().clamp(1, 10000);
    for (var step = 0; step <= steps; step++) {
      final t = step / steps;
      add(Offset(a.dx + delta.dx * t, a.dy + delta.dy * t));
    }
  }
  return points;
}

/// Grid points that lie on the paper border.
List<Offset> paperEdgeGridPoints(Rect paper, double spacing) {
  if (spacing <= 0) return const [];
  final points = <Offset>[];
  void add(Offset point) {
    if (points.any((other) => (other - point).distance < _eps)) return;
    points.add(point);
  }

  for (var x = paper.left; x <= paper.right + _eps; x += spacing) {
    add(Offset(x, paper.top));
    add(Offset(x, paper.bottom));
  }
  for (var y = paper.top; y <= paper.bottom + _eps; y += spacing) {
    add(Offset(paper.left, y));
    add(Offset(paper.right, y));
  }
  return points;
}

/// Blueprint vertices, cut vertices, and the paper border.
List<Offset> datumsFor(GridStep step, PapercutSheet sheet) {
  return [
    ...step.vertices,
    for (final stroke in sheet.cutStrokes) ...stroke,
    for (final crease in sheet.creases) ...[crease.a, crease.b],
  ];
}

/// Nearest datum ahead of [from] along [direction], or the far paper edge.
Offset? nextDatum({
  required Offset from,
  required Offset direction,
  required Rect paper,
  required List<Offset> datums,
  List<Offset>? boundary,
}) {
  Offset? best;
  var bestDistance = double.infinity;
  void consider(Offset point) {
    final along = _along(from, direction, point);
    if (along == null || along <= _eps || along >= bestDistance) return;
    best = point;
    bestDistance = along;
  }

  for (final datum in datums) {
    consider(datum);
  }
  final exit = boundary == null
      ? _paperExit(from, direction, paper)
      : _ringExit(from, direction, boundary);
  if (exit != null) consider(exit);
  return best;
}

/// Pulls the pieces created by a split off each other by [spacing].
///
/// Earlier pieces keep the nudge they already have. New pieces inherit that
/// and then step apart on the grid axes their centroids differ along.
PapercutSheet spreadPieces(
  PapercutSheet before,
  PapercutSheet after,
  double spacing,
) {
  if (spacing <= 0) return after;
  final oldIds = {for (final piece in before.pieces) piece.id};
  final fresh = <int>[];
  for (var i = 0; i < after.pieces.length; i++) {
    if (!oldIds.contains(after.pieces[i].id)) fresh.add(i);
  }
  if (fresh.length < 2) return after;
  var weight = 0.0;
  var gx = 0.0;
  var gy = 0.0;
  for (final index in fresh) {
    final piece = after.pieces[index];
    final area = polygonSignedArea(piece.vertices).abs();
    final centroid = polygonCentroid(piece.vertices);
    weight += area;
    gx += centroid.dx * area;
    gy += centroid.dy * area;
  }
  if (weight < 1e-8) return after;
  final group = Offset(gx / weight, gy / weight);
  return PapercutSheet(
    pieces: [
      for (var i = 0; i < after.pieces.length; i++)
        if (!fresh.contains(i))
          after.pieces[i]
        else
          after.pieces[i].copyWith(
            separation:
                after.pieces[i].separation +
                _nudge(polygonCentroid(after.pieces[i].vertices) - group, spacing),
          ),
    ],
    cutStrokes: after.cutStrokes,
    creases: after.creases,
    nextPieceId: after.nextPieceId,
  );
}

Offset _nudge(Offset delta, double spacing) {
  // Two cells each way, so the shared cut opens into a four-cell gap.
  final step = spacing * 2;
  final x = delta.dx.abs() < 1e-3 ? 0.0 : step * delta.dx.sign;
  final y = delta.dy.abs() < 1e-3 ? 0.0 : step * delta.dy.sign;
  return Offset(x, y);
}

class ScissorCommit {
  const ScissorCommit({required this.sheet, required this.march});

  final PapercutSheet sheet;
  final ScissorMarch? march;
}

/// Cuts from the march start through the next datum on [base].
///
/// The march stays locked once the blade has entered paper, until the piece
/// count grows.
ScissorCommit? commitScissor({
  required ScissorMarch march,
  required GridStep step,
  required PapercutSheet base,
  Offset? direction,
}) {
  final dir = direction ?? march.direction;
  final aimed = ScissorMarch(
    path: march.path,
    direction: dir,
    locked: march.locked,
  );
  final end = aimed.previewEnd(step, base);
  if (end == null) return null;
  final path = [...march.path, end];
  final cut = applyPapercutCut(base, path);
  if (cut == null) return null;
  final split = cut.pieces.length > base.pieces.length;
  if (split) {
    return ScissorCommit(sheet: cut, march: null);
  }
  final entered = _entersPieces(march.position, end, base.pieces);
  return ScissorCommit(
    sheet: cut,
    march: ScissorMarch(
      path: path,
      direction: dir,
      locked: march.locked || entered,
    ),
  );
}

/// Cut or fold span on the vertical grid line through [contact].
(Offset, Offset)? verticalSpan({
  required Offset contact,
  required GridStep step,
  required PapercutSheet sheet,
}) {
  final x = contact.dx;
  final marks = <double>[step.paper.top, step.paper.bottom];
  for (final datum in datumsFor(step, sheet)) {
    if ((datum.dx - x).abs() > _eps) continue;
    marks.add(datum.dy);
  }
  marks.sort();
  double? below;
  double? above;
  for (final y in marks) {
    if (y < contact.dy - _eps) below = y;
    if (y > contact.dy + _eps) {
      above = y;
      break;
    }
  }
  if (below == null || above == null) return null;
  return (Offset(x, below), Offset(x, above));
}

Offset? _inward(Offset point, Rect paper) {
  final onLeft = (point.dx - paper.left).abs() < _eps;
  final onRight = (point.dx - paper.right).abs() < _eps;
  final onBottom = (point.dy - paper.top).abs() < _eps;
  final onTop = (point.dy - paper.bottom).abs() < _eps;
  if (!onLeft && !onRight && !onBottom && !onTop) return null;
  if (onBottom && !onLeft && !onRight) return const Offset(0, 1);
  if (onTop && !onLeft && !onRight) return const Offset(0, -1);
  if (onLeft && !onBottom && !onTop) return const Offset(1, 0);
  if (onRight && !onBottom && !onTop) return const Offset(-1, 0);
  if (onBottom) return const Offset(0, 1);
  if (onTop) return const Offset(0, -1);
  if (onLeft) return const Offset(1, 0);
  return const Offset(-1, 0);
}

void _raySegment(
  Offset from,
  Offset ray,
  Offset a,
  Offset b,
  void Function(double t, Offset point) consider,
) {
  final edge = b - a;
  final denom = ray.dx * edge.dy - ray.dy * edge.dx;
  final rel = a - from;
  if (denom.abs() < 1e-8) {
    final cross = rel.dx * ray.dy - rel.dy * ray.dx;
    if (cross.abs() > 1e-3) return;
    final ta = rel.dx * ray.dx + rel.dy * ray.dy;
    final tb = (b.dx - from.dx) * ray.dx + (b.dy - from.dy) * ray.dy;
    if (ta > _eps) consider(ta, a);
    if (tb > _eps) consider(tb, b);
    return;
  }
  final t = (rel.dx * edge.dy - rel.dy * edge.dx) / denom;
  final u = (rel.dx * ray.dy - rel.dy * ray.dx) / denom;
  if (t <= _eps || u < -1e-4 || u > 1 + 1e-4) return;
  consider(t, Offset(from.dx + ray.dx * t, from.dy + ray.dy * t));
}

double? _along(Offset from, Offset direction, Offset point) {
  final rel = point - from;
  final cross = rel.dx * direction.dy - rel.dy * direction.dx;
  if (cross.abs() > 1e-3) return null;
  return rel.dx * direction.dx + rel.dy * direction.dy;
}

Offset? _paperExit(Offset from, Offset direction, Rect paper) {
  var best = double.infinity;
  Offset? hit;
  void consider(double t, Offset point) {
    if (t <= _eps || t >= best) return;
    if (!_onRect(point, paper)) return;
    best = t;
    hit = point;
  }

  if (direction.dx.abs() > 0.5) {
    final x = direction.dx > 0 ? paper.right : paper.left;
    final t = (x - from.dx) / direction.dx;
    consider(t, Offset(x, from.dy));
  }
  if (direction.dy.abs() > 0.5) {
    final y = direction.dy > 0 ? paper.bottom : paper.top;
    final t = (y - from.dy) / direction.dy;
    consider(t, Offset(from.dx, y));
  }
  return hit;
}

bool _onRect(Offset point, Rect paper) {
  final insideX = point.dx >= paper.left - _eps && point.dx <= paper.right + _eps;
  final insideY = point.dy >= paper.top - _eps && point.dy <= paper.bottom + _eps;
  if (!insideX || !insideY) return false;
  final onEdge =
      (point.dx - paper.left).abs() < _eps ||
      (point.dx - paper.right).abs() < _eps ||
      (point.dy - paper.top).abs() < _eps ||
      (point.dy - paper.bottom).abs() < _eps;
  return onEdge;
}

bool _entersPieces(Offset a, Offset b, List<PapercutPiece> pieces) {
  final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
  for (final piece in pieces) {
    if (isInsidePolygon(mid, piece.vertices)) return true;
  }
  return false;
}

/// Piece the blade will enter, or the piece whose outline contains [point].
PapercutPiece? pieceFacing(
  Offset point,
  Offset direction,
  List<PapercutPiece> pieces,
) {
  PapercutPiece? touching;
  final probe = point + direction * 0.05;
  for (final piece in pieces) {
    if (!ownsPoint(piece.vertices, point)) continue;
    touching ??= piece;
    if (isInsidePolygon(probe, piece.vertices)) return piece;
  }
  return touching;
}

bool ownsPoint(List<Offset> ring, Offset point) {
  if (isInsidePolygon(point, ring)) return true;
  return _distanceToRing(point, ring) <= 1e-3;
}

double _distanceToRing(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final delta = b - a;
    final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
    if (len2 < 1e-12) {
      final distance = (point - a).distance;
      if (distance < best) best = distance;
      continue;
    }
    final t = (((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2)
        .clamp(0.0, 1.0);
    final closest = Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
    final distance = (point - closest).distance;
    if (distance < best) best = distance;
  }
  return best;
}

/// Axis direction into [ring] from a point on its boundary.
Offset? inwardOnRing(Offset point, List<Offset> ring) {
  if (ring.length < 3) return null;
  final area = polygonSignedArea(ring);
  if (area.abs() < 1e-8) return null;
  final sign = area > 0 ? 1.0 : -1.0;
  final candidates = <Offset>[];
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    if (_distanceToSegment(point, a, b) > 1e-3) continue;
    final along = _segmentT(point, a, b);
    if (along < -1e-3 || along > 1 + 1e-3) continue;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final nx = -dy * sign;
    final ny = dx * sign;
    if (nx.abs() < 1e-8 && ny.abs() < 1e-8) continue;
    if (nx.abs() >= ny.abs()) {
      candidates.add(Offset(nx.sign, 0));
    } else {
      candidates.add(Offset(0, ny.sign));
    }
  }
  if (candidates.isEmpty) return null;
  const priority = [Offset(0, 1), Offset(0, -1), Offset(1, 0), Offset(-1, 0)];
  for (final preferred in priority) {
    if (candidates.any((candidate) => candidate == preferred)) return preferred;
  }
  return candidates.first;
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final delta = b - a;
  final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
  if (len2 < 1e-12) return (point - a).distance;
  final t = (((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2)
      .clamp(0.0, 1.0);
  final closest = Offset(a.dx + delta.dx * t, a.dy + delta.dy * t);
  return (point - closest).distance;
}

double _segmentT(Offset point, Offset a, Offset b) {
  final delta = b - a;
  final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
  if (len2 < 1e-12) return 0;
  return ((point.dx - a.dx) * delta.dx + (point.dy - a.dy) * delta.dy) / len2;
}

Offset? _ringExit(Offset from, Offset direction, List<Offset> ring) {
  var best = double.infinity;
  Offset? hit;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    final t = _rayOnSegment(from, direction, a, b);
    if (t == null || t >= best) continue;
    best = t;
    hit = Offset(from.dx + direction.dx * t, from.dy + direction.dy * t);
  }
  return hit;
}

double? _rayOnSegment(Offset from, Offset direction, Offset p, Offset q) {
  final dxb = q.dx - p.dx;
  final dyb = q.dy - p.dy;
  final denom = direction.dx * dyb - direction.dy * dxb;
  if (denom.abs() < 1e-9) return null;
  final wx = from.dx - p.dx;
  final wy = from.dy - p.dy;
  final t = (dxb * wy - dyb * wx) / denom;
  final u = (direction.dx * wy - direction.dy * wx) / denom;
  if (t <= _eps) return null;
  if (u < -1e-3 || u > 1 + 1e-3) return null;
  return t;
}
