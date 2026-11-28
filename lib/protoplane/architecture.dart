import 'package:vector_math/vector_math_64.dart';
import 'geometry.dart';
import 'models.dart';
import 'room_geometry.dart';

String architecturalPoint(Vector3 p) =>
    '${(p.x * 1e6).round()},${(p.y * 1e6).round()},${(p.z * 1e6).round()}';

class WallSide {
  WallSide(this.room, this.panel, this.start, this.end);
  final String room;
  final RoomPanel panel;
  final double start, end;
}

class ArchitecturalWall {
  ArchitecturalWall(this.id, this.a, this.b, this.sides);
  final String id;
  final Vector3 a, b;
  final List<WallSide> sides;
  bool get shared => sides.length == 2;
}

/// Collinear boundary intervals are split at endpoint projections, as in
/// Boost.Geometry's collinear segment/range handling. No proximity welding.
List<ArchitecturalWall> architecturalWalls(
  Map<String, CraftObject> objects,
  CraftPlane Function(CraftObject) source,
) {
  final entries = <({String room, RoomPanel panel, Vector3 a, Vector3 b})>[];
  for (final room in objects.values.where((o) => o.kind == CraftKind.room)) {
    for (final panel in roomPanels(
      room,
      source(room),
    ).where((p) => p.key.startsWith('wall-'))) {
      final a = panel.frame.origin + panel.frame.normal * roomThickness;
      entries.add((
        room: room.id,
        panel: panel,
        a: a,
        b: a + panel.frame.u * panel.frame.region.bounds.width,
      ));
    }
  }
  final walls = <String, ArchitecturalWall>{};
  for (final e in entries) {
    final delta = e.b - e.a, length = delta.length;
    final u = delta / length;
    final stops = <double>[0, length];
    for (final other in entries) {
      if ((other.b - other.a).cross(u).length > geometryEpsilon) continue;
      if ((other.a - e.a).cross(u).length > geometryEpsilon) continue;
      for (final p in [other.a, other.b]) {
        final t = (p - e.a).dot(u);
        if (t > geometryEpsilon && t < length - geometryEpsilon) stops.add(t);
      }
    }
    stops.sort();
    for (var i = 1; i < stops.length; i++) {
      if (stops[i] - stops[i - 1] < geometryEpsilon) continue;
      final a = e.a + u * stops[i - 1], b = e.a + u * stops[i];
      final keys = [architecturalPoint(a), architecturalPoint(b)]..sort();
      final id = 'wall:${keys.join("/")}';
      final wall = walls.putIfAbsent(id, () => ArchitecturalWall(id, a, b, []));
      wall.sides.add(WallSide(e.room, e.panel, stops[i - 1], stops[i]));
    }
  }
  final result = <ArchitecturalWall>[];
  for (final wall in walls.values) {
    if (!wall.shared) {
      result.add(wall);
      continue;
    }
    final a = wall.sides.first, b = wall.sides.last;
    List<RoomOpening> cuts(WallSide s) => objects[s.room]!.openings
        .where(
          (o) =>
              o.wall == s.panel.key &&
              o.region.bounds.left < s.end - geometryEpsilon &&
              o.region.bounds.right > s.start + geometryEpsilon,
        )
        .toList();
    final left = cuts(a), right = cuts(b);
    final compatible =
        left.length == right.length &&
        left.every(
          (x) => right.any((y) {
            final mapped = mapRegion(
              x.region,
              (p) => b.panel.frame.local(a.panel.frame.point(p)),
            );
            return x.kind == y.kind &&
                x.isFlap == y.isFlap &&
                mapped.containsRegion(y.region) &&
                y.region.containsRegion(mapped);
          }),
        );
    if (compatible) {
      result.add(wall);
    } else {
      // Older rooms can disagree at a seam. Keep both physical panels and
      // their original attachment identities rather than erase either cut.
      for (final side in wall.sides) {
        result.add(
          ArchitecturalWall('${wall.id}/${side.room}', wall.a, wall.b, [side]),
        );
      }
    }
  }
  return result;
}
