import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import 'models.dart';

/// A shared boundary is the portal used to choose a direction even when the
/// neighboring face is edge-on to the camera.
class PlaneNeighbor {
  PlaneNeighbor(this.planeId, this.portal, this.sameVolume);
  final String planeId;
  final Vector3 portal;
  final bool sameVolume;
}

class PlaneNavigationGraph {
  PlaneNavigationGraph(
    Map<String, CraftPlane> planes,
    Map<String, CraftObject> objects,
  ) {
    String? volume(CraftPlane p) {
      final owner = objects[p.owner];
      return owner?.kind == CraftKind.wall
          ? planes[owner?.planeId]?.owner
          : p.owner;
    }

    final occupied = objects.values
        .where((o) => o.kind == CraftKind.floor || o.kind == CraftKind.wall)
        .map((o) => o.planeId)
        .toSet();
    final origins = <String, Vector3>{};
    Vector3 origin(CraftPlane p) {
      if (origins.containsKey(p.id)) return origins[p.id]!;
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
      return origins[p.id] = value;
    }

    final available = planes.values
        .where((p) => !occupied.contains(p.id))
        .toList();
    final rings = <String, List<Vector3>>{
      for (final p in available)
        p.id: p.region.outer
            .map((v) => origin(p) + p.u * v.dx + p.v * v.dy)
            .toList(),
    };
    for (var i = 0; i < available.length; i++) {
      final a = available[i];
      for (final b in available.skip(i + 1)) {
        final portal = _sharedBoundary(rings[a.id]!, rings[b.id]!);
        if (portal == null) continue;
        // Store each portal in the visible source face's coordinates.
        (neighbors[a.id] ??= []).add(
          PlaneNeighbor(
            b.id,
            portal + a.origin - origin(a),
            volume(a) != null && volume(a) == volume(b),
          ),
        );
        (neighbors[b.id] ??= []).add(
          PlaneNeighbor(
            a.id,
            portal + b.origin - origin(b),
            volume(a) != null && volume(a) == volume(b),
          ),
        );
      }
    }
    // Creation keeps the source plane active. Give it the same exits as its
    // crafted structural surfaces until the user moves to the next face.
    for (final object in objects.values) {
      if (!occupied.contains(object.planeId)) continue;
      final source = planes[object.planeId];
      final surface = planes['surface-${object.id}'];
      if (source == null || surface == null) continue;
      for (final edge in neighbors[surface.id] ?? <PlaneNeighbor>[]) {
        (neighbors[source.id] ??= []).add(
          PlaneNeighbor(
            edge.planeId,
            edge.portal + source.origin - surface.origin,
            edge.sameVolume,
          ),
        );
      }
    }
  }

  final Map<String, List<PlaneNeighbor>> neighbors = {};

  String? inDirection(
    String planeId,
    Offset swipe,
    Offset center,
    Offset? Function(Vector3) project,
  ) {
    if (swipe.distance == 0) return null;
    String? best;
    var bestVolume = false;
    var bestScore = .5; // Ignore neighbors more than 60 degrees off the swipe.
    for (final edge in neighbors[planeId] ?? <PlaneNeighbor>[]) {
      final point = project(edge.portal);
      if (point == null) continue;
      final delta = point - center;
      if (delta.distance < 1e-6) continue;
      final score =
          (delta.dx * swipe.dx + delta.dy * swipe.dy) /
          (delta.distance * swipe.distance);
      if (score > bestScore + 1e-9 ||
          ((score - bestScore).abs() < 1e-9 &&
              best != null &&
              (edge.sameVolume && !bestVolume ||
                  edge.sameVolume == bestVolume &&
                      edge.planeId.compareTo(best) < 0))) {
        best = edge.planeId;
        bestScore = score;
        bestVolume = edge.sameVolume;
      }
    }
    return best;
  }
}

Vector3? _sharedBoundary(List<Vector3> a, List<Vector3> b) {
  const epsilon = 1e-6;
  for (var i = 0; i < a.length; i++) {
    final start = a[i], axis = a[(i + 1) % a.length] - a[i];
    final length = axis.length;
    if (length < epsilon) continue;
    axis.scale(1 / length);
    for (var j = 0; j < b.length; j++) {
      final c = b[j] - start, d = b[(j + 1) % b.length] - start;
      if (c.cross(axis).length > epsilon || d.cross(axis).length > epsilon) {
        continue;
      }
      // Boost's collinear segment case: intersect projected parameter intervals.
      // A corner alone is not an adjacent face.
      final low = math.max(0.0, math.min(c.dot(axis), d.dot(axis)));
      final high = math.min(length, math.max(c.dot(axis), d.dot(axis)));
      if (high - low > epsilon) return start + axis * ((low + high) / 2);
    }
  }
  return null;
}

/// Recognize translation only after both fingers travel together. Testing each
/// displacement prevents a stationary finger plus a pinch from becoming a swipe.
class PlaneSwipe {
  List<Offset>? _start;
  bool consumed = false;
  void start(Iterable<Offset> positions) {
    _start = positions.toList();
    consumed = _start!.length != 2;
  }

  Offset? update(Iterable<Offset> positions, double threshold) {
    final current = positions.toList(), start = _start;
    if (consumed || start == null) return null;
    if (current.length != 2) {
      consumed = true;
      return null;
    }
    final a = current[0] - start[0], b = current[1] - start[1];
    if (a.distance < threshold || b.distance < threshold) return null;
    if ((a - b).distance > threshold * .35) return null;
    consumed = true;
    return (a + b) / 2;
  }
}
