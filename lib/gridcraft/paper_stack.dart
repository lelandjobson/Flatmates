import 'dart:ui';

import '../geometry/polygon_union.dart';
import '../papercut/paper.dart';
import 'fold.dart';

/// Taps on one stack this close together select the next sheet down.
const Duration stackTapInterval = Duration(milliseconds: 300);

/// Opacity of one sheet in a pile of [pages]. A sheet alone stays opaque.
double pageOpacity(int pages) => pages <= 1 ? 1.0 : 1.0 / pages;

/// How many sheets share a pile with each piece, including itself.
///
/// Pieces that only share an edge are not a pile. A fold that lays one sheet
/// on another is.
List<int> pageCounts(PapercutSheet sheet) {
  final count = sheet.pieces.length;
  if (count == 0) return const [];
  final parent = List<int>.generate(count, (index) => index);
  int find(int index) {
    while (parent[index] != index) {
      parent[index] = parent[parent[index]];
      index = parent[index];
    }
    return index;
  }

  void unite(int a, int b) {
    final rootA = find(a);
    final rootB = find(b);
    if (rootA != rootB) parent[rootA] = rootB;
  }

  for (var i = 0; i < count; i++) {
    for (var j = i + 1; j < count; j++) {
      if (_areasOverlap(sheet.pieces[i], sheet.pieces[j], sheet.folds)) {
        unite(i, j);
      }
    }
  }
  final size = List<int>.filled(count, 0);
  for (var i = 0; i < count; i++) {
    size[find(i)]++;
  }
  return [for (var i = 0; i < count; i++) size[find(i)]];
}

/// Piece indexes under [point], front to back.
///
/// Higher fold depth is in front. A tie keeps the later piece, which is the
/// one painted on top.
List<int> piecesUnder(Offset point, PapercutSheet sheet) {
  final hits = <int>[];
  for (var i = 0; i < sheet.pieces.length; i++) {
    if (_contains(sheet.pieces[i], point, sheet.folds)) hits.add(i);
  }
  hits.sort((a, b) {
    final depthA = foldDepth(
      polygonCentroid(sheet.pieces[a].vertices),
      sheet.folds,
    );
    final depthB = foldDepth(
      polygonCentroid(sheet.pieces[b].vertices),
      sheet.folds,
    );
    final byDepth = depthB.compareTo(depthA);
    if (byDepth != 0) return byDepth;
    return b.compareTo(a);
  });
  return hits;
}

/// Index in a front-to-back stack for the [clickCount]-th tap. The first tap
/// is the top sheet. Further taps walk downward, then wrap.
int stackPickIndex(int clickCount, int length) {
  if (length <= 0) return 0;
  final count = clickCount < 1 ? 1 : clickCount;
  return (count - 1) % length;
}

/// Piece a drag should move. The last selection wins when the press is on it,
/// including when a sheet above it hides it.
int? dragTarget(List<int> under, int? selected) {
  if (under.isEmpty) return null;
  if (selected != null && under.contains(selected)) return selected;
  return under.first;
}

/// Click-through selection for stacked sheets.
class PaperStackPick {
  int? selected;
  int _clicks = 0;
  List<int> _stack = const [];
  DateTime? _lastTap;

  void clear() {
    selected = null;
    _clicks = 0;
    _stack = const [];
    _lastTap = null;
  }

  /// Keeps [index] without treating the next tap as a continuation.
  void adopt(int? index) {
    selected = index;
    _clicks = index == null ? 0 : 1;
    _stack = index == null ? const [] : [index];
    _lastTap = null;
  }

  /// Pointer down. Does not walk to the next sheet.
  int? press(Offset point, PapercutSheet sheet) {
    final under = piecesUnder(point, sheet);
    final target = dragTarget(under, selected);
    if (target == null) return null;
    if (selected == null || !under.contains(selected)) {
      selected = target;
      _clicks = 1;
      _stack = under;
    }
    return target;
  }

  /// A tap that did not drag. Repeats on the same stack walk downward.
  int? tap(Offset point, PapercutSheet sheet, DateTime now) {
    final under = piecesUnder(point, sheet);
    if (under.isEmpty) {
      clear();
      return null;
    }
    final repeat =
        _lastTap != null &&
        now.difference(_lastTap!) <= stackTapInterval &&
        _sameStack(_stack, under);
    _clicks = repeat ? _clicks + 1 : 1;
    _stack = under;
    _lastTap = now;
    selected = under[stackPickIndex(_clicks, under.length)];
    return selected;
  }
}

bool _sameStack(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  final other = b.toSet();
  return a.every(other.contains);
}

bool _contains(PapercutPiece piece, Offset point, List<FoldJoint> folds) {
  final ring = shownRing(piece.vertices, piece.separation, folds);
  if (ring.length < 3 || !isInsidePolygon(point, ring)) return false;
  for (final hole in piece.holes) {
    final drawn = shownRing(hole, piece.separation, folds);
    if (drawn.length >= 3 && isInsidePolygon(point, drawn)) return false;
  }
  return true;
}

bool _areasOverlap(PapercutPiece a, PapercutPiece b, List<FoldJoint> folds) {
  final ringA = shownRing(a.vertices, a.separation, folds);
  final ringB = shownRing(b.vertices, b.separation, folds);
  if (ringA.length < 3 || ringB.length < 3) return false;
  if (_strictInside(polygonCentroid(ringA), ringB)) return true;
  if (_strictInside(polygonCentroid(ringB), ringA)) return true;
  for (var i = 0; i < ringA.length; i++) {
    final start = ringA[i];
    final end = ringA[(i + 1) % ringA.length];
    if (_strictInside(start, ringB)) return true;
    for (var k = 0; k < ringB.length; k++) {
      if (_properCross(start, end, ringB[k], ringB[(k + 1) % ringB.length])) {
        return true;
      }
    }
  }
  for (final point in ringB) {
    if (_strictInside(point, ringA)) return true;
  }
  return false;
}

bool _strictInside(Offset point, List<Offset> ring) {
  if (ring.length < 3 || !isInsidePolygon(point, ring)) return false;
  return _distanceToRing(point, ring) > 1e-3;
}

bool _properCross(Offset a, Offset b, Offset c, Offset d) {
  final ab = b - a;
  final cd = d - c;
  final denom = ab.dx * cd.dy - ab.dy * cd.dx;
  if (denom.abs() < 1e-10) return false;
  final ac = c - a;
  final t = (ac.dx * cd.dy - ac.dy * cd.dx) / denom;
  final u = (ac.dx * ab.dy - ac.dy * ab.dx) / denom;
  return t > 1e-4 && t < 1 - 1e-4 && u > 1e-4 && u < 1 - 1e-4;
}

double _distanceToRing(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final distance = _distanceToSegment(
      point,
      ring[i],
      ring[(i + 1) % ring.length],
    );
    if (distance < best) best = distance;
  }
  return best;
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
