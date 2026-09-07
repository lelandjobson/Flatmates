import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import '../volumes/volume.dart';
import '../volumes/volume_solid.dart';
import '../volumes/volume_store.dart';
import 'stuff_catalog.dart';
import 'stuff_geometry.dart';
import 'stuff_instance.dart';

/// Padded world AABB used for picking. Never starts inside the anchor solid.
(Vector3 min, Vector3 max) stuffSelectionHull(StuffInstance item) {
  final spec = item.spec;
  final (localMin, localMax) = stuffLocalBounds(item.specId);
  final pad = spec?.hullPad ?? kStuffHullPad;
  final minDim = spec?.hullMin ?? kStuffHullMin;
  var min = Vector3.copy(localMin);
  var max = Vector3.copy(localMax);
  void grow(int axis) {
    final span = switch (axis) {
      0 => max.x - min.x,
      1 => max.y - min.y,
      _ => max.z - min.z,
    };
    final extra = ((minDim - span).clamp(0.0, minDim) + pad * 2) * 0.5;
    switch (axis) {
      case 0:
        min.x -= extra;
        max.x += extra;
      case 1:
        min.y -= extra;
        max.y += extra;
      default:
        min.z -= extra;
        max.z += extra;
    }
  }

  grow(0);
  grow(1);
  grow(2);

  // Pull the hull off the local sit-plane (y=0 floor, z=0 wall).
  if (spec?.isWall ?? item.face != VolumeFace.negY) {
    if (min.z < kStuffPlaneEpsilon) min.z = kStuffPlaneEpsilon;
  } else {
    if (min.y < kStuffPlaneEpsilon) min.y = kStuffPlaneEpsilon;
  }

  return _transformAabb(min, max, item.origin, stuffEuler(item.face, item.yaw));
}

List<Vector3> stuffHullSamples((Vector3 min, Vector3 max) hull) {
  final min = hull.$1;
  final max = hull.$2;
  final mid = (min + max) * 0.5;
  return [
    mid,
    Vector3(min.x, min.y, min.z),
    Vector3(max.x, min.y, min.z),
    Vector3(min.x, max.y, min.z),
    Vector3(max.x, max.y, min.z),
    Vector3(min.x, min.y, max.z),
    Vector3(max.x, min.y, max.z),
    Vector3(min.x, max.y, max.z),
    Vector3(max.x, max.y, max.z),
  ];
}

/// True when the hull stays in the mass cavity and does not hit the shell.
bool stuffIsValid(StuffInstance item, VolumeStore volumes) {
  final volume = volumes.volumeById(item.volumeId);
  if (volume == null) return false;
  final hull = stuffSelectionHull(item);
  final solid = resolveVolumeSolid(volume, volumes.grid);
  for (final sample in stuffHullSamples(hull)) {
    if (_inAnchorSlab(sample, item, volumes.grid, volume)) continue;
    if (!_interiorContains(sample, volume, volumes.grid, item.face)) {
      return false;
    }
    if (_shellContains(sample, solid, volume, volumes.grid, item.face)) {
      return false;
    }
  }
  return true;
}

bool _inAnchorSlab(
  Vector3 point,
  StuffInstance item,
  VolumeGrid grid,
  Volume volume,
) {
  final cell = volume.cellAt(item.tx, item.ty);
  if (cell == null) return false;
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  final (origin, normal) = item.face.originAndNormal(min, max);
  final depth = (point - origin).dot(normal);
  // Outward-positive. Into the room is negative. Ignore a thin inward slab
  // and only fail later if the point goes the other way too far.
  return depth.abs() <= kStuffAnchorSlab &&
      depth > -kStuffSevereAnchor;
}

bool _interiorContains(
  Vector3 point,
  Volume volume,
  VolumeGrid grid,
  VolumeFace anchor,
) {
  const inset = 0.08;
  for (final cell in volume.cells) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    var x0 = min.x + inset;
    var x1 = max.x - inset;
    var y0 = min.y + inset;
    var y1 = max.y - inset;
    var z0 = min.z + inset;
    var z1 = max.z - inset;
    switch (anchor) {
      case VolumeFace.negY:
        y0 = min.y;
      case VolumeFace.posY:
        y1 = max.y;
      case VolumeFace.posX:
        x1 = max.x;
      case VolumeFace.negX:
        x0 = min.x;
      case VolumeFace.posZ:
        z1 = max.z;
      case VolumeFace.negZ:
        z0 = min.z;
    }
    if (point.x >= x0 &&
        point.x <= x1 &&
        point.y >= y0 &&
        point.y <= y1 &&
        point.z >= z0 &&
        point.z <= z1) {
      return true;
    }
  }
  return false;
}

bool _shellContains(
  Vector3 point,
  VolumeSolid solid,
  Volume volume,
  VolumeGrid grid,
  VolumeFace anchor,
) {
  const thickness = 0.08;
  for (final cell in volume.cells) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    for (final face in VolumeFace.values) {
      if (face == anchor) {
        final (origin, normal) = face.originAndNormal(min, max);
        final depth = (point - origin).dot(normal);
        if (depth > kStuffSevereAnchor) return true;
        continue;
      }
      if (!face.containsHit(point, min, max, eps: thickness)) continue;
      final (origin, normal) = face.originAndNormal(min, max);
      if ((point - origin).dot(normal).abs() > thickness) continue;
      if (face == VolumeFace.negY) return true;
      final handle = handleForFace(face);
      if (handle == null) continue;
      final surface = solid.surfaceAt(cell.tx, cell.ty, handle);
      if (surface == null) continue;
      final uv = faceUvAt(world: point, grid: grid, cell: cell, face: face);
      if (uv == null) continue;
      for (final fragment in surface.fragments) {
        if (fragment.containsUv(uv.$1, uv.$2)) return true;
      }
    }
  }
  return false;
}

(Vector3 min, Vector3 max) _transformAabb(
  Vector3 min,
  Vector3 max,
  Vector3 origin,
  Vector3 euler,
) {
  final corners = [
    Vector3(min.x, min.y, min.z),
    Vector3(max.x, min.y, min.z),
    Vector3(min.x, max.y, min.z),
    Vector3(max.x, max.y, min.z),
    Vector3(min.x, min.y, max.z),
    Vector3(max.x, min.y, max.z),
    Vector3(min.x, max.y, max.z),
    Vector3(max.x, max.y, max.z),
  ];
  final matrix = Matrix4.identity()
    ..translate(origin)
    ..rotateX(euler.x)
    ..rotateY(euler.y)
    ..rotateZ(euler.z);
  var outMin = Vector3(double.infinity, double.infinity, double.infinity);
  var outMax = Vector3(-double.infinity, -double.infinity, -double.infinity);
  for (final corner in corners) {
    final world = matrix.transformed3(corner);
    outMin = Vector3(
      outMin.x < world.x ? outMin.x : world.x,
      outMin.y < world.y ? outMin.y : world.y,
      outMin.z < world.z ? outMin.z : world.z,
    );
    outMax = Vector3(
      outMax.x > world.x ? outMax.x : world.x,
      outMax.y > world.y ? outMax.y : world.y,
      outMax.z > world.z ? outMax.z : world.z,
    );
  }
  return (outMin, outMax);
}
