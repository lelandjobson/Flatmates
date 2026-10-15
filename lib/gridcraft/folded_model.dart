import 'dart:math' as math;
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../geometry/polygon_union.dart' show polygonCentroid, polygonSignedArea;
import '../papercut/craft_v1.dart';
import '../papercut/fold_pose.dart';
import 'blueprint.dart';
import 'scissor.dart' show ownsPoint;

/// One face of a folded model. [outline] is flat, in level coordinates.
/// [toWorld] carries that flat outline to its folded place in 3D.
class ModelFace {
  const ModelFace({
    required this.id,
    required this.ring,
    required this.island,
    required this.outline,
    required this.toWorld,
  });

  final String id;

  /// Blueprint piece this face belongs to, or -1 when none matched.
  final int ring;

  /// Index into [FoldedModel.islands].
  final int island;
  final List<Offset> outline;
  final Matrix4 toWorld;

  Offset get centroid => polygonCentroid(outline);

  Vector3 world(Offset point, [Matrix4? pose]) =>
      (pose ?? toWorld).transformed3(Vector3(point.dx, point.dy, 0));

  List<Vector3> worldRing([Matrix4? pose]) => [
    for (final point in outline) world(point, pose),
  ];
}

/// Shared fold line between two faces of one island, in level coordinates.
class FoldHinge {
  const FoldHinge(this.a, this.b, this.start, this.end);

  final int a;
  final int b;
  final Offset start;
  final Offset end;
}

/// The folded result of a level: the 3D shape its blueprint pieces wrap.
class FoldedModel {
  FoldedModel({
    required this.faces,
    required this.islands,
    required this.hinges,
  });

  final List<ModelFace> faces;

  /// Face indexes per island. The first face is the island root.
  final List<List<int>> islands;
  final List<FoldHinge> hinges;

  late final Aabb3 bounds = _bounds();

  /// Per face, per outline edge: true where another face of the same island
  /// shares that edge.
  late final List<List<bool>> foldEdges = [
    for (var i = 0; i < faces.length; i++)
      [
        for (var e = 0; e < faces[i].outline.length; e++)
          islands[faces[i].island].any(
            (j) =>
                j != i &&
                _sharesEdge(
                  faces[j].outline,
                  faces[i].outline[e],
                  faces[i].outline[(e + 1) % faces[i].outline.length],
                ),
          ),
      ],
  ];

  /// Which side of [face]'s flat plane, +1 or -1 along z, faces outward.
  late final List<double> outwardSides = [
    for (var i = 0; i < faces.length; i++)
      faces[i].toWorld
                  .getRotation()
                  .transposed()
                  .transformed(outwardNormal(i))
                  .z >=
              0
          ? 1.0
          : -1.0,
  ];

  /// The same model slid by [offset] in world space.
  FoldedModel moved(Vector3 offset) {
    final by = Matrix4.translation(offset);
    return FoldedModel(
      faces: [
        for (final face in faces)
          ModelFace(
            id: face.id,
            ring: face.ring,
            island: face.island,
            outline: face.outline,
            toWorld: by * face.toWorld,
          ),
      ],
      islands: islands,
      hinges: hinges,
    );
  }

  Vector3 get center => (bounds.min + bounds.max) * 0.5;

  double get radius => (bounds.max - bounds.min).length * 0.5;

  int? faceOfRing(int ring) {
    for (var i = 0; i < faces.length; i++) {
      if (faces[i].ring == ring) return i;
    }
    return null;
  }

  List<int> islandOf(int face) => islands[faces[face].island];

  /// Unit normal of [face] pointing away from its island's middle.
  Vector3 outwardNormal(int face, [Matrix4? pose]) {
    final ring = faces[face].worldRing(pose);
    final normal = _normal(ring);
    final middle = Vector3.zero();
    var count = 0;
    for (final index in islandOf(face)) {
      for (final point in faces[index].worldRing()) {
        middle.add(point);
        count++;
      }
    }
    if (count > 0) middle.scale(1 / count);
    final center = _average(ring);
    if (normal.dot(center - middle) < 0) normal.negate();
    return normal;
  }

  Vector3 worldCenter(int face, [Matrix4? pose]) =>
      faces[face].world(faces[face].centroid, pose);

  Aabb3 _bounds() {
    final box = Aabb3.minMax(
      Vector3.all(double.infinity),
      Vector3.all(-double.infinity),
    );
    for (final face in faces) {
      for (final point in face.worldRing()) {
        box.hullPoint(point);
      }
    }
    if (faces.isEmpty) return Aabb3();
    return box;
  }
}

/// A label printed on paper. [center] and [up] are in level coordinates, and
/// [size] is the shorter side of the blueprint face it sits on.
///
/// A decal belongs to the paper whose outline holds its center. It slides,
/// turns, stows, and wraps with that paper, and with no paper under it, it
/// is not drawn. It lies flat in the paper's plane and reads along [up], so
/// it turns with the paper and the model rather than the screen. Model
/// [face] shows it faintly as the place it wraps to.
class Decal {
  const Decal({
    required this.label,
    required this.center,
    this.up = const Offset(0, 1),
    required this.size,
    required this.face,
  });

  final String label;
  final Offset center;
  final Offset up;
  final double size;
  final int face;
}

/// Letters that tie each blueprint piece to the model: one on its island's
/// root face, and one on the face most nearly opposite that, if any faces
/// away from it. Letters follow face order, A, B, C, ...
List<Decal> faceDecals(FoldedModel model) {
  Decal decal(int face) => Decal(
    label: markLabel(face),
    center: model.faces[face].centroid,
    size: _shorterSide(model.faces[face].outline),
    face: face,
  );
  final decals = <Decal>[];
  for (final island in model.islands) {
    if (island.isEmpty) continue;
    final root = island.first;
    decals.add(decal(root));
    final normal = model.outwardNormal(root);
    int? opposite;
    var best = -0.5;
    for (final face in island.skip(1)) {
      final dot = model.outwardNormal(face).dot(normal);
      if (dot < best - 1e-9) {
        best = dot;
        opposite = face;
      }
    }
    if (opposite != null) decals.add(decal(opposite));
  }
  return decals;
}

/// A, B, ... Z, AA, AB, ...
String markLabel(int index) {
  var n = index;
  var label = '';
  do {
    label = String.fromCharCode(65 + n % 26) + label;
    n = n ~/ 26 - 1;
  } while (n >= 0);
  return label;
}

double _shorterSide(List<Offset> outline) {
  final box = pointBounds(outline);
  return math.min(box.width, box.height);
}

/// Folded model of [level] from the faces of [craft] on [craftingStep].
///
/// Craft outlines sit at an offset from the level and are not rounded to
/// whole cells, so each face outline is shifted by the bounds origin and
/// snapped to the grid. A face belongs to the closed blueprint piece that
/// contains it. A model that would sink below the sheet or float away from
/// its blueprint is moved to stand on the sheet over the blueprint.
FoldedModel? foldedModelFromCraft(
  CraftV1 craft,
  int craftingStep,
  GridStep level,
) {
  final members = [
    for (final face in craft.faces)
      if (face.craftingStep == craftingStep && face.flatLoops.isNotEmpty) face,
  ];
  if (members.isEmpty) return null;
  final closed = [
    for (var i = 0; i < level.polygons.length; i++)
      if (level.isRingClosed(i) && level.polygons[i].length >= 3) i,
  ];
  final levelBox = closed.isEmpty
      ? polygonBounds(level.polygons)
      : polygonBounds([for (final i in closed) level.polygons[i]]);
  final craftBox = pointBounds([
    for (final face in members)
      for (final point in face.flatLoops.first) Offset(point.x, point.y),
  ]);
  final shift = craftBox.topLeft - levelBox.topLeft;
  final spacing = level.gridSpacing <= 0 ? 1.0 : level.gridSpacing;
  Offset toLevel(Vector3 point) =>
      Offset(point.x - shift.dx, point.y - shift.dy);
  Offset snap(Offset point) => Offset(
    (point.dx / spacing).round() * spacing,
    (point.dy / spacing).round() * spacing,
  );
  final fromLevel = Matrix4.translation(Vector3(shift.dx, shift.dy, 0));
  final poses = applyFoldPose(craft, craftingStep, 1);

  final islandKeys = <String>[];
  for (final face in members) {
    if (!islandKeys.contains(face.islandKey)) islandKeys.add(face.islandKey);
  }
  final surfaces = {
    for (final face in members) '${face.islandKey}/${face.surfaceId}',
  };
  bool isRoot(CraftV1Face face) {
    final parent = face.foldParentSurfaceId;
    return parent == null || !surfaces.contains('${face.islandKey}/$parent');
  }

  final ordered = [
    for (final key in islandKeys) ...[
      for (final face in members)
        if (face.islandKey == key && isRoot(face)) face,
      for (final face in members)
        if (face.islandKey == key && !isRoot(face)) face,
    ],
  ];

  final faces = <ModelFace>[];
  final islands = [for (final _ in islandKeys) <int>[]];
  for (final face in ordered) {
    final loop = face.flatLoops.first;
    final outline = <Offset>[];
    for (final point in loop) {
      final snapped = snap(toLevel(point));
      if (outline.isNotEmpty && (outline.last - snapped).distance < 1e-9) {
        continue;
      }
      outline.add(snapped);
    }
    if (outline.length > 1 && (outline.first - outline.last).distance < 1e-9) {
      outline.removeLast();
    }
    final island = islandKeys.indexOf(face.islandKey);
    islands[island].add(faces.length);
    faces.add(
      ModelFace(
        id: face.id,
        ring: _ringHolding(level, closed, polygonCentroid(outline)),
        island: island,
        outline: outline,
        toWorld: (poses[face.id] ?? Matrix4.identity()).multiplied(fromLevel),
      ),
    );
  }

  final indexById = {for (var i = 0; i < faces.length; i++) faces[i].id: i};
  final hinges = <FoldHinge>[];
  for (final edge in craft.edges) {
    if (!edge.isFold || edge.craftingStep != craftingStep) continue;
    if (edge.curve.length < 2) continue;
    final a = indexById[edge.faceA];
    final b = indexById[edge.faceB];
    if (a == null || b == null) continue;
    hinges.add(
      FoldHinge(a, b, toLevel(edge.curve.first), toLevel(edge.curve.last)),
    );
  }

  final model = FoldedModel(faces: faces, islands: islands, hinges: hinges);
  final box = model.bounds;
  final footprint = Rect.fromLTRB(box.min.x, box.min.y, box.max.x, box.max.y);
  if (box.min.z > -1e-6 && footprint.overlaps(levelBox)) return model;
  final center = levelBox.center;
  final settle = Matrix4.translation(
    Vector3(
      center.dx - footprint.center.dx,
      center.dy - footprint.center.dy,
      -box.min.z,
    ),
  );
  return FoldedModel(
    faces: [
      for (final face in faces)
        ModelFace(
          id: face.id,
          ring: face.ring,
          island: face.island,
          outline: face.outline,
          toWorld: settle.multiplied(face.toWorld),
        ),
    ],
    islands: islands,
    hinges: hinges,
  );
}

int _ringHolding(GridStep level, List<int> closed, Offset point) {
  var best = -1;
  var bestArea = double.infinity;
  for (final i in closed) {
    final ring = level.polygons[i];
    if (!ownsPoint(ring, point)) continue;
    final area = polygonSignedArea(ring).abs();
    if (area < bestArea) {
      best = i;
      bestArea = area;
    }
  }
  if (best >= 0) return best;
  var bestDistance = double.infinity;
  for (final i in closed) {
    final distance = (polygonCentroid(level.polygons[i]) - point).distance;
    if (distance < bestDistance) {
      best = i;
      bestDistance = distance;
    }
  }
  return best;
}

/// Blueprint pieces joined by shared penciled edges. Each set folds as one.
List<Set<int>> stepIslands(GridStep step) {
  final parent = [for (var i = 0; i < step.polygons.length; i++) i];
  int find(int i) {
    while (parent[i] != i) {
      parent[i] = parent[parent[i]];
      i = parent[i];
    }
    return i;
  }

  for (var i = 0; i < step.polygons.length; i++) {
    if (!step.isRingClosed(i)) continue;
    final ring = step.polygons[i];
    final styles = step.edgeStyleOf(i);
    for (var e = 0; e < ring.length; e++) {
      if (styles[e] != EdgeStyle.penciled) continue;
      final a = ring[e];
      final b = ring[(e + 1) % ring.length];
      for (var j = 0; j < step.polygons.length; j++) {
        if (j == i || !step.isRingClosed(j)) continue;
        if (_sharesEdge(step.polygons[j], a, b)) parent[find(j)] = find(i);
      }
    }
  }
  final groups = <int, Set<int>>{};
  for (var i = 0; i < step.polygons.length; i++) {
    if (!step.isRingClosed(i)) continue;
    groups.putIfAbsent(find(i), () => <int>{}).add(i);
  }
  return groups.values.toList();
}

/// Face poses for the island of [anchor]. At 0 the island lies flat in the
/// anchor's plane. At 1 every face is at its [ModelFace.toWorld]. [from]
/// starts the anchor somewhere else and blends it home as [t] rises.
Map<int, Matrix4> wrapPose(
  FoldedModel model,
  int anchor,
  double t, {
  Matrix4? from,
}) {
  final island = model.islandOf(anchor).toSet();
  final anchorFace = model.faces[anchor];
  final poses = <int, Matrix4>{
    anchor: from == null
        ? anchorFace.toWorld.clone()
        : lerpRigid(from, anchorFace.toWorld, t),
  };
  final queue = [anchor];
  while (queue.isNotEmpty) {
    final current = queue.removeAt(0);
    for (final hinge in model.hinges) {
      final int next;
      if (hinge.a == current) {
        next = hinge.b;
      } else if (hinge.b == current) {
        next = hinge.a;
      } else {
        continue;
      }
      if (!island.contains(next) || poses.containsKey(next)) continue;
      final turn = _hingeTurn(
        model.faces[current].toWorld,
        model.faces[next].toWorld,
        hinge,
        t,
      );
      poses[next] = poses[current]!.multiplied(turn);
      queue.add(next);
    }
  }
  for (final index in island) {
    poses.putIfAbsent(index, () => poses[anchor]!.clone());
  }
  return poses;
}

/// Nearest face hit by a ray, using [poses] where given.
({int face, double distance})? pickFace(
  FoldedModel model,
  Vector3 origin,
  Vector3 direction, {
  Map<int, Matrix4>? poses,
}) {
  ({int face, double distance})? best;
  for (var i = 0; i < model.faces.length; i++) {
    final ring = model.faces[i].worldRing(poses?[i]);
    final hit = rayPolygon(origin, direction, ring);
    if (hit == null) continue;
    if (best == null || hit < best.distance) best = (face: i, distance: hit);
  }
  return best;
}

/// Ray distance to a planar polygon, fanned into Möller–Trumbore triangles.
double? rayPolygon(Vector3 origin, Vector3 direction, List<Vector3> ring) {
  if (ring.length < 3) return null;
  double? best;
  final center = _average(ring);
  for (var i = 0; i < ring.length; i++) {
    final t = _rayTriangle(
      origin,
      direction,
      center,
      ring[i],
      ring[(i + 1) % ring.length],
    );
    if (t != null && (best == null || t < best)) best = t;
  }
  return best;
}

/// Rotation about the hinge that carries [child]'s flat outline into
/// [parent]'s flat frame, scaled by [t].
Matrix4 _hingeTurn(Matrix4 parent, Matrix4 child, FoldHinge hinge, double t) {
  final relative = Matrix4.inverted(parent).multiplied(child);
  final direction = Vector3(
    hinge.end.dx - hinge.start.dx,
    hinge.end.dy - hinge.start.dy,
    0,
  );
  if (direction.length2 < 1e-12) return relative;
  direction.normalize();
  final across = Vector3(-direction.y, direction.x, 0);
  final turned = relative.getRotation().transformed(across);
  final angle = math.atan2(
    turned.dot(direction.cross(across)),
    turned.dot(across),
  );
  final pivot = Vector3(hinge.start.dx, hinge.start.dy, 0);
  return Matrix4.translation(pivot)
    ..rotate(direction, angle * t)
    ..translateByVector3(-pivot);
}

double? _rayTriangle(
  Vector3 origin,
  Vector3 direction,
  Vector3 v0,
  Vector3 v1,
  Vector3 v2,
) {
  const epsilon = 1e-9;
  final edge1 = v1 - v0;
  final edge2 = v2 - v0;
  final p = direction.cross(edge2);
  final det = edge1.dot(p);
  if (det.abs() < epsilon) return null;
  final inv = 1 / det;
  final s = origin - v0;
  final u = s.dot(p) * inv;
  if (u < 0 || u > 1) return null;
  final q = s.cross(edge1);
  final v = direction.dot(q) * inv;
  if (v < 0 || u + v > 1) return null;
  final t = edge2.dot(q) * inv;
  return t > epsilon ? t : null;
}

bool _sharesEdge(List<Offset> ring, Offset a, Offset b) {
  const eps = 1e-6;
  for (var i = 0; i < ring.length; i++) {
    final p = ring[i];
    final q = ring[(i + 1) % ring.length];
    if (((p - a).distance < eps && (q - b).distance < eps) ||
        ((p - b).distance < eps && (q - a).distance < eps)) {
      return true;
    }
  }
  return false;
}

Vector3 _normal(List<Vector3> ring) {
  final normal = Vector3.zero();
  for (var i = 0; i < ring.length; i++) {
    final a = ring[i];
    final b = ring[(i + 1) % ring.length];
    normal.x += (a.y - b.y) * (a.z + b.z);
    normal.y += (a.z - b.z) * (a.x + b.x);
    normal.z += (a.x - b.x) * (a.y + b.y);
  }
  if (normal.length2 < 1e-18) return Vector3(0, 0, 1);
  return normal.normalized();
}

Vector3 _average(List<Vector3> points) {
  final sum = Vector3.zero();
  for (final point in points) {
    sum.add(point);
  }
  return points.isEmpty ? sum : sum / points.length.toDouble();
}
