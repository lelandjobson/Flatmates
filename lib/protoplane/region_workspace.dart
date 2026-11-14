import 'dart:math' as math;
import 'dart:ui';

import '../geometry/polygon_union.dart'
    show PlanarGraph, splitAllAtIntersections, polygonSignedArea;
import 'geometry.dart';
import 'models.dart';
import 'pencil.dart';

const lightPencilColor = Color(0xffff9b32);

Region mapRegion(Region region, CraftPlane from, CraftPlane to) => Region(
  region.outer.map((p) => to.local(from.point(p))).toList(),
  region.holes
      .map((h) => h.map((p) => to.local(from.point(p))).toList())
      .toList(),
);

bool coplanar(CraftPlane a, CraftPlane b) =>
    a.normal.dot(b.normal).abs() > 1 - geometryEpsilon &&
    (a.origin - b.origin).dot(a.normal).abs() < 1e-5;

bool sharedRegionEdge(Region a, Region b) {
  for (final ar in a.rings) {
    for (final ae in edges(ar)) {
      for (final br in b.rings) {
        for (final be in edges(br)) {
          final common = [ae.$1, ae.$2, be.$1, be.$2]
              .where(
                (p) => onSegment(p, ae.$1, ae.$2) && onSegment(p, be.$1, be.$2),
              )
              .toList();
          if (common.any((p) => common.any((q) => !near(p, q)))) return true;
        }
      }
    }
  }
  return false;
}

/// A view over physical surfaces; never replaces their authoritative owners.
class RegionSurface {
  RegionSurface(this.frame, this.sources);
  final CraftPlane frame;
  final List<String> sources;
  String get id => frame.id;
  Region get region => frame.region;
  Map<String, dynamic> toJson() => {
    'frame': frame.toJson(),
    'sources': sources,
  };
  factory RegionSurface.fromJson(Map<String, dynamic> j) => RegionSurface(
    CraftPlane.fromJson(j['frame']),
    (j['sources'] as List).cast<String>(),
  );
}

class LightRegion {
  LightRegion(
    this.id,
    this.surfaceId,
    this.geometry, {
    this.uses = 1,
    this.implied = false,
  });
  final String id, surfaceId;
  final Region geometry;
  final int uses;
  final bool implied;
  Map<String, dynamic> toJson() => {
    'id': id,
    'surface': surfaceId,
    'geometry': geometry.toJson(),
    'uses': uses,
  };
  factory LightRegion.fromJson(Map<String, dynamic> j) => LightRegion(
    j['id'],
    j['surface'],
    Region.fromJson(j['geometry']),
    uses: j['uses'],
  );
}

/// Session data. The JSON representation is for undo, never for world storage.
class RegionWorkspace {
  final Map<String, RegionSurface> surfaces = {};
  final Map<String, LightRegion> regions = {};
  final Map<String, List<PencilSegment>> lines = {};
  int nextId = 1, revision = 0;

  Iterable<LightRegion> on(String surface) =>
      regions.values.where((r) => r.surfaceId == surface);

  List<Region> impliedRegions(String surface) {
    var rest = [surfaces[surface]!.region];
    for (final r in on(surface)) {
      rest = rest.expand((part) => part.subtract(r.geometry)).toList();
    }
    return rest;
  }

  LightRegion? at(String surface, Offset point) {
    for (final r in on(surface)) {
      if (r.geometry.contains(point, boundary: false)) return r;
    }
    for (final r in on(surface)) {
      if (r.geometry.contains(point)) return r;
    }
    final rest = impliedRegions(surface);
    for (final (i, r) in rest.indexed) {
      if (r.contains(point)) {
        return LightRegion('implied:$surface:$i', surface, r, implied: true);
      }
    }
    return null;
  }

  bool draw(String surface, List<Offset> path) {
    if (path.length < 2) return false;
    final domain = surfaces[surface]!.region;
    final incoming = clipPencil([
      for (var i = 1; i < path.length; i++) PencilSegment(path[i - 1], path[i]),
    ], domain);
    final fresh = newPencilCoverage(incoming, lines[surface] ?? []);
    if (fresh.isEmpty) return false;
    lines[surface] = [...?lines[surface], ...fresh];
    final old = on(surface).toList();
    final parts = [
      ...old,
      for (final r in impliedRegions(surface))
        LightRegion('', surface, r, implied: true),
    ];
    for (final source in parts) {
      final segments = [
        for (final ring in source.geometry.rings) ...edges(ring),
        for (final s in clipPencil(lines[surface]!, source.geometry))
          (s.a, s.b),
      ];
      final candidates =
          PlanarGraph(splitAllAtIntersections(segments))
              .findFaces()
              .where((r) => polygonSignedArea(r) < -geometryEpsilon)
              .map((r) => Region(simplifyRing(r)))
              .where((r) => r.valid)
              .toList()
            ..sort((a, b) => a.area.compareTo(b.area));
      // A disconnected inner loop can also return its enclosing face. Subtract
      // the smaller faces so the partition has disjoint interiors and real holes.
      final partition = <Region>[];
      for (final candidate in candidates) {
        var pieces = candidate.clipTo([source.geometry]);
        for (final accepted in partition) {
          pieces = pieces.expand((r) => r.subtract(accepted)).toList();
        }
        partition.addAll(pieces.where((r) => r.valid));
      }
      final tracedOuter = newPencilCoverage([
        for (final edge in edges(source.geometry.outer))
          PencilSegment(edge.$1, edge.$2),
      ], lines[surface]!).isEmpty;
      if ((partition.length < 2 && !(source.implied && tracedOuter)) ||
          (partition.fold<double>(0, (s, r) => s + r.area) -
                      source.geometry.area)
                  .abs() >
              1e-5) {
        continue;
      }
      regions.remove(source.id);
      final touchesOuter = lines[surface]!.any(
        (s) => edges(
          source.geometry.outer,
        ).any((e) => onSegment(s.a, e.$1, e.$2) || onSegment(s.b, e.$1, e.$2)),
      );
      for (final part in partition) {
        if (source.implied &&
            !touchesOuter &&
            edges(source.geometry.outer).any(
              (e) => part.rings.any(
                (ring) => edges(ring).any(
                  (edge) =>
                      onSegment(e.$1, edge.$1, edge.$2) &&
                      onSegment(e.$2, edge.$1, edge.$2),
                ),
              ),
            )) {
          continue;
        }
        final id = 'region-${nextId++}';
        regions[id] = LightRegion(id, surface, part);
      }
    }
    revision++;
    return true;
  }

  bool combine(LightRegion a, LightRegion b) {
    if (a.surfaceId != b.surfaceId ||
        a.id == b.id ||
        !sharedRegionEdge(a.geometry, b.geometry)) {
      return false;
    }
    final merged = a.geometry.union(b.geometry);
    if (merged.length != 1 || !merged.single.valid) return false;
    regions.remove(a.id);
    regions.remove(b.id);
    final id = 'region-${nextId++}';
    regions[id] = LightRegion(id, a.surfaceId, merged.single);
    List<PencilSegment> boundary(Region r) => [
      for (final ring in r.rings)
        for (final e in edges(ring)) PencilSegment(e.$1, e.$2),
    ];
    final ab = boundary(a.geometry), bb = boundary(b.geometry);
    bool covers(List<PencilSegment> edges, PencilSegment p) =>
        edges.any((e) => onSegment(p.a, e.a, e.b) && onSegment(p.b, e.a, e.b));
    lines[a.surfaceId] = [
      for (final s in lines[a.surfaceId] ?? <PencilSegment>[])
        for (final p in splitPencil(s, [...ab, ...bb]))
          if (!(covers(ab, p) && covers(bb, p))) p,
    ];
    revision++;
    return true;
  }

  void consume(LightRegion region) {
    // Direct Cut/Place gestures do not spend a workspace region.
    if (region.id == 'drawing') return;
    if (region.uses > 1) {
      regions[region.id] = LightRegion(
        region.id,
        region.surfaceId,
        region.geometry,
        uses: region.uses - 1,
      );
    } else {
      regions.remove(region.id);
      final keep = [
        for (final r in on(region.surfaceId))
          for (final ring in r.geometry.rings)
            for (final e in edges(ring)) PencilSegment(e.$1, e.$2),
      ];
      final removed = [
        for (final ring in region.geometry.rings)
          for (final e in edges(ring)) PencilSegment(e.$1, e.$2),
      ];
      lines[region.surfaceId] = [
        for (final s in lines[region.surfaceId] ?? <PencilSegment>[])
          for (final p in splitPencil(s, [...keep, ...removed]))
            if (!region.geometry.contains((p.a + p.b) / 2) ||
                keep.any(
                  (e) => onSegment(p.a, e.a, e.b) && onSegment(p.b, e.a, e.b),
                ))
              p,
      ];
    }
    revision++;
  }

  void clear() {
    surfaces.clear();
    regions.clear();
    lines.clear();
    revision++;
  }

  Map<String, dynamic> toJson() => {
    'nextId': nextId,
    'surfaces': surfaces.values.map((s) => s.toJson()).toList(),
    'regions': regions.values.map((r) => r.toJson()).toList(),
    'lines': {
      for (final e in lines.entries)
        e.key: e.value.map((s) => s.toJson()).toList(),
    },
  };
  void restore(Map<String, dynamic> j) {
    clear();
    nextId = j['nextId'] ?? 1;
    for (final s in j['surfaces'] ?? []) {
      final value = RegionSurface.fromJson(s);
      surfaces[value.id] = value;
    }
    for (final r in j['regions'] ?? []) {
      final value = LightRegion.fromJson(r);
      regions[value.id] = value;
    }
    for (final e in ((j['lines'] ?? {}) as Map).entries) {
      lines[e.key] = (e.value as List)
          .map((s) => PencilSegment.fromJson(s))
          .toList();
    }
  }
}

CraftGrid regionDrawingGrid(
  RegionSurface surface,
  double spacing,
  GridConnections connections,
) {
  return paperDrawingGrid(
    surface.id,
    surface.region,
    const [],
    const [],
    spacing: spacing,
    connections: connections,
  );
}

/// Maximum rectangle over fully contained grid cells, not point samples.
Rect? largestRegionRectangle(
  Region region, {
  required double spacing,
  required double minimum,
  required Offset nearPoint,
}) {
  final bounds = region.bounds;
  final xs = <double>{
    for (
      var x = (bounds.left / spacing).ceil();
      x <= (bounds.right / spacing).floor();
      x++
    )
      x * spacing,
  }.toList()..sort();
  final ys = <double>{
    for (
      var y = (bounds.top / spacing).ceil();
      y <= (bounds.bottom / spacing).floor();
      y++
    )
      y * spacing,
  }.toList()..sort();
  if (xs.length < 2 || ys.length < 2) return null;
  final cells = [
    for (var y = 0; y < ys.length - 1; y++)
      [
        for (var x = 0; x < xs.length - 1; x++)
          region.containsRegion(
            rectangle(
              xs[x + 1] - xs[x],
              ys[y + 1] - ys[y],
              origin: Offset(xs[x], ys[y]),
            ),
          ),
      ],
  ];
  Rect? best;
  for (var top = 0; top < cells.length; top++) {
    final columns = List<bool>.filled(xs.length - 1, true);
    for (var bottom = top; bottom < cells.length; bottom++) {
      for (var x = 0; x < columns.length; x++) {
        columns[x] = columns[x] && cells[bottom][x];
      }
      var left = 0;
      while (left < columns.length) {
        if (!columns[left]) {
          left++;
          continue;
        }
        var right = left + 1;
        while (right < columns.length && columns[right]) {
          right++;
        }
        final r = Rect.fromLTRB(xs[left], ys[top], xs[right], ys[bottom + 1]);
        if (math.min(r.width, r.height) >= minimum - geometryEpsilon) {
          if (preferRegionRectangle(r, best, nearPoint)) {
            best = r;
          }
        }
        left = right;
      }
    }
  }
  return best;
}

bool preferRegionRectangle(Rect candidate, Rect? current, Offset drop) {
  if (current == null) return true;
  final area =
      candidate.width * candidate.height - current.width * current.height;
  if (area.abs() > geometryEpsilon) return area > 0;
  final distance =
      (candidate.center - drop).distanceSquared -
      (current.center - drop).distanceSquared;
  if (distance.abs() > geometryEpsilon) return distance < 0;
  for (final pair in [
    (candidate.top, current.top),
    (candidate.left, current.left),
    (candidate.bottom, current.bottom),
    (candidate.right, current.right),
  ]) {
    if ((pair.$1 - pair.$2).abs() > geometryEpsilon) return pair.$1 < pair.$2;
  }
  return false;
}
