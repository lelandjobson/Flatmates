import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../../geometry/polygon_union.dart';
import 'outline_edges.dart';

/// Merge coplanar outline faces so T-junctions (scaled boxes) drop inner seams.
List<OutlineQuad> unionCoplanarQuads(Iterable<OutlineQuad> quads) {
  final groups = <_PlaneKey, List<OutlineQuad>>{};
  for (final quad in quads) {
    if (quad.points.length < 3) continue;
    groups.putIfAbsent(_PlaneKey(quad), () => []).add(quad);
  }
  if (groups.isEmpty) return const [];

  final out = <OutlineQuad>[];
  for (final group in groups.values) {
    if (group.length == 1) {
      out.add(group.single);
      continue;
    }
    final basis = _PlaneBasis(group.first);
    final loops = unionPolygons([
      for (final quad in group) [
        for (final p in quad.points) basis.to2d(p),
      ],
    ]);
    if (loops.isEmpty) {
      out.addAll(group);
      continue;
    }
    for (final loop in loops) {
      final simple = simplifyColinearLoop(loop);
      if (simple.length < 3) continue;
      out.add(
        OutlineQuad(
          points: [for (final p in simple) basis.to3d(p)],
          normal: group.first.normal,
        ),
      );
    }
  }
  return out;
}

/// Drop vertices that sit on a straight run so merged faces stay one edge.
List<Offset> simplifyColinearLoop(List<Offset> loop) {
  if (loop.length < 3) return loop;
  final pts = List<Offset>.from(loop);
  var changed = true;
  while (changed && pts.length >= 3) {
    changed = false;
    for (var i = 0; i < pts.length; ) {
      final prev = pts[(i - 1 + pts.length) % pts.length];
      final curr = pts[i];
      final next = pts[(i + 1) % pts.length];
      final ab = curr - prev;
      final bc = next - curr;
      final cross = ab.dx * bc.dy - ab.dy * bc.dx;
      final dot = ab.dx * bc.dx + ab.dy * bc.dy;
      if (dot > 0 && cross.abs() < planarEpsilon * 100) {
        pts.removeAt(i);
        changed = true;
      } else {
        i++;
      }
    }
  }
  return pts;
}

class _PlaneKey {
  factory _PlaneKey(OutlineQuad quad) {
    final n = quad.normal;
    final qn = (
      (n.x * 1000).round(),
      (n.y * 1000).round(),
      (n.z * 1000).round(),
    );
    final d = n.dot(quad.points.first);
    return _PlaneKey._(qn, (d * 1000).round());
  }

  _PlaneKey._(this._n, this._d);

  final (int, int, int) _n;
  final int _d;

  @override
  bool operator ==(Object other) =>
      other is _PlaneKey && other._n == _n && other._d == _d;

  @override
  int get hashCode => Object.hash(_n, _d);
}

class _PlaneBasis {
  factory _PlaneBasis(OutlineQuad quad) {
    final n = Vector3.copy(quad.normal);
    if (n.length2 < 1e-12) {
      n.setValues(0, 1, 0);
    } else {
      n.normalize();
    }
    final origin = quad.points.first;
    final helper = n.y.abs() < 0.9 ? Vector3(0, 1, 0) : Vector3(1, 0, 0);
    final u = n.cross(helper);
    if (u.length2 < 1e-12) {
      u.setFrom(n.cross(Vector3(0, 0, 1)));
    }
    u.normalize();
    final v = n.cross(u)..normalize();
    return _PlaneBasis._(origin, u, v);
  }

  _PlaneBasis._(this.origin, this.u, this.v);

  final Vector3 origin;
  final Vector3 u;
  final Vector3 v;

  Offset to2d(Vector3 p) {
    final d = p - origin;
    return Offset(d.dot(u), d.dot(v));
  }

  Vector3 to3d(Offset o) => origin + u * o.dx + v * o.dy;
}
