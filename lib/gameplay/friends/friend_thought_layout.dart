import 'dart:ui';

import 'package:vector_math/vector_math_64.dart';

import '../../rendering/scene/camera.dart';
import '../volumes/volume_store.dart';
import 'friend_instance.dart';
import 'friend_instance_store.dart';
import 'friend_mesh_sync.dart';
import 'friend_overlay_visibility.dart';

/// Original high lift (above the day-action bar).
const double kThoughtBubbleLift = 4.4;

/// Extra world height above the crown used for the low percolate seat.
const double kPercolateAboveHead = 0.28;
const double kThoughtInViewInset = 24;

/// Midpoint between the old high card seat and the low crown seat.
double thoughtLift({required double tileSize}) {
  final low = FriendMeshLayout.halfSize(tileSize: tileSize) + kPercolateAboveHead;
  return (kThoughtBubbleLift + low) * 0.5;
}

Vector3 thoughtAnchor(
  FriendInstance friend, {
  required double tileSize,
}) {
  return Vector3(
    friend.position.x,
    friend.position.y + thoughtLift(tileSize: tileSize),
    friend.position.z,
  );
}

Vector3 percolateAnchor(
  FriendInstance friend, {
  required double tileSize,
}) =>
    thoughtAnchor(friend, tileSize: tileSize);

bool friendThoughtInView({
  required FriendInstance friend,
  required Camera camera,
  required Size viewport,
  double tileSize = 8,
  VolumeStore? volumes,
  bool Function(int tx, int ty)? interiorOpen,
  double inset = kThoughtInViewInset,
}) {
  if (hideFriendOverlay(
    position: friend.position,
    volumes: volumes,
    interiorOpen: interiorOpen,
  )) {
    return false;
  }
  if (viewport.isEmpty) return false;
  final screen = camera.projectToScreen(
    thoughtAnchor(friend, tileSize: tileSize),
    viewport,
  );
  if (screen == null) return false;
  return screen.dx >= inset &&
      screen.dy >= inset &&
      screen.dx <= viewport.width - inset &&
      screen.dy <= viewport.height - inset;
}

String? hitFriendId({
  required Offset screen,
  required Size viewport,
  required Camera camera,
  required FriendInstanceStore friends,
  required double tileSize,
}) {
  final ray = camera.unprojectRay(screen, viewport);
  if (ray == null) return null;
  String? best;
  var bestT = double.infinity;
  final half = FriendMeshLayout.halfSize(tileSize: tileSize);
  for (final instance in friends.instances) {
    final min = instance.position - Vector3(half, half, half);
    final max = instance.position + Vector3(half, half, half);
    final t = _rayAabb(ray, min, max);
    if (t == null || t >= bestT) continue;
    bestT = t;
    best = instance.id;
  }
  return best;
}

double? _rayAabb(CameraRay ray, Vector3 min, Vector3 max) {
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
  return tMin;
}
