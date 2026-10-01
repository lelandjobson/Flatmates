import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import 'fold.dart';

/// How leftover paper leaves the sheet at the end of a level.
enum ScrapTallyStyle { shrink, shrinkThenFly, fly }

/// What a split did to the pieces it created.
class FreshPieces {
  const FreshPieces({
    required this.carriers,
    required this.scraps,
    required this.freed,
    required this.smallest,
  });

  /// New pieces that still hold an unsolved blueprint piece.
  final List<PapercutPiece> carriers;

  /// New pieces with no blueprint left on them.
  final List<PapercutPiece> scraps;

  /// New pieces that are an exact cut-out of a blueprint piece.
  final List<PapercutPiece> freed;

  /// Smallest new piece by area. Flashed when [discardsBlueprint].
  final PapercutPiece? smallest;

  /// Two new pieces each still hold an unsolved blueprint piece.
  bool get discardsBlueprint => carriers.length > 1;
}

/// Classifies the pieces a cut created.
///
/// A piece carries a closed ring when that ring still has area in the paper.
/// An exact cut-out is freed. A ring that only shares the paper's outline,
/// with every touching point of its curve on the perimeter, does not carry:
/// that paper is scrap. Anything else created by the cut is scrap too.
FreshPieces classifyFreshPieces({
  required PapercutSheet before,
  required PapercutSheet after,
  required List<List<Offset>> closedRings,
}) {
  final oldIds = {for (final piece in before.pieces) piece.id};
  final fresh = [
    for (final piece in after.pieces)
      if (!oldIds.contains(piece.id)) piece,
  ];
  final matched = <int>{};
  final freedIds = <String>{};
  for (var i = 0; i < closedRings.length; i++) {
    final piece = paperMatchingRing(closedRings[i], after);
    if (piece == null) continue;
    matched.add(i);
    if (!oldIds.contains(piece.id)) freedIds.add(piece.id);
  }
  final carriers = <PapercutPiece>[];
  final scraps = <PapercutPiece>[];
  for (final piece in fresh) {
    var carries = false;
    for (var i = 0; i < closedRings.length; i++) {
      if (matched.contains(i)) continue;
      if (_carriesRing(piece, closedRings[i])) {
        carries = true;
        break;
      }
    }
    if (carries) {
      carriers.add(piece);
    } else if (!freedIds.contains(piece.id)) {
      scraps.add(piece);
    }
  }
  PapercutPiece? smallest;
  var best = double.infinity;
  for (final piece in fresh) {
    final area = polygonSignedArea(piece.vertices).abs();
    if (area >= best) continue;
    best = area;
    smallest = piece;
  }
  return FreshPieces(
    carriers: carriers,
    scraps: scraps,
    freed: [
      for (final piece in fresh)
        if (freedIds.contains(piece.id)) piece,
    ],
    smallest: smallest,
  );
}

/// The ring still occupies [piece] when its curve enters the paper, or the
/// paper's interior crosses the ring. Points that only lie on the perimeter
/// are a shared edge, not blueprint area.
bool _carriesRing(PapercutPiece piece, List<Offset> ring) {
  if (ring.length < 3 || piece.vertices.length < 3) return false;
  var touched = false;
  var outlineOnly = true;
  for (final point in _curveSamples(ring)) {
    if (!_touchesPiece(piece, point)) continue;
    touched = true;
    if (!_onPiecePerimeter(piece, point)) outlineOnly = false;
  }
  if (touched && !outlineOnly) return true;
  return _interiorCrossesRing(piece, ring);
}

/// Samples along each straight edge. A chord that cuts through paper shows
/// up between its endpoints.
Iterable<Offset> _curveSamples(List<Offset> ring) sync* {
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    yield a;
    yield Offset.lerp(a, b, 0.25)!;
    yield Offset.lerp(a, b, 0.5)!;
    yield Offset.lerp(a, b, 0.75)!;
  }
}

bool _touchesPiece(PapercutPiece piece, Offset point) {
  final onOuter = _onRing(point, piece.vertices);
  if (!onOuter && !isInsidePolygon(point, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (hole.length < 3) continue;
    if (_onRing(point, hole)) return true;
    if (isInsidePolygon(point, hole)) return false;
  }
  return true;
}

bool _onPiecePerimeter(PapercutPiece piece, Offset point) {
  if (_onRing(point, piece.vertices)) return true;
  for (final hole in piece.holes) {
    if (_onRing(point, hole)) return true;
  }
  return false;
}

/// An interior point of [piece] that sits inside [ring] means the cut kept
/// blueprint area, even when the ring's curve only rides the outline.
bool _interiorCrossesRing(PapercutPiece piece, List<Offset> ring) {
  final center = polygonCentroid(piece.vertices);
  if (_strictlyInsidePiece(piece, center) && _strictlyInside(center, ring)) {
    return true;
  }
  if (_insetCrosses(piece.vertices, piece, ring)) return true;
  for (final hole in piece.holes) {
    if (_insetCrosses(hole, piece, ring)) return true;
  }
  return false;
}

bool _insetCrosses(List<Offset> loop, PapercutPiece piece, List<Offset> ring) {
  if (loop.length < 3) return false;
  for (var i = 0; i < loop.length; i++) {
    final probe = _insetProbe(loop, i, piece);
    if (probe != null && _strictlyInside(probe, ring)) return true;
  }
  return false;
}

/// A point just inside [piece] from the midpoint of edge [i].
Offset? _insetProbe(List<Offset> loop, int i, PapercutPiece piece) {
  final a = loop[i];
  final b = loop[(i + 1) % loop.length];
  final mid = Offset.lerp(a, b, 0.5)!;
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len = math.sqrt(dx * dx + dy * dy);
  if (len < _kEdgeEps) return null;
  final nx = -dy / len * _kInset;
  final ny = dx / len * _kInset;
  final left = mid + Offset(nx, ny);
  final right = mid - Offset(nx, ny);
  if (_strictlyInsidePiece(piece, left)) return left;
  if (_strictlyInsidePiece(piece, right)) return right;
  return null;
}

bool _strictlyInsidePiece(PapercutPiece piece, Offset point) {
  if (!_strictlyInside(point, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (hole.length < 3) continue;
    if (_onRing(point, hole) || isInsidePolygon(point, hole)) return false;
  }
  return true;
}

bool _strictlyInside(Offset point, List<Offset> ring) {
  if (_onRing(point, ring)) return false;
  return isInsidePolygon(point, ring);
}

bool _onRing(Offset point, List<Offset> ring) {
  if (ring.length < 2) return false;
  for (var i = 0; i < ring.length; i++) {
    if (_distanceToSegment(point, ring[i], ring[(i + 1) % ring.length]) <=
        _kEdgeEps) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final dx = b.dx - a.dx;
  final dy = b.dy - a.dy;
  final len2 = dx * dx + dy * dy;
  if (len2 < _kEdgeEps * _kEdgeEps) return (point - a).distance;
  final t = ((point.dx - a.dx) * dx + (point.dy - a.dy) * dy) / len2;
  final clamped = t.clamp(0.0, 1.0);
  final closest = Offset(a.dx + dx * clamped, a.dy + dy * clamped);
  return (point - closest).distance;
}

const double _kEdgeEps = 1e-3;
const double _kInset = 1e-2;

bool _ownsCenter(PapercutPiece piece, Offset center) {
  if (!isInsidePolygon(center, piece.vertices)) return false;
  for (final hole in piece.holes) {
    if (hole.length < 3) continue;
    if (isInsidePolygon(center, hole)) return false;
  }
  return true;
}

/// Unit-cell centers on leftover paper, top-left to bottom-right.
///
/// World +Y is up, so the first row is the highest Y, and a row runs toward
/// +X. A cell counts when its center is in a piece that is not a freed
/// blueprint piece. [spacing] is the cell size.
List<Offset> leftoverCells({
  required Iterable<PapercutPiece> pieces,
  required Set<String> freedIds,
  required double spacing,
}) {
  if (spacing <= 0) return const [];
  final cells = <Offset>[];
  for (final piece in pieces) {
    if (freedIds.contains(piece.id)) continue;
    final bounds = _drawnBounds(piece);
    if (bounds == null) continue;
    final x0 = (bounds.left / spacing).floor();
    final x1 = (bounds.right / spacing).ceil();
    final y0 = (bounds.top / spacing).floor();
    final y1 = (bounds.bottom / spacing).ceil();
    for (var iy = y0; iy < y1; iy++) {
      for (var ix = x0; ix < x1; ix++) {
        final center = Offset((ix + 0.5) * spacing, (iy + 0.5) * spacing);
        final local = center - piece.separation;
        if (!_ownsCenter(piece, local)) continue;
        cells.add(center);
      }
    }
  }
  cells.sort((a, b) {
    final row = b.dy.compareTo(a.dy);
    if (row != 0) return row;
    return a.dx.compareTo(b.dx);
  });
  return cells;
}

Rect? _drawnBounds(PapercutPiece piece) {
  if (piece.vertices.isEmpty) return null;
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in piece.vertices) {
    final shown = point + piece.separation;
    minX = math.min(minX, shown.dx);
    minY = math.min(minY, shown.dy);
    maxX = math.max(maxX, shown.dx);
    maxY = math.max(maxY, shown.dy);
  }
  if (!minX.isFinite) return null;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Bounds of leftover paper where it is drawn, separation included.
Rect? leftoverBounds(
  Iterable<PapercutPiece> pieces, {
  required Set<String> freedIds,
}) {
  Rect? bounds;
  for (final piece in pieces) {
    if (freedIds.contains(piece.id)) continue;
    final drawn = _drawnBounds(piece);
    if (drawn == null) continue;
    bounds = bounds == null ? drawn : bounds.expandToInclude(drawn);
  }
  return bounds;
}

/// Start and length of each cell so the last one finishes at [total] seconds.
class CellWindow {
  const CellWindow({required this.start, required this.duration});

  final double start;
  final double duration;

  double get end => start + duration;
}

List<CellWindow> tallySchedule(int count, {double total = 3}) {
  if (count <= 0 || total <= 0) return const [];
  final duration = total / count;
  return [
    for (var i = 0; i < count; i++)
      CellWindow(start: i * duration, duration: duration),
  ];
}

/// How many cells have finished by [seconds].
int tallyFinished(List<CellWindow> windows, double seconds) {
  var done = 0;
  for (final window in windows) {
    if (seconds + 1e-9 < window.end) break;
    done++;
  }
  return done;
}

/// Scale about the cell, and how far it has traveled toward the score.
///
/// [fly] is 0 at the cell and 1 at the score. A finished cell has scale 0.
class CellMotion {
  const CellMotion({
    required this.scale,
    required this.fly,
    required this.gone,
  });

  final double scale;
  final double fly;
  final bool gone;
}

CellMotion cellMotion({
  required ScrapTallyStyle style,
  required CellWindow window,
  required double seconds,
}) {
  if (seconds >= window.end - 1e-9) {
    return const CellMotion(scale: 0, fly: 1, gone: true);
  }
  if (seconds <= window.start) {
    return const CellMotion(scale: 1, fly: 0, gone: false);
  }
  final t = ((seconds - window.start) / window.duration).clamp(0.0, 1.0);
  switch (style) {
    case ScrapTallyStyle.shrink:
      return CellMotion(scale: 1 - t, fly: 0, gone: false);
    case ScrapTallyStyle.fly:
      return CellMotion(scale: 1, fly: t, gone: false);
    case ScrapTallyStyle.shrinkThenFly:
      if (t < 0.5) {
        return CellMotion(scale: 1 - t, fly: 0, gone: false);
      }
      return CellMotion(scale: 0.5, fly: (t - 0.5) * 2, gone: false);
  }
}
