import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'geometry.dart';
import 'focus_context.dart';
import 'layered_terrain.dart';
import 'pencil.dart';
import 'models.dart';
import 'spatial_index.dart';
import 'world_relations.dart';

export 'world_relations.dart';

/// The connection type is independent of ownership/support relationships.
enum PlaneAdjacency { coplanar, fold, landscapeStep }

/// A directed portal on the displayed source face. Keep the entire shared
/// segment: a midpoint alone loses the direction of partial/asymmetric exits.
class PlaneNeighbor {
  PlaneNeighbor(this.planeId, this.start, this.end, this.sameVolume, this.kind);
  final String planeId;
  final Vector3 start, end;
  final bool sameVolume;
  final PlaneAdjacency kind;
  Vector3 get portal => (start + end) * .5;
  double get length => start.distanceTo(end);
}

/// Derived snapshot of the canonical plane/object entities. Navigation,
/// dependencies and spatial proximity remain distinct queries over stable IDs.
class PlaneNavigationGraph {
  PlaneNavigationGraph(
    Map<String, CraftPlane> planes,
    Map<String, CraftObject> objects, {
    Map<String, String> aliases = const {},
    Set<String> excluded = const {},
    List<Region> Function(CraftPlane)? surfaceRegions,
    LayeredTerrain? terrain,
  }) : aliases = Map.unmodifiable(aliases),
       relations = CraftRelations(planes, objects) {
    final structural = <String, List<CraftObject>>{};
    for (final object in objects.values) {
      if (object.kind == CraftKind.floor || object.kind == CraftKind.wall) {
        (structural[aliases[object.planeId] ?? object.planeId] ??= []).add(
          object,
        );
      }
    }
    String? volume(CraftPlane p) {
      final owner = objects[p.owner];
      final id = owner?.kind == CraftKind.wall
          ? planes[owner?.planeId]?.owner
          : p.owner;
      return planes[aliases['surface-$id']]?.owner ?? id;
    }

    // Logical attachment geometry excludes paper thickness and drawing offsets.
    // This adapter is confined here; displayed/rendered bounds stay unmodified.
    final origins = <String, Vector3>{};
    final resolving = <String>{};
    Vector3 origin(CraftPlane p) {
      if (origins.containsKey(p.id)) return origins[p.id]!;
      if (!resolving.add(p.id)) {
        throw StateError('Cyclic plane ownership: ${p.id}');
      }
      final owner = objects[p.owner];
      final source = planes[owner?.planeId];
      var value = p.origin;
      if (owner != null && source != null) {
        final shift = origin(source) - source.origin;
        value = p.origin + shift;
        if (p.id == 'surface-${owner.id}' &&
            (owner.kind == CraftKind.floor || owner.kind == CraftKind.wall)) {
          value = origin(source);
        } else if (p.wallCandidate || p.id == 'upper-${owner.id}') {
          value -= source.normal * (owner.depth + .003);
        }
      }
      resolving.remove(p.id);
      return origins[p.id] = value;
    }

    final edges = <_Boundary>[];
    final regions = <String, List<Region>>{};
    final hidden = <String>{};
    for (final plane in planes.values) {
      if (excluded.contains(plane.id) ||
          (aliases[plane.id] ?? plane.id) != plane.id) {
        continue;
      }
      var remaining = surfaceRegions?.call(plane) ?? [plane.region];
      // Only the occupied area is replaced. A small floor must not make the
      // rest of a ground tile, wall candidate or upper candidate unreachable.
      for (final object in structural[plane.id] ?? <CraftObject>[]) {
        remaining = [
          for (final region in remaining)
            ...region.subtract(
              Region(
                object.region.outer
                    .map((p) => plane.local(planes[object.planeId]!.point(p)))
                    .toList(),
                object.region.holes
                    .map(
                      (ring) => ring
                          .map(
                            (p) =>
                                plane.local(planes[object.planeId]!.point(p)),
                          )
                          .toList(),
                    )
                    .toList(),
              ),
            ),
        ];
      }
      regions[plane.id] = remaining;
      if (remaining.isEmpty) hidden.add(plane.id);
      for (final region in remaining) {
        for (final ring in region.rings) {
          for (var i = 0; i < ring.length; i++) {
            Vector3 point(Offset p) =>
                origin(plane) + plane.u * p.dx + plane.v * p.dy;
            final a = point(ring[i]), b = point(ring[(i + 1) % ring.length]);
            if (a.distanceTo(b) > _epsilon) {
              edges.add(_Boundary(plane.id, a, b));
            }
          }
        }
      }
    }
    final boundaryIndex = CraftSpatialIndex<int>({
      for (var i = 0; i < edges.length; i++) i: edges[i].bounds,
    });
    boundaryCount = edges.length;
    final adjacent = <String, List<PlaneNeighbor>>{};
    for (var i = 0; i < edges.length; i++) {
      final a = edges[i], source = planes[a.planeId]!;
      for (final j in boundaryIndex.query(a.bounds)) {
        if (j <= i || edges[j].planeId == a.planeId) continue;
        boundaryComparisons++;
        final b = edges[j], target = planes[b.planeId]!;
        final overlap = _sharedBoundary(a, b);
        if (overlap == null) continue;
        final coplanar = source.normal.cross(target.normal).length < _epsilon;
        if (coplanar) {
          // Coincident/overlapping sheets are not neighbors across a boundary.
          final middle = (overlap.$1 + overlap.$2) * .5;
          final side =
              source.normal.cross((a.b - a.a).normalized()) * (_epsilon * 8);
          bool contains(CraftPlane p, Vector3 point) {
            final d = point - origin(p);
            final local = Offset(d.dot(p.u), d.dot(p.v));
            return regions[p.id]!.any(
              (r) => r.contains(local, boundary: false),
            );
          }

          if ([middle + side, middle - side].any(
            (point) => contains(source, point) && contains(target, point),
          )) {
            continue;
          }
        }
        final sameVolume =
            volume(source) != null && volume(source) == volume(target);
        final kind = coplanar ? PlaneAdjacency.coplanar : PlaneAdjacency.fold;
        void connect(CraftPlane from, CraftPlane to) {
          final shift = from.origin - origin(from);
          (adjacent[from.id] ??= []).add(
            PlaneNeighbor(
              to.id,
              overlap.$1 + shift,
              overlap.$2 + shift,
              sameVolume,
              kind,
            ),
          );
        }

        connect(source, target);
        connect(target, source);
      }
    }
    // Authored seams can lie inside a support, not only on its outer boundary.
    for (final object in objects.values) {
      final attachment = object.linear;
      if (attachment == null) continue;
      final sourceId =
          aliases[attachment.sourcePlaneId] ?? attachment.sourcePlaneId;
      final targetId =
          aliases['surface-${object.id}'] ?? 'surface-${object.id}';
      final source = planes[sourceId], target = planes[targetId];
      final anchor = planes[attachment.sourcePlaneId];
      if (source == null ||
          target == null ||
          anchor == null ||
          sourceId == targetId ||
          excluded.contains(sourceId) ||
          excluded.contains(targetId)) {
        continue;
      }
      final frame = planes[object.planeId];
      if (frame == null) continue;
      final seams = clipPencil([
        PencilSegment(
          Offset.zero,
          Offset((attachment.b - attachment.a).distance, 0),
        ),
      ], object.region);
      for (final seam in seams) {
        final a = frame.point(seam.a), b = frame.point(seam.b);
        for (final pair in [(sourceId, targetId), (targetId, sourceId)]) {
          final list = adjacent.putIfAbsent(pair.$1, () => []);
          if (!list.any(
            (n) =>
                n.planeId == pair.$2 &&
                n.start.distanceTo(a) < _epsilon &&
                n.end.distanceTo(b) < _epsilon,
          )) {
            list.add(PlaneNeighbor(pair.$2, a, b, true, PlaneAdjacency.fold));
          }
        }
      }
    }

    // Creation deliberately keeps the original source active. Hidden sources
    // have outgoing exits, but other nodes always arrive at visible surfaces.
    for (final id in hidden) {
      final source = planes[id]!;
      for (final object in structural[id] ?? <CraftObject>[]) {
        final surfaceId = 'surface-${object.id}';
        final surface = planes[aliases[surfaceId] ?? surfaceId];
        if (surface == null) continue;
        final shift = source.origin - surface.origin;
        for (final edge in adjacent[surface.id] ?? <PlaneNeighbor>[]) {
          (adjacent[id] ??= []).add(
            PlaneNeighbor(
              edge.planeId,
              edge.start + shift,
              edge.end + shift,
              edge.sameVolume,
              edge.kind,
            ),
          );
        }
      }
    }
    availableRegions = Map.unmodifiable({
      for (final entry in regions.entries)
        entry.key: List<Region>.unmodifiable(entry.value),
    });
    neighbors = Map.unmodifiable({
      for (final entry in adjacent.entries)
        entry.key: List<PlaneNeighbor>.unmodifiable(entry.value),
    });
    // Swiping is a movement policy over topology, not a support relationship.
    // Floors never fold onto walls. Wall navigation retains its existing exits.
    final swipeEdges = <String, List<PlaneNeighbor>>{
      for (final entry in neighbors.entries)
        entry.key: [
          for (final edge in entry.value)
            if (!isFloorOrientation(planes[entry.key]!) ||
                isFloorOrientation(planes[edge.planeId]!))
              edge,
        ],
    };
    if (terrain != null) {
      // Index actual exposed geometry once per graph rebuild. Tile columns
      // describe adjacency; elevation does not. A cut leaving an isolated scrap
      // still permits entry, but an entirely empty column is never a target.
      final columns = <(int, int), List<CraftPlane>>{};
      for (final tile in terrain.tiles.values) {
        final p = planes[tile.id];
        if (p == null ||
            excluded.contains(p.id) ||
            (regions[p.id] ?? []).isEmpty) {
          continue;
        }
        (columns[(tile.x, tile.y)] ??= []).add(p);
      }
      for (final list in columns.values) {
        list.sort((a, b) {
          final elevation = b.origin.y.compareTo(a.origin.y);
          return elevation != 0 ? elevation : a.id.compareTo(b.id);
        });
      }
      for (final tile in terrain.tiles.values) {
        final source = planes[tile.id];
        if (source == null || excluded.contains(source.id)) continue;
        final list = swipeEdges.putIfAbsent(source.id, () => []);
        // Replace landscape boundary exits with column exits. Partial exposed
        // fragments at one height must not mask a complete neighboring layer.
        list.removeWhere((edge) => terrain.tiles.containsKey(edge.planeId));
        for (final step in [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final candidates = columns[(tile.x + step.$1, tile.y + step.$2)];
          if (candidates == null || candidates.isEmpty) continue;
          final target = candidates.first;
          final a = step.$1 == 0
              ? Offset(0, step.$2 > 0 ? 1 : 0)
              : Offset(step.$1 > 0 ? 1 : 0, 0);
          final b = step.$1 == 0
              ? a + const Offset(1, 0)
              : a + const Offset(0, 1);
          list.add(
            PlaneNeighbor(
              target.id,
              source.point(a),
              source.point(b),
              false,
              PlaneAdjacency.landscapeStep,
            ),
          );
        }
      }
    }
    swipeNeighbors = Map.unmodifiable({
      for (final entry in swipeEdges.entries)
        entry.key: List<PlaneNeighbor>.unmodifiable(entry.value),
    });
    // Render-space bounds must never use the flattened topology origins.
    spatial = CraftSpatialIndex<CraftEntity>({
      for (final plane in planes.values)
        planeEntity(plane.id): craftBounds(plane.region.outer.map(plane.point)),
      for (final object in objects.values)
        if (planes.containsKey(object.planeId))
          objectEntity(object.id): craftBounds([
            for (final point in [...object.region.outer, ...object.path])
              for (final depth in [0.0, math.max(.003, object.depth)])
                planes[object.planeId]!.point(point, depth),
          ], padding: .004),
    });
  }

  static const _epsilon = 1e-6;
  late final Map<String, List<PlaneNeighbor>> neighbors;

  /// Visible portions after occupied floor/wall footprints are removed.
  late final Map<String, List<Region>> availableRegions;

  /// Gesture destinations; the full adjacency graph remains available above.
  late final Map<String, List<PlaneNeighbor>> swipeNeighbors;
  final CraftRelations relations;
  final Map<String, String> aliases;
  late final CraftSpatialIndex<CraftEntity> spatial;
  late final int boundaryCount;
  int boundaryComparisons = 0;

  /// Direction selection visits only this face's exits, independent of world
  /// size. The projected swipe ray crossing a portal outranks angular fallback.
  String? inDirection(
    String planeId,
    Offset swipe,
    Offset center,
    Offset? Function(Vector3) project,
  ) {
    planeId = aliases[planeId] ?? planeId;
    if (swipe.distance == 0) return null;
    final direction = swipe / swipe.distance;
    String? best;
    var bestVolume = false, bestScore = .5, bestDistance = double.infinity;
    for (final edge in swipeNeighbors[planeId] ?? <PlaneNeighbor>[]) {
      final a = project(edge.start), b = project(edge.end);
      if (a == null || b == null) continue;
      final segment = b - a, delta = a - center;
      final denominator = cross(direction, segment);
      double score = -1, distance = double.infinity;
      // Cramer's rule as in Boost Cartesian segment intersection. Here the
      // first primitive is a ray and the second is the finite portal segment.
      if (denominator.abs() > 1e-9) {
        final t = cross(delta, segment) / denominator;
        final u = cross(delta, direction) / denominator;
        if (t >= -1e-6 && u >= -1e-9 && u <= 1 + 1e-9) {
          score = 1;
          distance = t;
        }
      }
      if (score < 0) {
        for (final point in [a, b, (a + b) * .5]) {
          final delta = point - center;
          if (delta.distance < 1e-6) continue;
          final alignment =
              (delta.dx * direction.dx + delta.dy * direction.dy) /
              delta.distance;
          if (alignment > score) {
            score = alignment;
            distance = delta.distance;
          }
        }
      }
      final tied = (score - bestScore).abs() < 1e-9;
      if (score > bestScore + 1e-9 ||
          (tied &&
              best != null &&
              (edge.sameVolume && !bestVolume ||
                  edge.sameVolume == bestVolume &&
                      (distance < bestDistance - 1e-6 ||
                          (distance - bestDistance).abs() < 1e-6 &&
                              edge.planeId.compareTo(best) < 0)))) {
        best = edge.planeId;
        bestScore = score;
        bestVolume = edge.sameVolume;
        bestDistance = distance;
      }
    }
    return best;
  }
}

class _Boundary {
  _Boundary(this.planeId, this.a, this.b)
    : bounds = craftBounds([a, b], padding: PlaneNavigationGraph._epsilon);
  final String planeId;
  final Vector3 a, b;
  final MapAabb bounds;
}

(Vector3, Vector3)? _sharedBoundary(_Boundary a, _Boundary b) {
  const epsilon = PlaneNavigationGraph._epsilon;
  final axis = a.b - a.a;
  final length = axis.length;
  axis.scale(1 / length);
  final c = b.a - a.a, d = b.b - a.a;
  if (c.cross(axis).length > epsilon || d.cross(axis).length > epsilon) {
    return null;
  }
  // Boost's collinear case intersects projected intervals. A corner alone
  // has zero length and never becomes a navigation connection.
  final low = math.max(0.0, math.min(c.dot(axis), d.dot(axis)));
  final high = math.min(length, math.max(c.dot(axis), d.dot(axis)));
  return high - low > epsilon ? (a.a + axis * low, a.a + axis * high) : null;
}

/// Recognize translation only after both fingers travel together. Testing each
/// displacement prevents a stationary finger plus a pinch from becoming a swipe.
class PlaneSwipe {
  List<Offset>? _start;
  bool consumed = false;
  bool zooming = false;

  static double threshold(Size viewport) =>
      (viewport.shortestSide * .12).clamp(48.0, 96.0);

  void start(Iterable<Offset> positions) {
    _start = positions.toList();
    consumed = _start!.length != 2;
    zooming = false;
  }

  /// Evaluate once both contacts have reported motion. Lock a meaningful pinch
  /// or rotation to zoom for the contact sequence, even if it later translates.
  Offset? update(Iterable<Offset> positions, double threshold) {
    final current = positions.toList(), start = _start;
    if (consumed || start == null) return null;
    if (current.length != 2) {
      consumed = true;
      return null;
    }
    final a = current[0] - start[0], b = current[1] - start[1];
    if ((a - b).distance > math.max(18.0, threshold * .55)) {
      zooming = true;
    }
    if (zooming || a.distance < threshold || b.distance < threshold) {
      return null;
    }
    final alignment = (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);
    if (alignment < .85) return null;
    consumed = true;
    return (a + b) / 2;
  }

  void startTrackpad() {
    consumed = zooming = false;
  }

  Offset? updateTrackpad(
    Offset pan,
    double scale,
    double rotation,
    double threshold,
  ) {
    if (consumed) return null;
    if ((scale - 1).abs() > .06 || rotation.abs() > .08) zooming = true;
    if (zooming || pan.distance < threshold) return null;
    consumed = true;
    return pan;
  }
}
