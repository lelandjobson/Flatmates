// Authored legacy recipe geometry for recognition and save compatibility tests.
import 'dart:math' as math;
import 'dart:ui';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';

List<CraftGrid> floorGrids(String id, Region region, int seed) {
  final box = interiorSquare(region);
  final rng = math.Random(seed);
  return [
    for (var variant = 0; variant < 3; variant++)
      _floorGrid('$id-$variant', box, variant, rng),
  ];
}

CraftGrid _floorGrid(String id, Rect box, int variant, math.Random rng) {
  final margin = 0.03 + rng.nextDouble() * 0.04;
  final b = box.deflate(box.width * margin);
  final nodes = [
    for (var y = 0; y < 5; y++)
      for (var x = 0; x < 5; x++)
        Offset(b.left + b.width * x / 4, b.top + b.height * y / 4),
  ];
  final links = <GridEdge>[];
  for (var y = 0; y < 5; y++) {
    for (var x = 0; x < 5; x++) {
      final a = y * 5 + x;
      if (x < 4) {
        links.add(
          GridEdge(
            a,
            a + 1,
            variant > 0 && y == 0
                ? (nodes[a] + nodes[a + 1]) / 2 - Offset(0, b.height * 0.025)
                : null,
          ),
        );
      }
      if (y < 4) links.add(GridEdge(a, a + 5));
    }
  }
  const square = [6, 7, 8, 13, 18, 17, 16, 11, 6];
  const elongated = [10, 11, 12, 13, 14, 19, 18, 17, 16, 15, 10];
  const curved = [0, 1, 2, 7, 12, 11, 10, 5, 0];
  final recipes = switch (variant) {
    0 => [CraftKind.rug, CraftKind.tabletop, CraftKind.bench],
    1 => [CraftKind.rug, CraftKind.tabletop, CraftKind.planter],
    _ => [
      CraftKind.rug,
      CraftKind.tabletop,
      CraftKind.bench,
      CraftKind.planter,
      CraftKind.screen,
    ],
  };
  return CraftGrid(
    id: id,
    name: ['Angular', 'Curved', 'Mixed'][variant],
    nodes: nodes,
    edges: links,
    recipes: recipes,
    examples: {
      for (final r in recipes)
        r: switch (r) {
          CraftKind.bench => elongated,
          CraftKind.planter => curved,
          CraftKind.screen => [20, 21, 22, 23, 24],
          _ => square,
        },
    },
  );
}

/// Repeat a stored recipe motif without rescaling its drawable examples.
CraftGrid tileFloorGrid(CraftGrid motif, Region region) {
  if (motif.tiled || motif.nodes.isEmpty) return motif;
  final box = Rect.fromPoints(
    Offset(
      motif.nodes.map((p) => p.dx).reduce(math.min),
      motif.nodes.map((p) => p.dy).reduce(math.min),
    ),
    Offset(
      motif.nodes.map((p) => p.dx).reduce(math.max),
      motif.nodes.map((p) => p.dy).reduce(math.max),
    ),
  );
  if (box.width < geometryEpsilon || box.height < geometryEpsilon) return motif;
  final nodes = List<Offset>.of(motif.nodes),
      links = List<GridEdge>.of(motif.edges);
  String key(Offset p) => '${(p.dx * 1e7).round()}:${(p.dy * 1e7).round()}';
  final indices = {for (var i = 0; i < nodes.length; i++) key(nodes[i]): i};
  final edgeKeys = <String>{};
  String edgeKey(int a, int b, Offset? control) =>
      '${math.min(a, b)}:${math.max(a, b)}:${control == null ? "straight" : key(control)}';
  for (final e in links) {
    edgeKeys.add(edgeKey(e.a, e.b, e.control));
  }
  bool inside(List<Offset> points) {
    for (var i = 1; i < points.length; i++) {
      final a = points[i - 1], b = points[i], delta = b - a;
      if (!region.contains(a) || !region.contains(b)) return false;
      final cuts = <double>[0, 1];
      for (final ring in region.rings) {
        for (final edge in edges(ring)) {
          final hit = crossing(a, b, edge.$1, edge.$2);
          if (hit != null) {
            cuts.add(
              ((hit - a).dx * delta.dx + (hit - a).dy * delta.dy) /
                  delta.distanceSquared,
            );
          }
        }
      }
      cuts.sort();
      for (var j = 1; j < cuts.length; j++) {
        if (!region.contains(a + delta * ((cuts[j - 1] + cuts[j]) / 2))) {
          return false;
        }
      }
    }
    return true;
  }

  final minX = ((region.bounds.left - box.right) / box.width).ceil();
  final maxX = ((region.bounds.right - box.left) / box.width).floor();
  final minY = ((region.bounds.top - box.bottom) / box.height).ceil();
  final maxY = ((region.bounds.bottom - box.top) / box.height).floor();
  for (var y = minY; y <= maxY; y++) {
    for (var x = minX; x <= maxX; x++) {
      if (x == 0 && y == 0) continue;
      final offset = Offset(x * box.width, y * box.height);
      for (final edge in motif.edges) {
        final points = edge.points(motif.nodes).map((p) => p + offset).toList();
        if (!inside(points)) continue;
        int index(Offset p) => indices.putIfAbsent(key(p), () {
          nodes.add(p);
          return nodes.length - 1;
        });
        final a = index(motif.nodes[edge.a] + offset),
            b = index(motif.nodes[edge.b] + offset);
        final control = edge.control == null ? null : edge.control! + offset;
        if (edgeKeys.add(edgeKey(a, b, control))) {
          links.add(GridEdge(a, b, control));
        }
      }
    }
  }
  return CraftGrid(
    id: motif.id,
    name: motif.name,
    nodes: nodes,
    edges: links,
    recipes: motif.recipes,
    examples: motif.examples,
    tiled: true,
  );
}

CraftGrid bedroomGrid(String planeId, Region region) {
  var box = region.bounds.deflate(region.bounds.shortestSide * .06);
  if (!region.containsRegion(
    rectangle(box.width, box.height, origin: box.topLeft),
  )) {
    box = interiorSquare(region);
  }
  final nodes = [
    for (var y = 0; y < 7; y++)
      for (var x = 0; x < 7; x++)
        Offset(box.left + box.width * x / 6, box.top + box.height * y / 6),
  ];
  final edges = <GridEdge>[];
  for (var y = 0; y < 7; y++) {
    for (var x = 0; x < 7; x++) {
      final i = y * 7 + x;
      if (x < 6) edges.add(GridEdge(i, i + 1));
      if (y < 6) edges.add(GridEdge(i, i + 7));
    }
  }
  return CraftGrid(
    id: '$planeId-bedroom',
    name: 'Bedroom',
    nodes: nodes,
    edges: edges,
    recipes: [
      CraftKind.bedFrame,
      CraftKind.lamp,
      CraftKind.storage,
      CraftKind.rug,
    ],
    examples: {
      CraftKind.bedFrame: [8, 9, 10, 17, 24, 31, 30, 29, 22, 15, 8],
      CraftKind.lamp: [12, 13, 20, 19, 12],
      CraftKind.storage: [33, 34, 41, 48, 47, 40, 33],
      CraftKind.rug: [36, 37, 38, 45, 44, 43, 36],
    },
  );
}
