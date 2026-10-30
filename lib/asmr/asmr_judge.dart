import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui';

import 'asmr_net.dart';
import 'asmr_piece.dart';

/// How far a cut may stray from a blueprint edge, in desk units. A cube
/// face is 50 across. Up to [kAsmrJudgePerfect] is perfect; past
/// [kAsmrJudgeAcceptable] the edge does not count as cut at all.
const double kAsmrJudgePerfect = 0.4;
const double kAsmrJudgeGood = 1.0;
const double kAsmrJudgeFair = 2.0;
const double kAsmrJudgeAcceptable = 3.5;

/// Desk units between the points sampled along a blueprint edge.
const double kAsmrJudgeStep = 1.0;

/// Samples stay this far from an edge's ends, where two edges meet and a
/// corner cut a little round still counts.
const double kAsmrJudgeInset = 0.5;

const Color kAsmrJudgePerfectColor = Color(0xFF4FC3F7);
const Color kAsmrJudgeGoodColor = Color(0xFF5BE08A);
const Color kAsmrJudgeFairColor = Color(0xFFFFD54F);
const Color kAsmrJudgeAcceptableColor = Color(0xFFFF8A3D);

const double _kCell = 4;

/// Blue for a perfect cut, through green and yellow, to orange for one that
/// is bad but still acceptable.
Color asmrJudgeColor(double error) {
  const stops = [
    (kAsmrJudgePerfect, kAsmrJudgePerfectColor),
    (kAsmrJudgeGood, kAsmrJudgeGoodColor),
    (kAsmrJudgeFair, kAsmrJudgeFairColor),
    (kAsmrJudgeAcceptable, kAsmrJudgeAcceptableColor),
  ];
  if (error <= stops.first.$1) return stops.first.$2;
  for (var i = 1; i < stops.length; i++) {
    final (to, toColor) = stops[i];
    if (error > to) continue;
    final (from, fromColor) = stops[i - 1];
    return Color.lerp(fromColor, toColor, (error - from) / (to - from))!;
  }
  return stops.last.$2;
}

/// How closely paper follows one blueprint edge: the mean and the worst
/// distance from its samples to the nearest paper edge, in desk units.
class AsmrEdgeJudgement {
  const AsmrEdgeJudgement({required this.mean, required this.worst});

  final double mean;
  final double worst;

  Color get color => asmrJudgeColor(mean);
}

/// Points along [a]–[b], [step] apart, [inset] in from each end. A segment
/// too short for that gives its midpoint.
List<Offset> asmrEdgeSamples(
  Offset a,
  Offset b, {
  double step = kAsmrJudgeStep,
  double inset = kAsmrJudgeInset,
}) {
  final length = (b - a).distance;
  final run = length - inset * 2;
  if (run <= 1e-9) return [(a + b) / 2];
  final dir = (b - a) / length;
  final n = math.max(1, (run / step).ceil());
  return [for (var i = 0; i <= n; i++) a + dir * (inset + run * i / n)];
}

/// Distance from [p] to segment [a]–[b]: the closest point is the projection
/// of [p] onto the segment's line, clamped to the segment.
double distanceToSegment(Offset p, Offset a, Offset b) {
  final abx = b.dx - a.dx;
  final aby = b.dy - a.dy;
  final len2 = abx * abx + aby * aby;
  if (len2 < 1e-12) return (p - a).distance;
  final t = (((p.dx - a.dx) * abx + (p.dy - a.dy) * aby) / len2).clamp(
    0.0,
    1.0,
  );
  final dx = p.dx - (a.dx + abx * t);
  final dy = p.dy - (a.dy + aby * t);
  return math.sqrt(dx * dx + dy * dy);
}

class _Segment {
  const _Segment(this.a, this.b, this.owner);

  final Offset a;
  final Offset b;
  final Object owner;
}

/// Segments bucketed into square cells, for nearest-edge lookups that only
/// look at the cells around a point.
class _SegmentGrid {
  final Map<int, List<_Segment>> _cells = {};

  static int _key(int x, int y) => x * 1048583 + y;

  static int _cell(double v) => (v / _kCell).floor();

  /// Cell keys [a]–[b] passes through, by its bounding box.
  static List<int> _cellsOf(Offset a, Offset b) {
    final x0 = _cell(math.min(a.dx, b.dx));
    final x1 = _cell(math.max(a.dx, b.dx));
    final y0 = _cell(math.min(a.dy, b.dy));
    final y1 = _cell(math.max(a.dy, b.dy));
    return [
      for (var x = x0; x <= x1; x++)
        for (var y = y0; y <= y1; y++) _key(x, y),
    ];
  }

  void add(_Segment segment) {
    for (final key in _cellsOf(segment.a, segment.b)) {
      (_cells[key] ??= []).add(segment);
    }
  }

  void removeOwner(Object owner, Iterable<_Segment> segments) {
    for (final segment in segments) {
      for (final key in _cellsOf(segment.a, segment.b)) {
        final cell = _cells[key];
        if (cell == null) continue;
        cell.removeWhere((s) => identical(s.owner, owner));
        if (cell.isEmpty) _cells.remove(key);
      }
    }
  }

  /// Distance from [p] to the nearest segment no farther than [within], or
  /// null when there is none that close.
  double? nearest(Offset p, double within) {
    final x0 = _cell(p.dx - within);
    final x1 = _cell(p.dx + within);
    final y0 = _cell(p.dy - within);
    final y1 = _cell(p.dy + within);
    double? best;
    for (var x = x0; x <= x1; x++) {
      for (var y = y0; y <= y1; y++) {
        final cell = _cells[_key(x, y)];
        if (cell == null) continue;
        for (final s in cell) {
          final d = distanceToSegment(p, s.a, s.b);
          if (d <= within && (best == null || d < best)) best = d;
        }
      }
    }
    return best;
  }
}

final Expando<List<_Segment>> _segmentCache = Expando();
final Expando<Rect> _boundsCache = Expando();

/// The edges of [piece] on the desk: its outline, its holes, and the scores
/// cut into it so far. Kept per piece, which never changes.
List<_Segment> _segmentsOf(AsmrPiece piece) => _segmentCache[piece] ??= [
  for (final ring in [piece.deskRing, ...piece.deskHoles])
    for (var i = 0; i < ring.length; i++)
      _Segment(ring[i], ring[(i + 1) % ring.length], piece),
  for (final score in piece.scores)
    for (var i = 0; i + 1 < score.length; i++)
      _Segment(piece.toDesk(score[i]), piece.toDesk(score[i + 1]), piece),
];

Rect _boundsOf(AsmrPiece piece) => _boundsCache[piece] ??= () {
  final segments = _segmentsOf(piece);
  if (segments.isEmpty) {
    return Rect.fromCenter(center: piece.position, width: 0, height: 0);
  }
  var rect = Rect.fromPoints(segments.first.a, segments.first.b);
  for (final s in segments) {
    rect = rect.expandToInclude(Rect.fromPoints(s.a, s.b));
  }
  return rect;
}();

/// Every paper edge on the desk, for finding the one nearest a point. It
/// follows the desk piece by piece, so a cut only reindexes what it changed.
class PaperEdgeIndex {
  final _SegmentGrid _grid = _SegmentGrid();
  final Set<AsmrPiece> _pieces = HashSet.identity();

  /// Brings the index up to [pieces]. Returns the desk area that changed,
  /// the pieces that went away and the ones that came, or null if none did.
  Rect? sync(Iterable<AsmrPiece> pieces) {
    final next = HashSet<AsmrPiece>.identity()..addAll(pieces);
    Rect? dirty;
    void touch(AsmrPiece piece) {
      final box = _boundsOf(piece);
      dirty = dirty?.expandToInclude(box) ?? box;
    }

    for (final piece in _pieces.where((p) => !next.contains(p)).toList()) {
      _grid.removeOwner(piece, _segmentsOf(piece));
      _pieces.remove(piece);
      touch(piece);
    }
    for (final piece in next) {
      if (_pieces.contains(piece)) continue;
      _segmentsOf(piece).forEach(_grid.add);
      _pieces.add(piece);
      touch(piece);
    }
    return dirty;
  }

  double? nearest(Offset p, {double within = kAsmrJudgeAcceptable}) =>
      _grid.nearest(p, within);
}

/// Judges each cut edge of a blueprint against the paper on the desk. After
/// the first look, only edges near paper that changed are judged again.
class AsmrJudge {
  final PaperEdgeIndex _index = PaperEdgeIndex();
  AsmrNet _net = AsmrNet.empty;
  final Map<String, List<Offset>> _samples = {};
  final Map<String, Rect> _edgeBounds = {};
  final Map<String, AsmrEdgeJudgement> _judged = {};

  /// Edge key to how well it is cut. Edges not cut yet are missing.
  Map<String, AsmrEdgeJudgement> get judged => UnmodifiableMapView(_judged);

  AsmrEdgeJudgement? of(String key) => _judged[key];

  /// Brings the judgements up to [net] and the desk's [pieces]. Returns the
  /// keys of the edges that were judged again.
  Set<String> update(AsmrNet net, Iterable<AsmrPiece> pieces) {
    final dirty = _index.sync(pieces);
    if (!identical(net, _net)) {
      _net = net;
      _samples.clear();
      _edgeBounds.clear();
      _judged.clear();
      for (final edge in net.edges) {
        if (edge.fold) continue;
        _samples[edge.key] = asmrEdgeSamples(edge.a, edge.b);
        _edgeBounds[edge.key] = Rect.fromPoints(edge.a, edge.b);
      }
      _samples.keys.forEach(_rejudge);
      return _samples.keys.toSet();
    }
    if (dirty == null) return const {};
    final near = dirty.inflate(kAsmrJudgeAcceptable);
    final again = {
      for (final entry in _edgeBounds.entries)
        if (entry.value.overlaps(near)) entry.key,
    };
    again.forEach(_rejudge);
    return again;
  }

  void _rejudge(String key) {
    final samples = _samples[key];
    if (samples == null || samples.isEmpty) return;
    var sum = 0.0;
    var worst = 0.0;
    for (final p in samples) {
      final d = _index.nearest(p);
      if (d == null) {
        _judged.remove(key);
        return;
      }
      sum += d;
      worst = math.max(worst, d);
    }
    _judged[key] = AsmrEdgeJudgement(mean: sum / samples.length, worst: worst);
  }
}

/// Whether [piece] is a close-enough cut of one island of [net]: every
/// sample along that island's outline is within [tolerance] of the piece's
/// edge, and every sample along the piece's outline is within [tolerance]
/// of the island's, so a piece cut too big does not pass. Returns the
/// outline it matches, or null.
List<Offset>? asmrMatchedOutline(
  AsmrPiece piece,
  AsmrNet net, {
  double tolerance = kAsmrJudgeAcceptable,
}) {
  if (net.isEmpty) return null;
  final box = _boundsOf(piece).inflate(tolerance);
  final ring = piece.deskRing;
  final paper = _SegmentGrid();
  for (var i = 0; i < ring.length; i++) {
    paper.add(_Segment(ring[i], ring[(i + 1) % ring.length], piece));
  }
  for (final outline in net.outlines) {
    if (outline.length < 3) continue;
    var outlineBox = Rect.fromPoints(outline.first, outline.first);
    for (final p in outline) {
      outlineBox = outlineBox.expandToInclude(Rect.fromPoints(p, p));
    }
    if (!box.overlaps(outlineBox)) continue;
    var along = true;
    for (var i = 0; i < outline.length && along; i++) {
      final a = outline[i];
      final b = outline[(i + 1) % outline.length];
      for (final p in asmrEdgeSamples(a, b)) {
        if (paper.nearest(p, tolerance) == null) {
          along = false;
          break;
        }
      }
    }
    if (!along) continue;
    final blueprint = _SegmentGrid();
    for (var i = 0; i < outline.length; i++) {
      blueprint.add(
        _Segment(outline[i], outline[(i + 1) % outline.length], outline),
      );
    }
    var inside = true;
    for (var i = 0; i < ring.length && inside; i++) {
      final a = ring[i];
      final b = ring[(i + 1) % ring.length];
      for (final p in asmrEdgeSamples(a, b, inset: 0)) {
        if (blueprint.nearest(p, tolerance) == null) {
          inside = false;
          break;
        }
      }
    }
    if (inside) return outline;
  }
  return null;
}

final Expando<Map<AsmrNet, double>> _submissionCache = Expando();

/// Fraction of acceptable outline edges on the best matching blueprint island.
/// Only physical boundaries count: scores alone cannot submit an uncut sheet.
/// There is no reverse-outline requirement, so overhangs and missing portions
/// are allowed. A shared interior probe excludes the leftover frame around a
/// cutout. Cached for immutable piece/net pairs, including camera-only frames.
double asmrSubmissionQuality(AsmrPiece piece, AsmrNet net) {
  final cache = _submissionCache[piece] ??= {};
  return cache[net] ??= () {
    final paper = _SegmentGrid();
    for (final ring in [piece.deskRing, ...piece.deskHoles]) {
      for (var i = 0; i < ring.length; i++) {
        paper.add(_Segment(ring[i], ring[(i + 1) % ring.length], piece));
      }
    }
    var best = 0.0;
    for (final outline in net.outlines) {
      if (outline.length < 3) continue;
      final inside = Path()..addPolygon(outline, true);
      var good = 0;
      var overlaps = false;
      for (var i = 0; i < outline.length; i++) {
        final a = outline[i];
        final b = outline[(i + 1) % outline.length];
        final delta = b - a;
        if (delta.distance < 1e-9) continue;
        if (asmrEdgeSamples(
          a,
          b,
        ).every((p) => paper.nearest(p, kAsmrJudgeAcceptable) != null)) {
          good++;
          final midpoint = (a + b) / 2;
          final normal = Offset(-delta.dy, delta.dx) / delta.distance;
          for (final depth in [0.25, kAsmrJudgeAcceptable + 0.5]) {
            for (final sign in [-1, 1]) {
              final probe = midpoint + normal * (depth * sign);
              if (inside.contains(probe) && piece.contains(probe)) {
                overlaps = true;
              }
            }
          }
        }
      }
      if (overlaps) best = math.max(best, good / outline.length);
    }
    return best;
  }();
}
