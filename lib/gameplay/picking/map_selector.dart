import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../rendering/scene/camera.dart';
import '../friends/friend_instance_store.dart';
import '../friends/friend_mesh_sync.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_regions.dart';
import 'selectable.dart';
import 'volume_face_picker.dart';

/// Zoom-aware pick of a map entity along a screen ray.
class MapSelector {
  const MapSelector({this.facePicker = const VolumeFacePicker()});

  final VolumeFacePicker facePicker;

  SelectableHit? pick({
    required Offset screen,
    required Size viewport,
    required Camera camera,
    required double distance,
    required VolumeStore volumes,
    required FriendInstanceStore friends,
    required Iterable<WallRegion> regions,
    double faceMaxDistance = kSelectVolumeFacesBelowDistance,
    double tileSize = 8,
  }) {
    if (viewport.width <= 0 || viewport.height <= 0) return null;

    final face = facePicker.pick(
      screen: screen,
      viewport: viewport,
      camera: camera,
      store: volumes,
    );
    if (face != null) {
      if (distance <= faceMaxDistance) {
        return SelectableHit.volumeFace(
          face.volumeId,
          face: face.face,
          cell: face.cell,
          worldPoint: face.worldPoint,
        );
      }
      return SelectableHit.volume(
        face.volumeId,
        cell: face.cell,
        worldPoint: face.worldPoint,
      );
    }

    final friend = _pickFriend(
      screen: screen,
      viewport: viewport,
      camera: camera,
      friends: friends,
      tileSize: tileSize,
    );
    if (friend != null) return friend;

    final ground = camera.intersectGround(screen, viewport);
    if (ground == null) return null;
    final tile = volumes.grid.tileAtWorld(ground);
    if (tile == null) return null;
    final region = wallRegionContaining(regions, tile.$1, tile.$2);
    if (region != null) {
      return SelectableHit.region(
        region,
        tx: tile.$1,
        ty: tile.$2,
        worldPoint: ground,
      );
    }
    return SelectableHit.tile(tile.$1, tile.$2, worldPoint: ground);
  }

  SelectableHit? _pickFriend({
    required Offset screen,
    required Size viewport,
    required Camera camera,
    required FriendInstanceStore friends,
    required double tileSize,
  }) {
    final ray = camera.unprojectRay(screen, viewport);
    if (ray == null) return null;
    SelectableHit? best;
    var bestT = double.infinity;
    final half = FriendMeshLayout.halfSize(tileSize: tileSize);
    for (final instance in friends.instances) {
      final min = instance.position - Vector3(half, half, half);
      final max = instance.position + Vector3(half, half, half);
      final t = _rayAabb(ray, min, max);
      if (t == null || t >= bestT) continue;
      bestT = t;
      best = SelectableHit.friend(instance.id, worldPoint: ray.pointAt(t));
    }
    return best;
  }

  static double? _rayAabb(CameraRay ray, Vector3 min, Vector3 max) {
    var tMin = 0.0;
    var tMax = double.infinity;
    bool slab(double origin, double dir, double a, double b) {
      if (dir.abs() < 1e-8) return origin >= a && origin <= b;
      final inv = 1.0 / dir;
      var t1 = (a - origin) * inv;
      var t2 = (b - origin) * inv;
      if (t1 > t2) {
        final swap = t1;
        t1 = t2;
        t2 = swap;
      }
      if (t1 > tMin) tMin = t1;
      if (t2 < tMax) tMax = t2;
      return tMin <= tMax;
    }

    if (!slab(ray.origin.x, ray.direction.x, min.x, max.x)) return null;
    if (!slab(ray.origin.y, ray.direction.y, min.y, max.y)) return null;
    if (!slab(ray.origin.z, ray.direction.z, min.z, max.z)) return null;
    if (tMax < 1e-4) return null;
    return tMin >= 1e-4 ? tMin : tMax;
  }
}
