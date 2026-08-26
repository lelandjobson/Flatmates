import '../friends/friend_instance_store.dart';
import '../volumes/volume_box_mesh.dart';
import '../volumes/volume_store.dart';
import 'gizmo_target.dart';

/// Parses `friend_{id}_body`.
String? parseFriendInstanceId(String meshId) {
  const prefix = 'friend_';
  const suffix = '_body';
  if (!meshId.startsWith(prefix) || !meshId.endsWith(suffix)) return null;
  return meshId.substring(prefix.length, meshId.length - suffix.length);
}

/// Parses `volume_{id}_{tx}_{ty}`.
({int volumeId, int tx, int ty})? parseVolumeMeshIdParts(String meshId) {
  const prefix = 'volume_';
  if (!meshId.startsWith(prefix)) return null;
  final parts = meshId.substring(prefix.length).split('_');
  if (parts.length != 3) return null;
  final volumeId = int.tryParse(parts[0]);
  final tx = int.tryParse(parts[1]);
  final ty = int.tryParse(parts[2]);
  if (volumeId == null || tx == null || ty == null) return null;
  return (volumeId: volumeId, tx: tx, ty: ty);
}

/// Maps a scene mesh id to a grouped [GizmoTarget], or null if unhandled.
GizmoTarget? resolveGizmoTarget({
  required String meshId,
  required FriendInstanceStore friends,
  required VolumeStore volumes,
  required double tileSize,
  bool Function(int tx, int ty)? pathBlocked,
}) {
  final friendId = parseFriendInstanceId(meshId);
  if (friendId != null) {
    final instance = friends.byId(friendId);
    if (instance == null) return null;
    return FriendGizmoTarget(instance, tileSize: tileSize);
  }

  final volumeParts = parseVolumeMeshIdParts(meshId);
  if (volumeParts != null) {
    final volume = volumes.volumeById(volumeParts.volumeId);
    if (volume == null) return null;
    return VolumeGizmoTarget(
      volume: volume,
      store: volumes,
      blocked: pathBlocked,
    );
  }

  return null;
}

/// True when [a] and [b] resolve to the same grouped target.
bool sameGizmoGroup(String meshIdA, String meshIdB) {
  final friendA = parseFriendInstanceId(meshIdA);
  final friendB = parseFriendInstanceId(meshIdB);
  if (friendA != null || friendB != null) {
    return friendA != null && friendA == friendB;
  }
  final volA = parseVolumeMeshIdParts(meshIdA);
  final volB = parseVolumeMeshIdParts(meshIdB);
  if (volA != null || volB != null) {
    return volA != null && volB != null && volA.volumeId == volB.volumeId;
  }
  return meshIdA == meshIdB;
}

/// Re-export so tests can compare against the canonical volume mesh id helper.
String volumeCellMeshId(int volumeId, int tx, int ty) =>
    volumeMeshId(volumeId, tx, ty);
