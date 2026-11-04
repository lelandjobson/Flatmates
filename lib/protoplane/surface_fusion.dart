import 'dart:ui';
import 'package:vector_math/vector_math_64.dart';
import 'geometry.dart';
import 'models.dart';

/// A shared work surface retains each member's support identity and coordinates.
/// This avoids moving attachments when adjacent pieces become one drawing area.
class CraftSurfaceFusion {
  final Set<String> retired = {};
  final Map<String, String> canonical = {};
  final Map<String, List<String>> members = {};

  void rebuild(
    Map<String, CraftPlane> planes,
    Map<String, CraftObject> objects,
  ) {
    retired.clear();
    canonical.clear();
    members.clear();
    for (final object in objects.values) {
      final p = planes['surface-${object.id}'];
      if (p == null || p.supports.isEmpty) continue;
      planes[p.id] = CraftPlane(
        id: p.id,
        origin: p.origin,
        u: p.u,
        v: p.v,
        region: object.region,
        grids: p.grids,
        owner: p.owner,
      );
    }
    final pending = objects.values
        .where(
          (o) =>
              (o.kind == CraftKind.floor || o.kind == CraftKind.wall) &&
              planes.containsKey('surface-${o.id}'),
        )
        .toList();
    while (pending.isNotEmpty) {
      final first = pending.removeAt(0);
      final basis = planes['surface-${first.id}']!;
      var region = first.region;
      final group = [first];
      var changed = true;
      while (changed) {
        changed = false;
        for (final other in pending.toList()) {
          final p = planes['surface-${other.id}']!;
          if (other.kind != first.kind ||
              other.material != first.material ||
              (other.depth - first.depth).abs() > geometryEpsilon ||
              basis.normal.dot(p.normal) < 1 - geometryEpsilon ||
              (p.origin - basis.origin).dot(basis.normal).abs() >
                  geometryEpsilon) {
            continue;
          }
          final mapped = _mapRegion(other.region, p, basis);
          if (!region.bounds.inflate(geometryEpsilon).overlaps(mapped.bounds)) {
            continue;
          }
          final merged = region.union(mapped);
          if (merged.length != 1 ||
              !merged.single.valid ||
              region.overlaps(mapped)) {
            continue;
          }
          region = merged.single;
          group.add(other);
          pending.remove(other);
          changed = true;
        }
      }
      if (group.length == 1) continue;
      final snapshots = {
        for (final o in group) o.id: planes['surface-${o.id}']!,
      };
      final ids = group.map((o) => o.id).toList();
      for (final object in group) {
        final p = snapshots[object.id]!;
        final union = _mapRegion(region, basis, p);
        final grids = <CraftGrid>[];
        for (var index = 0; index < p.grids.length; index++) {
          final original = p.grids[index];
          final expanded = tileFloorGrid(
            CraftGrid(
              id: original.id,
              name: original.name,
              nodes: original.nodes,
              edges: original.edges,
              recipes: original.recipes,
              examples: original.examples,
              connectionStyle: original.connectionStyle,
            ),
            union,
          );
          final nodes = List<Offset>.of(expanded.nodes);
          final edges = List<GridEdge>.of(expanded.edges);
          final seenEdges = {
            for (final e in edges) '${e.a}/${e.b}/${e.control}',
          };
          for (final other in group) {
            if (other.id == object.id) continue;
            final source = snapshots[other.id]!;
            if (index >= source.grids.length) continue;
            final grid = source.grids[index];
            final mapping = <int>[];
            for (final n in grid.nodes) {
              final point = p.local(source.point(n));
              var found = nodes.indexWhere(
                (v) => (v - point).distance < geometryEpsilon,
              );
              if (found < 0) {
                found = nodes.length;
                nodes.add(point);
              }
              mapping.add(found);
            }
            for (final e in grid.edges) {
              final a = mapping[e.a], b = mapping[e.b];
              final control = e.control == null
                  ? null
                  : p.local(source.point(e.control!));
              if (a == b || !seenEdges.add('$a/$b/$control')) continue;
              edges.add(GridEdge(a, b, control));
            }
          }
          grids.add(
            CraftGrid(
              id: original.id,
              name: original.name,
              nodes: nodes,
              edges: edges,
              recipes: original.recipes,
              examples: original.examples,
              tiled: true,
              connectionStyle: original.connectionStyle,
            ),
          );
        }
        planes[p.id] = CraftPlane(
          id: p.id,
          origin: p.origin,
          u: p.u,
          v: p.v,
          region: union,
          grids: grids,
          owner: p.owner,
          wallCandidate: p.wallCandidate,
          supports: {...p.supports, ...ids}.toList(),
        );
        canonical[p.id] = basis.id;
        members[p.id] = ids;
      }
    }
    _deriveBoundaries(planes, objects);
  }

  void _deriveBoundaries(
    Map<String, CraftPlane> planes,
    Map<String, CraftObject> objects,
  ) {
    final occupied = objects.values.map((o) => o.planeId).toSet();
    for (final entry in members.entries.toList()) {
      if (canonical[entry.key] != entry.key) continue;
      final surface = planes[entry.key]!;
      if (objects[surface.owner]?.kind != CraftKind.floor) continue;
      final owners = entry.value.toSet();
      // Keep occupied frames for attachments; only unoccupied candidates can
      // be discarded. New candidates are generated from the actual union rim.
      for (final p in planes.values) {
        if (p.wallCandidate && owners.contains(p.owner)) retired.add(p.id);
      }
      final ring = simplifyRing(surface.region.outer);
      for (var i = 0; i < ring.length; i++) {
        final a = ring[i], b = ring[(i + 1) % ring.length];
        final edge = surface.point(b) - surface.point(a);
        // Geometry-derived IDs avoid changing an occupied frame's meaning when
        // another boundary is inserted or removed elsewhere on the union.
        String key(double n) => (n * 1000000).round().toString();
        final id =
            'fused-wall-${surface.owner}-${key(a.dx)}-${key(a.dy)}-${key(b.dx)}-${key(b.dy)}';
        retired.remove(id);
        if (occupied.contains(id) && planes.containsKey(id)) continue;
        final region = rectangle(edge.length, 1);
        planes[id] = CraftPlane(
          id: id,
          origin: surface.point(a, .001),
          u: edge.normalized(),
          v: Vector3(0, 1, 0),
          region: region,
          owner: surface.owner,
          wallCandidate: true,
          supports: entry.value,
          grids: [
            lattice(id, region, recipes: [CraftKind.wall], name: 'Wall'),
          ],
        );
      }
      final uppers = planes.values
          .where((p) => p.id.startsWith('upper-') && owners.contains(p.owner))
          .toList();
      if (uppers.isEmpty) continue;
      final supports = {for (final p in uppers) ...p.supports}.toList();
      final id = 'upper-${surface.owner}';
      final base = CraftPlane(
        id: id,
        origin: surface.origin + Vector3(0, 1.001, 0),
        u: surface.u,
        v: surface.v,
        region: surface.region,
        owner: surface.owner,
        supports: supports,
        grids: [lattice(id, surface.region, name: 'Upper floor')],
      );
      planes[id] = base;
      for (final p in uppers) {
        if (p.id != id) {
          final region = _mapRegion(surface.region, surface, p);
          planes[p.id] = CraftPlane(
            id: p.id,
            origin: p.origin,
            u: p.u,
            v: p.v,
            region: region,
            owner: p.owner,
            supports: supports,
            grids: [lattice(p.id, region, name: 'Upper floor')],
          );
        }
        canonical[p.id] = id;
      }
      canonical[id] = id;
    }
  }
}

Region _mapRegion(Region region, CraftPlane from, CraftPlane to) => Region(
  region.outer.map((p) => to.local(from.point(p))).toList(),
  region.holes
      .map((ring) => ring.map((p) => to.local(from.point(p))).toList())
      .toList(),
);
