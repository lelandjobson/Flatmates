import 'package:vector_math/vector_math_64.dart';

import '../friends/friend_instance.dart';
import '../friends/friend_mesh_sync.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';

/// A grouped scene object that Show gizmos mode can select and translate.
abstract class GizmoTarget {
  String get id;
  bool get allowsVertical;
  Vector3 get worldCenter;
  (Vector3 min, Vector3 max) get worldBounds;
  void translate(Vector3 worldDelta);
}

class FriendGizmoTarget implements GizmoTarget {
  FriendGizmoTarget(this.instance, {required this.tileSize});

  final FriendInstance instance;
  final double tileSize;

  @override
  String get id => 'friend:${instance.id}';

  @override
  bool get allowsVertical => false;

  @override
  Vector3 get worldCenter => Vector3.copy(instance.position);

  @override
  (Vector3 min, Vector3 max) get worldBounds {
    final half = FriendMeshLayout.halfSize(tileSize: tileSize);
    final p = instance.position;
    return (
      Vector3(p.x - half, p.y - half, p.z - half),
      Vector3(p.x + half, p.y + half, p.z + half),
    );
  }

  @override
  void translate(Vector3 worldDelta) {
    instance.position.add(worldDelta);
    final minY = FriendMeshLayout.sitOnGroundY(tileSize: tileSize);
    if (instance.position.y < minY) instance.position.y = minY;
  }

  void setPosition(Vector3 value) {
    instance.position.setFrom(value);
    final minY = FriendMeshLayout.sitOnGroundY(tileSize: tileSize);
    if (instance.position.y < minY) instance.position.y = minY;
  }
}

class VolumeGizmoTarget implements GizmoTarget {
  VolumeGizmoTarget({
    required this.volume,
    required this.store,
    this.blocked,
  });

  final Volume volume;
  final VolumeStore store;
  final bool Function(int tx, int ty)? blocked;

  /// Visual offset on top of committed tile positions while dragging.
  final Vector3 previewOffset = Vector3.zero();
  int committedDtx = 0;
  int committedDty = 0;

  @override
  String get id => 'volume:${volume.id}';

  @override
  bool get allowsVertical => false;

  Vector3 get _committedCenter {
    if (volume.cells.isEmpty) return Vector3.zero();
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final cell in volume.cells) {
      final min = cell.box.worldMin(store.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(store.grid, cell.tx, cell.ty);
      minX = mathMin(minX, min.x);
      minY = mathMin(minY, min.y);
      minZ = mathMin(minZ, min.z);
      maxX = mathMax(maxX, max.x);
      maxY = mathMax(maxY, max.y);
      maxZ = mathMax(maxZ, max.z);
    }
    return Vector3(
      (minX + maxX) * 0.5,
      (minY + maxY) * 0.5,
      (minZ + maxZ) * 0.5,
    );
  }

  @override
  Vector3 get worldCenter => _committedCenter + previewOffset;

  @override
  (Vector3 min, Vector3 max) get worldBounds {
    if (volume.cells.isEmpty) {
      return (Vector3.zero(), Vector3.zero());
    }
    var minX = double.infinity;
    var minY = double.infinity;
    var minZ = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    var maxZ = -double.infinity;
    for (final cell in volume.cells) {
      final min = cell.box.worldMin(store.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(store.grid, cell.tx, cell.ty);
      minX = mathMin(minX, min.x);
      minY = mathMin(minY, min.y);
      minZ = mathMin(minZ, min.z);
      maxX = mathMax(maxX, max.x);
      maxY = mathMax(maxY, max.y);
      maxZ = mathMax(maxZ, max.z);
    }
    final o = previewOffset;
    return (
      Vector3(minX + o.x, minY + o.y, minZ + o.z),
      Vector3(maxX + o.x, maxY + o.y, maxZ + o.z),
    );
  }

  @override
  void translate(Vector3 worldDelta) {
    applyTotalDelta(previewOffset + worldDelta);
  }

  /// Snap toward [totalDelta] from the drag origin. Returns tile steps applied.
  (int dtx, int dty) applyTotalDelta(Vector3 totalDelta) {
    final tile = store.grid.tileSize;
    final desiredX = (totalDelta.x / tile).round();
    final desiredY = (totalDelta.z / tile).round();
    var appliedX = 0;
    var appliedY = 0;
    final stepX = desiredX - committedDtx;
    final stepY = desiredY - committedDty;
    if (stepX != 0 &&
        store.tryTranslate(volume, stepX, 0, blocked: blocked)) {
      committedDtx += stepX;
      appliedX = stepX;
    }
    if (stepY != 0 &&
        store.tryTranslate(volume, 0, stepY, blocked: blocked)) {
      committedDty += stepY;
      appliedY = stepY;
    }
    previewOffset.setValues(
      totalDelta.x - committedDtx * tile,
      0,
      totalDelta.z - committedDty * tile,
    );
    return (appliedX, appliedY);
  }

  void resetDrag() {
    committedDtx = 0;
    committedDty = 0;
    previewOffset.setZero();
  }
}

double mathMin(double a, double b) => a < b ? a : b;
double mathMax(double a, double b) => a > b ? a : b;
