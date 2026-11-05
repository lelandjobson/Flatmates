import 'dart:math' as math;
import 'dart:ui';
import 'geometry.dart';
import 'models.dart';

/// Exact geometry, independent of the textured presentation of graphite.
class PencilSegment {
  const PencilSegment(this.a, this.b);
  final Offset a, b;
  double get length => (b - a).distance;
  PencilSegment map(Offset Function(Offset) f) => PencilSegment(f(a), f(b));
  List<double> toJson() => [a.dx, a.dy, b.dx, b.dy];
  factory PencilSegment.fromJson(List<dynamic> j) {
    if (j.length != 4 || j.any((v) => v is! num || !v.isFinite)) {
      throw const FormatException('Invalid pencil segment');
    }
    return PencilSegment(
      Offset((j[0] as num).toDouble(), (j[1] as num).toDouble()),
      Offset((j[2] as num).toDouble(), (j[3] as num).toDouble()),
    );
  }
}

/// Split using Cartesian intersections and collinear endpoint ratios (Boost
/// cartesian_segments). Midpoint classification excludes holes and removed paper.
List<PencilSegment> splitPencil(
  PencilSegment s,
  Iterable<PencilSegment> cutters,
) {
  if (s.length < geometryEpsilon) return [];
  final points = <Offset>[s.a, s.b];
  for (final c in cutters) {
    final hit = crossing(s.a, s.b, c.a, c.b);
    if (hit != null) points.add(hit);
    if (onSegment(c.a, s.a, s.b)) points.add(c.a);
    if (onSegment(c.b, s.a, s.b)) points.add(c.b);
  }
  points.sort(
    (a, b) => (a - s.a).distanceSquared.compareTo((b - s.a).distanceSquared),
  );
  return [
    for (var i = 1; i < points.length; i++)
      if (!near(points[i - 1], points[i]))
        PencilSegment(points[i - 1], points[i]),
  ];
}

List<PencilSegment> clipPencil(
  Iterable<PencilSegment> segments,
  Region region,
) {
  final boundary = [
    for (final ring in region.rings)
      for (final (a, b) in edges(ring)) PencilSegment(a, b),
  ];
  return [
    for (final s in segments)
      for (final part in splitPencil(s, boundary))
        if (region.contains((part.a + part.b) / 2)) part,
  ];
}

/// Only positive-length coincident coverage is subtracted; crossing another mark
/// does not pay for it or unlock any other connection.
List<PencilSegment> newPencilCoverage(
  Iterable<PencilSegment> incoming,
  Iterable<PencilSegment> existing,
) {
  final covered = existing.toList(), result = <PencilSegment>[];
  for (final s in incoming) {
    final fresh = splitPencil(s, covered)
        .where(
          (part) => !covered.any(
            (c) => onSegment(part.a, c.a, c.b) && onSegment(part.b, c.a, c.b),
          ),
        )
        .toList();
    result.addAll(fresh);
    covered.addAll(fresh);
  }
  return result;
}

List<PencilSegment> paperGridLines(Region region, {double spacing = .5}) {
  final b = region.bounds;
  return clipPencil([
    for (
      var x = (b.left / spacing).ceil();
      x <= (b.right / spacing).floor();
      x++
    )
      PencilSegment(Offset(x * spacing, b.top), Offset(x * spacing, b.bottom)),
    for (
      var y = (b.top / spacing).ceil();
      y <= (b.bottom / spacing).floor();
      y++
    )
      PencilSegment(Offset(b.left, y * spacing), Offset(b.right, y * spacing)),
  ], region);
}

CraftGrid paperDrawingGrid(
  String id,
  Region region,
  Iterable<PencilSegment> marks,
  List<CraftKind> recipes, {
  bool pencil = false,
  List<Region>? material,
}) {
  final committed = marks.toList();
  final raw = [
    ...paperGridLines(region, spacing: pencil ? .25 : .5),
    if (!pencil) ...clipPencil(committed, region),
  ];
  final lines = material == null
      ? raw
      : newPencilCoverage([
          for (final part in material) ...clipPencil(raw, part),
        ], const []);
  final nodes = <Offset>[], links = <GridEdge>[];
  final indices = <String, int>{}, linked = <String>{};
  int node(Offset p) => indices.putIfAbsent(
    '${(p.dx * 1e7).round()},${(p.dy * 1e7).round()}',
    () {
      nodes.add(p);
      return nodes.length - 1;
    },
  );
  for (final s in lines) {
    for (final split in splitPencil(s, lines)) {
      final dots = <Offset>[split.a, split.b];
      if (!pencil &&
          committed.any(
            (m) => onSegment(split.a, m.a, m.b) && onSegment(split.b, m.a, m.b),
          )) {
        for (
          var x = (math.min(split.a.dx, split.b.dx) * 4).ceil();
          x <= (math.max(split.a.dx, split.b.dx) * 4).floor();
          x++
        ) {
          for (
            var y = (math.min(split.a.dy, split.b.dy) * 4).ceil();
            y <= (math.max(split.a.dy, split.b.dy) * 4).floor();
            y++
          ) {
            final p = Offset(x / 4, y / 4);
            if (onSegment(p, split.a, split.b) &&
                !dots.any((n) => near(n, p))) {
              dots.add(p);
            }
          }
        }
      }
      dots.sort(
        (a, b) => (a - split.a).distanceSquared.compareTo(
          (b - split.a).distanceSquared,
        ),
      );
      for (var i = 1; i < dots.length; i++) {
        final a = node(dots[i - 1]), b = node(dots[i]);
        final key = a < b ? '$a/$b' : '$b/$a';
        if (linked.add(key)) links.add(GridEdge(a, b));
      }
    }
  }
  return CraftGrid(
    id: '$id-${pencil ? 'pencil' : 'paper'}',
    name: 'Paper',
    nodes: nodes,
    edges: links,
    recipes: recipes,
    tiled: true,
  );
}

class PencilStroke {
  PencilStroke(this.id, this.segments);
  final String id;
  final List<PencilSegment> segments;
  Map<String, dynamic> toJson() => {
    'id': id,
    'segments': segments.map((s) => s.toJson()).toList(),
  };
  factory PencilStroke.fromJson(Map<String, dynamic> j) => PencilStroke(
    j['id'] as String,
    (j['segments'] as List).map((s) => PencilSegment.fromJson(s)).toList(),
  );
}

enum PencilMotif {
  parallel('Parallel lines'),
  crosshatch('Crosshatch'),
  cross('Cross'),
  diamond('Diamond');

  const PencilMotif(this.label);
  final String label;
  List<PencilSegment> segments({Offset tile = Offset.zero, int turns = 0}) {
    final horizontal = [
      for (final y in [.25, .5, .75]) PencilSegment(Offset(0, y), Offset(1, y)),
    ];
    final raw = switch (this) {
      PencilMotif.parallel => horizontal,
      PencilMotif.crosshatch => [
        ...horizontal,
        for (final x in [.25, .5, .75])
          PencilSegment(Offset(x, 0), Offset(x, 1)),
      ],
      PencilMotif.cross => [
        const PencilSegment(Offset.zero, Offset(1, 1)),
        const PencilSegment(Offset(1, 0), Offset(0, 1)),
      ],
      PencilMotif.diamond => [
        const PencilSegment(Offset(.5, 0), Offset(1, .5)),
        const PencilSegment(Offset(1, .5), Offset(.5, 1)),
        const PencilSegment(Offset(.5, 1), Offset(0, .5)),
        const PencilSegment(Offset(0, .5), Offset(.5, 0)),
      ],
    };
    return raw
        .map(
          (s) => s.map((p) {
            for (var i = 0; i < turns % 4; i++) {
              p = Offset(1 - p.dy, p.dx);
            }
            return p + tile;
          }),
        )
        .toList();
  }

  bool covered(Iterable<PencilSegment> marks, Offset tile) => [0, 1, 2, 3].any(
    (turns) =>
        newPencilCoverage(segments(tile: tile, turns: turns), marks).isEmpty,
  );
}
