import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'craft_v1.dart';

/// Flat pose is 0. Fully folded is 1. Faces on earlier steps stay at 1.
Map<String, Matrix4> applyFoldPose(CraftV1 craft, int currentStep, double t) {
  final islands = <String, List<CraftV1Face>>{};
  final amountByIsland = <String, double>{};
  for (final face in craft.faces) {
    double? amount;
    if (face.craftingStep < currentStep) {
      amount = 1;
    } else if (face.craftingStep == currentStep) {
      amount = t;
    }
    if (amount == null) continue;
    islands.putIfAbsent(face.islandKey, () => []).add(face);
    amountByIsland.putIfAbsent(face.islandKey, () => amount!);
  }

  final posed = <String, Matrix4>{};
  for (final entry in islands.entries) {
    final members = entry.value;
    final amount = amountByIsland[entry.key] ?? 0;
    final bySurface = {for (final face in members) face.surfaceId: face};
    final children = <String?, List<String>>{};
    for (final face in members) {
      children.putIfAbsent(face.foldParentSurfaceId, () => []);
      final parent = face.foldParentSurfaceId;
      if (parent != null) {
        children.putIfAbsent(parent, () => []).add(face.surfaceId);
      }
    }
    final order = <String>[];
    final pending = bySurface.keys.toList();
    final placed = <String>{};
    while (order.length < pending.length) {
      var progressed = false;
      for (final id in pending) {
        if (placed.contains(id)) continue;
        final kids = children[id] ?? const <String>[];
        if (kids.every(placed.contains)) {
          order.add(id);
          placed.add(id);
          progressed = true;
        }
      }
      if (!progressed) break;
    }
    final matrices = {
      for (final face in members) face.surfaceId: Matrix4.identity(),
    };
    void visit(String id, Matrix4 delta) {
      final matrix = matrices[id];
      if (matrix == null) return;
      matrix.setFrom(delta.multiplied(matrix));
      for (final kid in children[id] ?? const <String>[]) {
        visit(kid, delta);
      }
    }

    for (final id in order) {
      final face = bySurface[id];
      if (face == null) continue;
      visit(id, partialInverse(face, amount));
    }
    for (final face in members) {
      final matrix = matrices[face.surfaceId];
      if (matrix != null) posed[face.id] = matrix.clone();
    }
  }
  return posed;
}

/// One face's share of the refold. Movement lerps to [CraftV1Movement.inverse].
/// Rotation is −angle × t about the axis segment.
Matrix4 partialInverse(CraftV1Face face, double t) {
  final transform = face.transform;
  if (transform is CraftV1Movement) {
    return _lerpRigid(Matrix4.identity(), transform.inverse, t);
  }
  if (transform is CraftV1Rotation) {
    final from = transform.axisStart;
    final dir = transform.axisEnd - from;
    if (dir.length2 < 1e-12) return Matrix4.identity();
    dir.normalize();
    final angle = -transform.angleRadians * t;
    final rot = Matrix4.identity()..rotate(dir, angle);
    final toOrigin = Matrix4.translation(Vector3(-from.x, -from.y, -from.z));
    final back = Matrix4.translation(from);
    return back.multiplied(rot).multiplied(toOrigin);
  }
  return Matrix4.identity();
}

/// Rhino Z-up point to the engine frame used by [ObjParser] (Y up).
Vector3 rhinoToEngine(Vector3 rhino) => Vector3(rhino.x, rhino.z, rhino.y);

Matrix4 _lerpRigid(Matrix4 from, Matrix4 to, double t) {
  final position =
      from.getTranslation() + (to.getTranslation() - from.getTranslation()) * t;
  final rotation = _slerp(
    Quaternion.fromRotation(from.getRotation()),
    Quaternion.fromRotation(to.getRotation()),
    t,
  );
  return Matrix4.compose(position, rotation, Vector3(1, 1, 1));
}

Quaternion _slerp(Quaternion a, Quaternion b, double t) {
  var bx = b.x;
  var by = b.y;
  var bz = b.z;
  var bw = b.w;
  var cos = a.x * bx + a.y * by + a.z * bz + a.w * bw;
  if (cos < 0) {
    cos = -cos;
    bx = -bx;
    by = -by;
    bz = -bz;
    bw = -bw;
  }
  if (cos > 0.9995) {
    return Quaternion(
      a.x + (bx - a.x) * t,
      a.y + (by - a.y) * t,
      a.z + (bz - a.z) * t,
      a.w + (bw - a.w) * t,
    ).normalized();
  }
  final theta = math.acos(cos.clamp(-1.0, 1.0));
  final sinTheta = math.sin(theta);
  final wa = math.sin((1 - t) * theta) / sinTheta;
  final wb = math.sin(t * theta) / sinTheta;
  return Quaternion(
    wa * a.x + wb * bx,
    wa * a.y + wb * by,
    wa * a.z + wb * bz,
    wa * a.w + wb * bw,
  );
}
