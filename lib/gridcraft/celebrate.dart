import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart';

/// One cell of a cut-out celebration. [row] 0 is the outer band.
class SparkCell {
  const SparkCell({
    required this.at,
    required this.wave,
    required this.row,
    required this.direction,
    this.reach = 1,
  });

  final Offset at;
  final int wave;
  final int row;

  /// Repeatable launch direction, away from the centroid with a sideways kick.
  final Offset direction;

  /// 1, 2, or 4. A mixed share travel twice as far, and the same share twice that.
  final double reach;
}

/// Prepared green-fill and spark burst for one freed paper piece.
class Celebration {
  const Celebration({
    required this.cells,
    required this.rowCount,
    required this.cellSize,
    required this.gridSpacing,
    this.ring = const [],
    this.holes = const [],
  });

  final List<SparkCell> cells;
  final int rowCount;
  final double cellSize;
  final double gridSpacing;

  /// Outline the solid fill paints. Sparks still launch from [cells].
  final List<Offset> ring;
  final List<List<Offset>> holes;

  static const int fillMilliseconds = 250;
  static const int holdMilliseconds = 250;
  static const int burstMilliseconds = 800;
  static const double fillSeconds = fillMilliseconds / 1000;
  static const double holdSeconds = holdMilliseconds / 1000;
  static const double burstSeconds = burstMilliseconds / 1000;
  static const double totalSeconds = fillSeconds + holdSeconds + burstSeconds;
  static const Duration duration = Duration(
    milliseconds: fillMilliseconds + holdMilliseconds + burstMilliseconds,
  );

  /// Leftover paper bursts this far apart once the level is won.
  static const double scrapStaggerSeconds = 0.15;

  static const List<Color> successFill = [
    Color(0xFF69F0AE),
    Color(0xFF1DE9B6),
  ];
  static const List<Color> successSpark = [
    Color(0xFFB9F6CA),
    Color(0xFF00C853),
  ];
}

/// Delay before leftover piece [index] bursts. The first waits one stagger
/// when a blueprint piece is already lighting up, and otherwise starts at once.
double scrapDelay(int index, {required bool afterSuccess}) {
  return (index + (afterSuccess ? 1 : 0)) * Celebration.scrapStaggerSeconds;
}

/// How many inward bands a piece of this shorter side gets.
int celebrationRowCount(double shortestSide) {
  return math.max(1, (shortestSide / 2).round());
}

const List<List<int>> _waveTile = [
  [0, 1, 2, 3],
  [2, 3, 0, 1],
  [1, 0, 3, 2],
  [3, 2, 1, 0],
];

/// Raster of [ring] at 2 cells per grid unit.
///
/// Waves come from a tiled mix, not a scanline. Rows run from the perimeter
/// toward the center. The same ring always produces the same cells.
Celebration prepareCelebration(
  List<Offset> ring, {
  double gridSpacing = 1,
  List<List<Offset>> holes = const [],
}) {
  if (ring.length < 3 || gridSpacing <= 0) {
    return Celebration(
      cells: const [],
      rowCount: 1,
      cellSize: gridSpacing / 2,
      gridSpacing: gridSpacing,
      ring: ring,
      holes: holes,
    );
  }
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
  final cell = gridSpacing / 2;
  final spanX = maxX - minX;
  final spanY = maxY - minY;
  final cols = math.max(1, (spanX / cell).round());
  final rows = math.max(1, (spanY / cell).round());
  final shortest = math.min(spanX, spanY) / gridSpacing;
  final rowCount = celebrationRowCount(shortest);
  final centroid = polygonCentroid(ring);
  final samples = <({Offset at, int wave, double distance, int ix, int iy})>[];
  for (var iy = 0; iy < rows; iy++) {
    for (var ix = 0; ix < cols; ix++) {
      final at = Offset(minX + (ix + 0.5) * cell, minY + (iy + 0.5) * cell);
      if (!isInsidePolygon(at, ring)) continue;
      var buried = false;
      for (final hole in holes) {
        if (hole.length >= 3 && isInsidePolygon(at, hole)) {
          buried = true;
          break;
        }
      }
      if (buried) continue;
      var distance = _ringDistance(at, ring);
      for (final hole in holes) {
        if (hole.length < 2) continue;
        distance = math.min(distance, _ringDistance(at, hole));
      }
      samples.add((
        at: at,
        wave: _waveTile[iy % 4][ix % 4],
        distance: distance,
        ix: ix,
        iy: iy,
      ));
    }
  }
  var maxDistance = 0.0;
  for (final sample in samples) {
    maxDistance = math.max(maxDistance, sample.distance);
  }
  final cells = <SparkCell>[
    for (final sample in samples)
      SparkCell(
        at: sample.at,
        wave: sample.wave,
        row: _rowOf(sample.distance, maxDistance, rowCount),
        direction: _launch(sample.at, centroid, sample.ix, sample.iy),
        reach: sparkReach(sample.ix, sample.iy),
      ),
  ];
  return Celebration(
    cells: cells,
    rowCount: rowCount,
    cellSize: cell,
    gridSpacing: gridSpacing,
    ring: ring,
    holes: holes,
  );
}

int _rowOf(double distance, double maxDistance, int rowCount) {
  if (rowCount <= 1 || maxDistance <= 1e-8) return 0;
  final band = (distance / maxDistance * rowCount).floor();
  return math.min(rowCount - 1, band);
}

Offset _launch(Offset at, Offset centroid, int ix, int iy) {
  final away = at - centroid;
  final length = away.distance;
  final outward = length < 1e-6 ? const Offset(0, 1) : away / length;
  final tangent = Offset(-outward.dy, outward.dx);
  final mix = _hash(ix, iy);
  final kick = outward + tangent * (mix * 0.35);
  final span = kick.distance;
  if (span < 1e-8) return outward;
  return kick / span;
}

/// How far this spark travels compared with the base throw.
///
/// Three in ten go twice as far, and three in ten go twice that. The rest
/// keep the base throw. The same cell always gets the same reach.
double sparkReach(int ix, int iy) {
  final bucket = _mix(ix, iy) % 10;
  if (bucket < 3) return 4;
  if (bucket < 6) return 2;
  return 1;
}

/// Stable value in [-1, 1] from the cell indices.
double _hash(int ix, int iy) {
  return (_mix(ix, iy) % 1000) / 999.0 * 2 - 1;
}

int _mix(int ix, int iy) {
  var n = ix * 374761393 + iy * 668265263;
  n = (n ^ (n >> 13)) * 1274126177;
  return n & 0x7fffffff;
}

double _ringDistance(Offset point, List<Offset> ring) {
  var best = double.infinity;
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    best = math.min(best, _distanceToSegment(point, a, b));
  }
  return best;
}

double _distanceToSegment(Offset point, Offset a, Offset b) {
  final ab = b - a;
  final length2 = ab.dx * ab.dx + ab.dy * ab.dy;
  if (length2 < 1e-12) return (point - a).distance;
  final t = ((point.dx - a.dx) * ab.dx + (point.dy - a.dy) * ab.dy) / length2;
  final clamped = t.clamp(0.0, 1.0);
  final foot = Offset(a.dx + ab.dx * clamped, a.dy + ab.dy * clamped);
  return (point - foot).distance;
}

class CelebrationPlayback {
  const CelebrationPlayback({
    required this.pieceId,
    required this.celebration,
    this.anchor = Offset.zero,
    this.delay = 0,
    this.ink,
    this.burst = false,
  });

  final String pieceId;
  final Celebration celebration;

  /// Separation the piece had when it was cut free. The fill and the burst
  /// stay on that spot instead of following a later nudge.
  final Offset anchor;

  /// Seconds after the clock starts before this piece fills.
  final double delay;

  /// Paper color for a leftover burst. Null keeps the green success gradient.
  final Color? ink;

  /// Leftover paper explodes. A completed blueprint piece only lights green.
  final bool burst;

  double local(double seconds) => seconds - delay;

  /// How long this playback needs on the clock, including its delay.
  double get span =>
      delay + (burst ? Celebration.totalSeconds : Celebration.fillSeconds);

  List<Color> get fillColors {
    final ink = this.ink;
    if (ink == null) return Celebration.successFill;
    return [ink, Color.lerp(ink, const Color(0xFF80DEEA), 0.45)!];
  }

  List<Color> get sparkColors {
    final ink = this.ink;
    if (ink == null) return Celebration.successSpark;
    return [Color.lerp(ink, const Color(0xFFFFFFFF), 0.45)!, ink];
  }
}

Offset sparkPosition(SparkCell cell, double burst, {required double speed}) {
  const drag = 3.0;
  final travel = speed * (1 - math.exp(-drag * burst)) / drag;
  return cell.at + cell.direction * travel;
}
