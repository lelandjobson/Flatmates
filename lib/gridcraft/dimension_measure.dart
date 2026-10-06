import 'dart:ui';

/// Bottom ruler measures world X. Left ruler measures world Y.
enum DimensionAxis { horizontal, vertical }

/// A grab sticks when a vertex's screen projection is this close, in px.
const double kDimensionSnapPx = 18;

/// Vertices within this world distance share a colinear pool.
const double kDimensionColinearEpsilon = 1e-4;

/// Free grabs sit here along the track.
const double kDimensionLowFraction = 0.25;
const double kDimensionHighFraction = 0.75;

/// Hit radius of a grab, in px. A tap inside this is a drag, not a lock.
const double kDimensionGrabRadius = 16;

/// How close a tap must be to the span between the grabs, in px.
const double kDimensionSpanSlop = 18;

/// Opening frame: the longer blueprint span fills this much of its ruler.
const double kDimensionFrameFraction = 0.6;

/// Vertex mark thickness, matching the old dot's diameter.
const double kDimensionMarkWidth = 9;

/// Vertex marks are this many times longer than they are wide.
const double kDimensionMarkLengthScale = 2.5;

/// Dimension-widget ticks are this much larger than the vertex-sized mark.
const double kDimensionWidgetMarkScale = 1.5;

/// Tip width as a fraction of [kDimensionMarkWidth]. The base stays square.
const double kDimensionMarkTipScale = 0.82;

/// One blueprint vertex already projected into the viewport.
class ProjectedVertex {
  const ProjectedVertex({required this.world, required this.screen});

  final Offset world;
  final Offset screen;
}

/// A grab that has stuck to a world coordinate, plus every colinear vertex.
class DimensionSnap {
  const DimensionSnap({
    required this.worldCoordinate,
    required this.screenAlong,
    required this.pool,
  });

  final double worldCoordinate;

  /// Screen position of the nearest vertex on the measured axis.
  final double screenAlong;
  final List<ProjectedVertex> pool;
}

/// Screen segment a ruler's grabs travel along.
class DimensionTrack {
  const DimensionTrack({
    required this.axis,
    required this.start,
    required this.end,
  });

  final DimensionAxis axis;
  final Offset start;
  final Offset end;

  double get length => (end - start).distance;

  Offset at(double fraction) {
    final t = fraction.clamp(0.0, 1.0);
    return Offset(
      start.dx + (end.dx - start.dx) * t,
      start.dy + (end.dy - start.dy) * t,
    );
  }

  /// Fraction of a screen coordinate on the measured axis, clamped to the track.
  double fractionAlong(double screenAlong) {
    final from = axis == DimensionAxis.horizontal ? start.dx : start.dy;
    final to = axis == DimensionAxis.horizontal ? end.dx : end.dy;
    final span = to - from;
    if (span.abs() < 1e-6) return 0;
    return ((screenAlong - from) / span).clamp(0.0, 1.0);
  }
}

/// One handle on a ruler. [world] is null while the grab is free.
class DimensionGrab {
  DimensionGrab({required this.fraction, this.world});

  double fraction;
  double? world;

  bool get stuck => world != null;
}

/// Two-handle ruler. Grabs stay in the order they were created.
class DimensionRuler {
  DimensionRuler(this.axis)
    : grabs = [
        DimensionGrab(fraction: kDimensionLowFraction),
        DimensionGrab(fraction: kDimensionHighFraction),
      ];

  final DimensionAxis axis;
  final List<DimensionGrab> grabs;

  bool get bothStuck => grabs[0].stuck && grabs[1].stuck;

  void reset() {
    grabs[0].fraction = kDimensionLowFraction;
    grabs[0].world = null;
    grabs[1].fraction = kDimensionHighFraction;
    grabs[1].world = null;
  }

  /// Stick the grabs to [low] and [high]. The grab nearer the track start
  /// keeps index 0.
  void stickTo({
    required double low,
    required double high,
    required DimensionTrack track,
    required double? Function(double world) screenAlongOf,
  }) {
    final placed = <(double world, double fraction)>[];
    for (final world in [low, high]) {
      final along = screenAlongOf(world);
      if (along == null) {
        reset();
        return;
      }
      placed.add((world, track.fractionAlong(along)));
    }
    placed.sort((a, b) => a.$2.compareTo(b.$2));
    grabs[0].world = placed[0].$1;
    grabs[0].fraction = placed[0].$2;
    grabs[1].world = placed[1].$1;
    grabs[1].fraction = placed[1].$2;
  }

  /// Drag [index] along [track]. Snaps when a vertex is within [kDimensionSnapPx].
  void moveGrab({
    required int index,
    required double screenAlong,
    required DimensionTrack track,
    required List<ProjectedVertex> vertices,
  }) {
    final grab = grabs[index];
    final hit = nearestSnap(
      axis: axis,
      screenAlong: screenAlong,
      vertices: vertices,
    );
    if (hit == null) {
      grab.world = null;
      grab.fraction = track.fractionAlong(screenAlong);
      return;
    }
    grab.world = hit.worldCoordinate;
    grab.fraction = track.fractionAlong(hit.screenAlong);
  }

  /// Slide stuck grabs with the camera. Resets both when either pool leaves
  /// [viewport]. Returns true when the ruler reset.
  bool followCamera({
    required List<ProjectedVertex> vertices,
    required Rect viewport,
    required DimensionTrack track,
    required double? Function(double world) screenAlongOf,
  }) {
    for (final grab in grabs) {
      final world = grab.world;
      if (world == null) continue;
      final along = screenAlongOf(world);
      final visible = poolInView(
        axis: axis,
        worldCoordinate: world,
        vertices: vertices,
        viewport: viewport,
      );
      if (!visible || along == null) {
        reset();
        return true;
      }
    }
    for (final grab in grabs) {
      final world = grab.world;
      if (world == null) continue;
      final along = screenAlongOf(world);
      if (along == null) continue;
      grab.fraction = track.fractionAlong(along);
    }
    return false;
  }
}

/// A dimension dropped onto the plane. It does not ride the screen.
class LockedDimension {
  const LockedDimension({
    required this.axis,
    required this.low,
    required this.high,
    required this.cross,
  });

  final DimensionAxis axis;

  /// World coordinates of the two grabs on [axis].
  final double low;
  final double high;

  /// World coordinate of the track on the other axis, at the moment of the lock.
  final double cross;
}

/// A stuck grab whose pool should be drawn.
class SnapGuide {
  const SnapGuide({required this.axis, required this.world});

  final DimensionAxis axis;
  final double world;
}

double axisCoordinate(DimensionAxis axis, Offset point) {
  return axis == DimensionAxis.horizontal ? point.dx : point.dy;
}

/// Bounding box of [vertices], or null when there are none.
Rect? vertexBounds(Iterable<Offset> vertices) {
  final points = vertices.iterator;
  if (!points.moveNext()) return null;
  var minX = points.current.dx;
  var maxX = minX;
  var minY = points.current.dy;
  var maxY = minY;
  while (points.moveNext()) {
    final point = points.current;
    if (point.dx < minX) minX = point.dx;
    if (point.dx > maxX) maxX = point.dx;
    if (point.dy < minY) minY = point.dy;
    if (point.dy > maxY) maxY = point.dy;
  }
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Half-height that puts the longer world span on [fraction] of its bar.
///
/// X is measured on [barX] and Y on [barY]. A zero span does not compete.
/// Returns null when neither span can be framed.
double? dimensionFrameHalfHeight({
  required double spanX,
  required double spanY,
  required double barX,
  required double barY,
  required double viewportHeight,
  double fraction = kDimensionFrameFraction,
}) {
  if (viewportHeight < 2 || fraction <= 0) return null;
  double? halfFor(double span, double bar) {
    if (span <= 1e-9 || bar <= 1e-6) return null;
    return span * viewportHeight / (2 * fraction * bar);
  }

  final halfX = halfFor(spanX, barX);
  final halfY = halfFor(spanY, barY);
  if (halfX == null) return halfY;
  if (halfY == null) return halfX;
  return spanX >= spanY ? halfX : halfY;
}

/// Nearest vertex on the measured screen axis, within [threshold] px.
DimensionSnap? nearestSnap({
  required DimensionAxis axis,
  required double screenAlong,
  required List<ProjectedVertex> vertices,
  double threshold = kDimensionSnapPx,
}) {
  ProjectedVertex? best;
  var bestDist = threshold;
  for (final vertex in vertices) {
    final along = axisCoordinate(axis, vertex.screen);
    final dist = (along - screenAlong).abs();
    if (dist > bestDist) continue;
    if (best != null && dist >= bestDist) continue;
    best = vertex;
    bestDist = dist;
  }
  if (best == null) return null;
  final world = axisCoordinate(axis, best.world);
  return DimensionSnap(
    worldCoordinate: world,
    screenAlong: axisCoordinate(axis, best.screen),
    pool: [
      for (final vertex in vertices)
        if ((axisCoordinate(axis, vertex.world) - world).abs() <=
            kDimensionColinearEpsilon)
          vertex,
    ],
  );
}

/// True when at least one vertex in the colinear pool lies inside [viewport].
bool poolInView({
  required DimensionAxis axis,
  required double worldCoordinate,
  required List<ProjectedVertex> vertices,
  required Rect viewport,
}) {
  for (final vertex in vertices) {
    if ((axisCoordinate(axis, vertex.world) - worldCoordinate).abs() >
        kDimensionColinearEpsilon) {
      continue;
    }
    if (dimensionPointInView(vertex.screen, viewport)) return true;
  }
  return false;
}

bool dimensionPointInView(Offset screen, Rect viewport) {
  return screen.dx >= viewport.left &&
      screen.dy >= viewport.top &&
      screen.dx <= viewport.right &&
      screen.dy <= viewport.bottom;
}

/// Null when either grab is free.
LockedDimension? lockDimension(DimensionRuler ruler, double cross) {
  final low = ruler.grabs[0].world;
  final high = ruler.grabs[1].world;
  if (low == null || high == null) return null;
  return LockedDimension(axis: ruler.axis, low: low, high: high, cross: cross);
}

(Offset, Offset) dimensionEndpoints(LockedDimension dimension) {
  if (dimension.axis == DimensionAxis.horizontal) {
    return (
      Offset(dimension.low, dimension.cross),
      Offset(dimension.high, dimension.cross),
    );
  }
  return (
    Offset(dimension.cross, dimension.low),
    Offset(dimension.cross, dimension.high),
  );
}

double dimensionCells(double low, double high, double gridSpacing) {
  final spacing = gridSpacing <= 0 ? 1.0 : gridSpacing;
  return (high - low).abs() / spacing;
}

String formatDimensionCells(double cells) {
  if (!cells.isFinite) return '';
  final rounded = cells.roundToDouble();
  if ((cells - rounded).abs() < 0.02) return rounded.toInt().toString();
  return cells.toStringAsFixed(1);
}

/// Length between two stuck grabs, or "-" while either grab is free.
String dimensionReadout(DimensionRuler ruler, double gridSpacing) {
  final low = ruler.grabs[0].world;
  final high = ruler.grabs[1].world;
  if (low == null || high == null) return '-';
  return formatDimensionCells(dimensionCells(low, high, gridSpacing));
}

/// Distance from [tap] to the segment, or null when the closest point falls
/// outside the segment.
double? spanDistance(Offset a, Offset b, Offset tap) {
  final delta = b - a;
  final len2 = delta.dx * delta.dx + delta.dy * delta.dy;
  if (len2 < 1e-6) {
    final dist = (tap - a).distance;
    return dist;
  }
  final t = ((tap.dx - a.dx) * delta.dx + (tap.dy - a.dy) * delta.dy) / len2;
  if (t < 0 || t > 1) return null;
  return (tap - (a + delta * t)).distance;
}

/// Index of the closest span within [slop], or null.
int? nearestSpan(
  List<({Offset a, Offset b})> spans,
  Offset tap, {
  double slop = kDimensionSpanSlop,
}) {
  int? best;
  var bestDist = slop;
  for (var i = 0; i < spans.length; i++) {
    final dist = spanDistance(spans[i].a, spans[i].b, tap);
    if (dist == null || dist > bestDist) continue;
    if (best != null && dist >= bestDist) continue;
    best = i;
    bestDist = dist;
  }
  return best;
}

/// The open span between two grabs. A tap on a grab is not a lock, unless the
/// grabs are close enough that their hit areas cover the whole span.
bool tapHitsMeasuredSpan(Offset a, Offset b, Offset tap) {
  final dist = spanDistance(a, b, tap);
  if (dist == null || dist > kDimensionSpanSlop) return false;
  if ((a - b).distance <= kDimensionGrabRadius * 2) return true;
  if ((tap - a).distance <= kDimensionGrabRadius) return false;
  if ((tap - b).distance <= kDimensionGrabRadius) return false;
  return true;
}

/// A crop mark at [at], reaching toward [toward].
///
/// The base is centered on [at] and perpendicular to [toward]. The tip is
/// narrower and [kDimensionMarkLengthScale] widths away, in that direction.
/// Corners run base, tip, tip, base.
/// Bottom ticks point up. Left ticks point right, into the page.
Offset dimensionWidgetMarkDirection(DimensionAxis axis) {
  return axis == DimensionAxis.horizontal
      ? const Offset(0, -1)
      : const Offset(1, 0);
}

List<Offset> dimensionCropMark({
  required Offset at,
  required Offset toward,
  double scale = 1,
}) {
  final length = toward.distance;
  final dir = length < 1e-6 ? const Offset(1, 0) : toward / length;
  final side = Offset(-dir.dy, dir.dx);
  final width = kDimensionMarkWidth * scale;
  final half = width / 2;
  final tipHalf = half * kDimensionMarkTipScale;
  final reach = dir * (width * kDimensionMarkLengthScale);
  final tip = at + reach;
  return [
    at + side * half,
    tip + side * tipHalf,
    tip - side * tipHalf,
    at - side * half,
  ];
}

/// True when [point] is inside the convex [corners], or within [slop] of an edge.
bool pointHitsPolygon(List<Offset> corners, Offset point, {double slop = 0}) {
  if (corners.length < 3) return false;
  double? sign;
  for (var i = 0; i < corners.length; i++) {
    final a = corners[i];
    final b = corners[(i + 1) % corners.length];
    final edge = b - a;
    final len = edge.distance;
    if (len < 1e-6) continue;
    final dist =
        (edge.dx * (point.dy - a.dy) - edge.dy * (point.dx - a.dx)) / len;
    sign ??= dist >= 0 ? 1.0 : -1.0;
    if (dist * sign < -slop) return false;
  }
  return sign != null;
}

/// Index of the grab under [screen], or null.
int? hitGrab(DimensionTrack track, DimensionRuler ruler, Offset screen) {
  final toward = dimensionWidgetMarkDirection(track.axis);
  int? best;
  var bestDist = double.infinity;
  for (var i = 0; i < ruler.grabs.length; i++) {
    final at = track.at(ruler.grabs[i].fraction);
    final dist = (at - screen).distance;
    final onMark = pointHitsPolygon(
      dimensionCropMark(
        at: at,
        toward: toward,
        scale: kDimensionWidgetMarkScale,
      ),
      screen,
      slop: 4,
    );
    if (!onMark && dist > kDimensionGrabRadius) continue;
    if (dist >= bestDist) continue;
    best = i;
    bestDist = dist;
  }
  return best;
}
