import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../gameplay/viewers/world_plane.dart';
import 'geometry.dart';

enum CraftKind {
  floor,
  wall,
  rug,
  tabletop,
  bench,
  planter,
  screen,
  window,
  door,
  bedFrame,
  mattress,
  pillow,
  blanket,
  lamp,
  storage,
}

enum PaperColor { red, yellow, green }

enum CraftTool { scissors, volume }

extension CraftKindName on CraftKind {
  String get label => this == CraftKind.bedFrame
      ? 'Bed frame'
      : name[0].toUpperCase() + name.substring(1);
}

class GridEdge {
  const GridEdge(this.a, this.b, [this.control]);
  final int a, b;
  final Offset? control;
  List<Offset> points(List<Offset> nodes, {bool reversed = false}) {
    final p = control == null
        ? [nodes[a], nodes[b]]
        : flattenCurve(nodes[a], control!, nodes[b]);
    return reversed ? p.reversed.toList() : p;
  }

  Map<String, dynamic> toJson() => {
    'a': a,
    'b': b,
    if (control != null) 'c': [control!.dx, control!.dy],
  };
  factory GridEdge.fromJson(Map<String, dynamic> j) => GridEdge(
    j['a'],
    j['b'],
    j['c'] == null
        ? null
        : Offset((j['c'][0] as num).toDouble(), (j['c'][1] as num).toDouble()),
  );
}

class CraftGrid {
  CraftGrid({
    required this.id,
    required this.name,
    required this.nodes,
    required this.edges,
    required this.recipes,
    this.examples = const {},
    this.tiled = false,
  });
  final bool tiled;
  final String id, name;
  final List<Offset> nodes;
  final List<GridEdge> edges;
  final List<CraftKind> recipes;
  final Map<CraftKind, List<int>> examples;
  GridEdge? connection(int a, int b) {
    for (final edge in edges) {
      if ((edge.a == a && edge.b == b) || (edge.a == b && edge.b == a)) {
        return edge;
      }
    }
    return null;
  }

  /// Dot shapes advertise permitted connection geometry, not draw history.
  String dotStyle(int node) {
    final neighbors = edges.where((e) => e.a == node || e.b == node).toList();
    if (nodes.length > 2 &&
        neighbors.map((e) => e.a == node ? e.b : e.a).toSet().length ==
            nodes.length - 1) {
      return 'star';
    }
    for (final e in neighbors) {
      final d = nodes[e.a] - nodes[e.b];
      if (e.control != null ||
          (d.dx.abs() > geometryEpsilon && d.dy.abs() > geometryEpsilon)) {
        return 'circle';
      }
    }
    return 'square';
  }

  final Map<int, Map<int, List<int>>> _straightRoutes = {};

  /// Routes are computed once per starting node. Only straight permitted edges
  /// advancing along the target ray can participate; curves retain their shape.
  List<int>? collinearRoute(int from, int to) {
    return (_straightRoutes[from] ??= _routesFrom(from))[to];
  }

  Map<int, List<int>> _routesFrom(int from) {
    final result = <int, List<int>>{};
    for (var target = 0; target < nodes.length; target++) {
      if (target == from) continue;
      final vector = nodes[target] - nodes[from];
      final length = vector.distance;
      if (length < 1e-8) continue;
      final direction = vector / length;
      final candidates = <(double, int)>[];
      for (var n = 0; n < nodes.length; n++) {
        final delta = nodes[n] - nodes[from];
        final along = delta.dx * direction.dx + delta.dy * direction.dy;
        final across = (delta.dx * direction.dy - delta.dy * direction.dx)
            .abs();
        if (along > 1e-8 && along <= length + 1e-8 && across <= 1e-5) {
          candidates.add((along, n));
        }
      }
      candidates.sort((a, b) => a.$1.compareTo(b.$1));
      final reached = <int, List<int>>{from: []};
      for (final candidate in candidates) {
        for (final previous in reached.keys.toList().reversed) {
          final edge = connection(previous, candidate.$2);
          if (edge != null && edge.control == null) {
            reached[candidate.$2] = [...reached[previous]!, candidate.$2];
            break;
          }
        }
      }
      if (reached.containsKey(target)) result[target] = reached[target]!;
    }
    return result;
  }

  List<Offset> trace(List<int> path) {
    if (path.isEmpty) return [];
    final out = <Offset>[nodes[path.first]];
    for (var i = 1; i < path.length; i++) {
      final edge = connection(path[i - 1], path[i]);
      if (edge == null) return [];
      out.addAll(edge.points(nodes, reversed: edge.a != path[i - 1]).skip(1));
    }
    return out;
  }

  bool hasCurve(List<int> path) {
    for (var i = 1; i < path.length; i++) {
      if (connection(path[i - 1], path[i])?.control != null) return true;
    }
    return false;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'tiled': tiled,
    'name': name,
    'nodes': encodePoints(nodes),
    'edges': edges.map((e) => e.toJson()).toList(),
    'recipes': recipes.map((r) => r.name).toList(),
    'examples': {for (final e in examples.entries) e.key.name: e.value},
  };
  factory CraftGrid.fromJson(Map<String, dynamic> j) => CraftGrid(
    tiled: j['tiled'] == true,
    id: j['id'],
    name: j['name'],
    nodes: decodePoints(j['nodes']),
    edges: (j['edges'] as List).map((e) => GridEdge.fromJson(e)).toList(),
    recipes: (j['recipes'] as List)
        .map((r) => CraftKind.values.byName(r))
        .toList(),
    examples: {
      for (final e in (j['examples'] as Map).entries)
        CraftKind.values.byName(e.key): (e.value as List).cast<int>(),
    },
  );
}

class CraftPlane {
  CraftPlane({
    required this.id,
    required this.origin,
    required this.u,
    required this.v,
    required this.region,
    required this.grids,
    this.owner,
    this.wallCandidate = false,
    this.supports = const [],
  });
  final String id;
  final Vector3 origin, u, v;
  final Region region;
  final List<CraftGrid> grids;
  final String? owner;
  final bool wallCandidate;
  final List<String> supports;
  CraftPlane withGrids(List<CraftGrid> value) => CraftPlane(
    id: id,
    origin: origin,
    u: u,
    v: v,
    region: region,
    grids: value,
    owner: owner,
    wallCandidate: wallCandidate,
    supports: supports,
  );
  Vector3 get normal => u.cross(v).normalized();
  Vector3 point(Offset p, [double depth = 0]) =>
      origin + u * p.dx + v * p.dy + normal * depth;
  Offset local(Vector3 p) => Offset((p - origin).dot(u), (p - origin).dot(v));
  WorldPlane get worldPlane =>
      WorldPlane(origin: origin, normal: normal, up: v, subtileSize: 0.5);
  Map<String, dynamic> toJson() => {
    'id': id,
    'origin': _vector(origin),
    'u': _vector(u),
    'v': _vector(v),
    'region': region.toJson(),
    'owner': owner,
    'wallCandidate': wallCandidate,
    'supports': supports,
    'grids': grids.map((g) => g.toJson()).toList(),
  };
  factory CraftPlane.fromJson(Map<String, dynamic> j) => CraftPlane(
    id: j['id'],
    origin: _readVector(j['origin']),
    u: _readVector(j['u']),
    v: _readVector(j['v']),
    region: Region.fromJson(j['region']),
    owner: j['owner'],
    wallCandidate: j['wallCandidate'],
    supports: (j['supports'] as List).cast<String>(),
    grids: (j['grids'] as List).map((g) => CraftGrid.fromJson(g)).toList(),
  );
}

class CraftObject {
  CraftObject({
    required this.id,
    required this.planeId,
    required this.kind,
    required this.region,
    required this.color,
    this.depth = 0,
    this.path = const [],
    this.attachmentIds = const [],
  });
  final String id, planeId;
  final CraftKind kind;
  final Region region;
  final PaperColor color;
  final double depth;
  final List<Offset> path;
  final List<String> attachmentIds;
  CraftObject copyWith({
    CraftKind? kind,
    Region? region,
    double? depth,
    String? id,
    List<Offset>? path,
    List<String>? attachmentIds,
  }) => CraftObject(
    id: id ?? this.id,
    planeId: planeId,
    kind: kind ?? this.kind,
    region: region ?? this.region,
    color: color,
    depth: depth ?? this.depth,
    path: path ?? this.path,
    attachmentIds: attachmentIds ?? this.attachmentIds,
  );
  double get materialArea => kind == CraftKind.screen
      ? pathLength(path) * depth
      : region.area + region.perimeter * depth;
  Map<String, dynamic> toJson() => {
    'id': id,
    'planeId': planeId,
    'kind': kind.name,
    'region': region.toJson(),
    'color': color.name,
    'depth': depth,
    'path': encodePoints(path),
    'attachments': attachmentIds,
  };
  factory CraftObject.fromJson(Map<String, dynamic> j) => CraftObject(
    id: j['id'],
    planeId: j['planeId'],
    kind: CraftKind.values.byName(j['kind']),
    region: Region.fromJson(j['region']),
    color: PaperColor.values.byName(j['color']),
    depth: (j['depth'] as num).toDouble(),
    path: decodePoints(j['path']),
    attachmentIds: (j['attachments'] as List).cast<String>(),
  );
}

class CraftDraft {
  CraftDraft({this.path = const [], this.depth = 0, this.choice});
  final List<int> path;
  final double depth;
  final CraftKind? choice;
  CraftDraft copyWith({List<int>? path, double? depth, CraftKind? choice}) =>
      CraftDraft(
        path: path ?? this.path,
        depth: depth ?? this.depth,
        choice: choice ?? this.choice,
      );
  Map<String, dynamic> toJson() => {
    'path': path,
    'depth': depth,
    'choice': choice?.name,
  };
  factory CraftDraft.fromJson(Map<String, dynamic> j) => CraftDraft(
    path: (j['path'] as List).cast<int>(),
    depth: (j['depth'] as num).toDouble(),
    choice: j['choice'] == null ? null : CraftKind.values.byName(j['choice']),
  );
}

List<double> _vector(Vector3 v) => [v.x, v.y, v.z];
Vector3 _readVector(dynamic v) => Vector3(
  (v[0] as num).toDouble(),
  (v[1] as num).toDouble(),
  (v[2] as num).toDouble(),
);
double pathLength(List<Offset> p) {
  var length = 0.0;
  for (var i = 1; i < p.length; i++) {
    length += (p[i] - p[i - 1]).distance;
  }
  return length;
}

Region rectangle(double width, double height, {Offset origin = Offset.zero}) =>
    Region([
      origin,
      origin + Offset(width, 0),
      origin + Offset(width, height),
      origin + Offset(0, height),
    ]);

CraftGrid lattice(
  String id,
  Region bounds, {
  int count = 3,
  List<CraftKind> recipes = const [CraftKind.floor],
  String name = 'Ground',
}) {
  final box = bounds.bounds;
  final nodes = [
    for (var y = 0; y < count; y++)
      for (var x = 0; x < count; x++)
        Offset(
          box.left + box.width * x / (count - 1),
          box.top + box.height * y / (count - 1),
        ),
  ];
  final edges = <GridEdge>[];
  for (var a = 0; a < nodes.length; a++) {
    for (var b = a + 1; b < nodes.length; b++) {
      if ((nodes[a].dx - nodes[b].dx).abs() > geometryEpsilon &&
          (nodes[a].dy - nodes[b].dy).abs() > geometryEpsilon) {
        continue;
      }
      if (nodes.indexed.any(
        (p) => p.$1 != a && p.$1 != b && onSegment(p.$2, nodes[a], nodes[b]),
      )) {
        continue;
      }
      // Verify the entire edge lies inside a potentially concave support.
      final cuts = <double>[0, 1];
      final delta = nodes[b] - nodes[a];
      for (final ring in bounds.rings) {
        for (final e in edgesOf(ring)) {
          final hit = crossing(nodes[a], nodes[b], e.$1, e.$2);
          if (hit != null) {
            cuts.add(
              delta.dx.abs() > delta.dy.abs()
                  ? (hit.dx - nodes[a].dx) / delta.dx
                  : (hit.dy - nodes[a].dy) / delta.dy,
            );
          }
        }
      }
      cuts.sort();
      if (!bounds.contains(nodes[a]) || !bounds.contains(nodes[b])) continue;
      if (List.generate(
        cuts.length - 1,
        (i) =>
            bounds.contains(nodes[a] + delta * ((cuts[i] + cuts[i + 1]) / 2)),
      ).every((x) => x)) {
        edges.add(GridEdge(a, b));
      }
    }
  }
  return CraftGrid(
    id: id,
    name: name,
    nodes: nodes,
    edges: edges,
    recipes: recipes,
  );
}

Iterable<(Offset, Offset)> edgesOf(List<Offset> ring) => edges(ring);

/// A guaranteed interior square for template grids, even on triangular floors.
Rect interiorSquare(Region region) {
  final candidates = region.triangles;
  var best = Rect.zero;
  for (final t in candidates) {
    final center = (t[0] + t[1] + t[2]) / 3;
    var half = math.min(region.bounds.width, region.bounds.height) * 0.42;
    for (var i = 0; i < 20; i++) {
      final square = rectangle(
        half * 2,
        half * 2,
        origin: center - Offset(half, half),
      );
      if (region.containsRegion(square)) {
        if (half * 2 > best.width) best = square.bounds;
        break;
      }
      half *= 0.8;
    }
  }
  return best;
}

Region hollowRegion(Region region) {
  final center = region.bounds.center;
  var inner = Region(
    region.outer.map((p) => center + (p - center) * .78).toList(),
  );
  if (!region.containsRegion(inner)) {
    final box = interiorSquare(
      region,
    ).deflate(interiorSquare(region).width * .12);
    inner = rectangle(box.width, box.height, origin: box.topLeft);
  }
  return Region(region.outer, [...region.holes, inner.outer]);
}

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
