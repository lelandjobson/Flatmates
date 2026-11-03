import 'dart:math' as math;
import 'dart:ui';
import 'geometry.dart';
import 'models.dart';
import 'bedroom_items.dart';

class Recipe {
  const Recipe(
    this.kind,
    this.defaultDepth,
    this.minDepth,
    this.maxDepth, {
    this.priority = 100,
  });
  final int priority;
  final CraftKind kind;
  final double defaultDepth, minDepth, maxDepth;
  bool depthAllowed(double d) =>
      d >= minDepth - geometryEpsilon && d <= maxDepth + geometryEpsilon;
}

const recipes = <CraftKind, Recipe>{
  CraftKind.floor: Recipe(CraftKind.floor, 0, 0, .2, priority: 0),
  CraftKind.wall: Recipe(CraftKind.wall, .02, 0, .2, priority: 0),
  CraftKind.rug: Recipe(CraftKind.rug, 0, 0, .03, priority: 10),
  CraftKind.tabletop: Recipe(CraftKind.tabletop, .06, .015, .15, priority: 20),
  CraftKind.bench: Recipe(CraftKind.bench, .22, .15, .5, priority: 30),
  CraftKind.planter: Recipe(CraftKind.planter, .2, .08, .5, priority: 40),
  CraftKind.screen: Recipe(CraftKind.screen, .65, .1, 1, priority: 50),
  CraftKind.window: Recipe(CraftKind.window, .015, 0, .1, priority: 10),
  CraftKind.door: Recipe(CraftKind.door, .02, 0, .1, priority: 10),
  CraftKind.bedFrame: Recipe(CraftKind.bedFrame, .08, .03, .15, priority: 10),
  CraftKind.mattress: Recipe(CraftKind.mattress, .035, .015, .08, priority: 10),
  CraftKind.pillow: Recipe(CraftKind.pillow, .025, .01, .06, priority: 10),
  CraftKind.blanket: Recipe(CraftKind.blanket, .008, 0, .02, priority: 10),
  CraftKind.lamp: Recipe(CraftKind.lamp, .16, .08, .3, priority: 20),
  CraftKind.storage: Recipe(CraftKind.storage, .15, .06, .35, priority: 30),
};

/// Geometry predicates use an oriented minimum bounding rectangle, rather
/// than axis-aligned extents, so rotating a drawing preserves its identity.
double aspectRatio(List<Offset> ring) {
  var bestArea = double.infinity, aspect = 1.0;
  for (final edge in edges(ring)) {
    final delta = edge.$2 - edge.$1;
    if (delta.distance < geometryEpsilon) continue;
    final u = delta / delta.distance, v = Offset(-u.dy, u.dx);
    final xs = ring.map((p) => p.dx * u.dx + p.dy * u.dy).toList();
    final ys = ring.map((p) => p.dx * v.dx + p.dy * v.dy).toList();
    final w = xs.reduce(math.max) - xs.reduce(math.min);
    final h = ys.reduce(math.max) - ys.reduce(math.min);
    if (w * h < bestArea - geometryEpsilon &&
        math.min(w, h) > geometryEpsilon) {
      bestArea = w * h;
      aspect = math.max(w, h) / math.min(w, h);
    }
  }
  return aspect;
}

List<CraftKind> recognize(CraftPlane plane, CraftGrid grid, List<int> path) {
  if (path.length < 2) return [];
  final closed = path.length >= 4 && path.first == path.last;
  final trace = grid.trace(path);
  if (trace.isEmpty) return [];
  final points = closed ? trace.sublist(0, trace.length - 1) : trace;
  if (!simplePath(points, closed: closed)) return [];
  if (!closed) {
    return grid.recipes.contains(CraftKind.screen) && pathLength(points) > .01
        ? [CraftKind.screen]
        : [];
  }
  final region = Region(points);
  if (!plane.region.containsRegion(region)) return [];
  return recognizeRegion(plane, grid, region, curved: grid.hasCurve(path));
}

List<CraftKind> recognizeRegion(
  CraftPlane plane,
  CraftGrid grid,
  Region region, {
  bool curved = false,
}) {
  final points = region.outer;
  final ratio = aspectRatio(points);
  final bottom = plane.region.bounds.top;
  final touchesBottom = points.any(
    (p) => (p.dy - bottom).abs() < geometryEpsilon,
  );
  final whollyInterior = points.every(
    (p) => plane.region.contains(p, boundary: false),
  );
  return grid.recipes.where((kind) {
    final item = bedroomItems[kind];
    if (item != null) {
      final coverage = region.area / plane.region.area;
      return coverage >= item.minimumCoverage - geometryEpsilon &&
          coverage <= item.maximumCoverage + geometryEpsilon &&
          (kind != CraftKind.bedFrame || (ratio >= 1.2 && ratio <= 3));
    }
    return switch (kind) {
      CraftKind.floor || CraftKind.wall => true,
      CraftKind.rug => region.area > .00001,
      CraftKind.tabletop => ratio <= 3.5 && region.area > .00001,
      CraftKind.bench => ratio >= 1.6 && ratio <= 6,
      CraftKind.planter => curved && ratio <= 2,
      CraftKind.window => whollyInterior,
      CraftKind.door => touchesBottom,
      CraftKind.screen => false,
      _ => false,
    };
  }).toList()..sort((a, b) {
    final rank = recipes[a]!.priority.compareTo(recipes[b]!.priority);
    return rank != 0 ? rank : a.index.compareTo(b.index);
  });
}
