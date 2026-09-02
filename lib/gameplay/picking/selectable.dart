import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import '../volumes/volume.dart';
import '../walls/wall_regions.dart';

/// Camera distance at or below which a volume hit selects a face, not the mass.
const double kSelectVolumeFacesBelowDistance = 80;

enum SelectableKind { tile, region, friend, volume, volumeFace, path }

/// One pick of a map entity under a screen ray.
class SelectableHit {
  const SelectableHit({
    required this.kind,
    this.tx,
    this.ty,
    this.volumeId,
    this.cell,
    this.face,
    this.friendId,
    this.region,
    this.worldPoint,
  });

  factory SelectableHit.tile(int tx, int ty, {Vector3? worldPoint}) =>
      SelectableHit(
        kind: SelectableKind.tile,
        tx: tx,
        ty: ty,
        worldPoint: worldPoint,
      );

  factory SelectableHit.region(
    WallRegion region, {
    int? tx,
    int? ty,
    Vector3? worldPoint,
  }) =>
      SelectableHit(
        kind: SelectableKind.region,
        region: region,
        tx: tx,
        ty: ty,
        worldPoint: worldPoint,
      );

  factory SelectableHit.friend(String friendId, {Vector3? worldPoint}) =>
      SelectableHit(
        kind: SelectableKind.friend,
        friendId: friendId,
        worldPoint: worldPoint,
      );

  factory SelectableHit.volume(
    int volumeId, {
    VolumeCell? cell,
    int? tx,
    int? ty,
    Vector3? worldPoint,
  }) =>
      SelectableHit(
        kind: SelectableKind.volume,
        volumeId: volumeId,
        cell: cell,
        tx: tx ?? cell?.tx,
        ty: ty ?? cell?.ty,
        worldPoint: worldPoint,
      );

  factory SelectableHit.path(int tx, int ty, {Vector3? worldPoint}) =>
      SelectableHit(
        kind: SelectableKind.path,
        tx: tx,
        ty: ty,
        worldPoint: worldPoint,
      );

  factory SelectableHit.volumeFace(
    int volumeId, {
    required VolumeFace face,
    VolumeCell? cell,
    Vector3? worldPoint,
  }) =>
      SelectableHit(
        kind: SelectableKind.volumeFace,
        volumeId: volumeId,
        face: face,
        cell: cell,
        tx: cell?.tx,
        ty: cell?.ty,
        worldPoint: worldPoint,
      );

  final SelectableKind kind;
  final int? tx;
  final int? ty;
  final int? volumeId;
  final VolumeCell? cell;
  final VolumeFace? face;
  final String? friendId;
  final WallRegion? region;
  final Vector3? worldPoint;

  /// Volumes, faces, regions, paths, and friends — not bare tiles.
  bool get isCreatedObject => kind != SelectableKind.tile;

  String get debugLabel {
    switch (kind) {
      case SelectableKind.tile:
        return 'tile (${tx ?? '?'},${ty ?? '?'})';
      case SelectableKind.region:
        return 'region ${region?.tiles.length ?? 0}t';
      case SelectableKind.friend:
        return 'friend ${friendId ?? '?'}';
      case SelectableKind.volume:
        return 'volume v${volumeId ?? '?'}';
      case SelectableKind.path:
        return 'path (${tx ?? '?'},${ty ?? '?'})';
      case SelectableKind.volumeFace:
        return 'volumeFace v${volumeId ?? '?'} ${face?.name ?? '?'}';
    }
  }

  bool sameAs(SelectableHit? other) {
    if (other == null || other.kind != kind) return false;
    return switch (kind) {
      SelectableKind.tile => tx == other.tx && ty == other.ty,
      SelectableKind.region =>
        region != null && other.region != null && region == other.region,
      SelectableKind.friend => friendId == other.friendId,
      SelectableKind.path => tx == other.tx && ty == other.ty,
      SelectableKind.volume => volumeId == other.volumeId,
      SelectableKind.volumeFace =>
        volumeId == other.volumeId &&
            face == other.face &&
            cell?.tx == other.cell?.tx &&
            cell?.ty == other.cell?.ty,
    };
  }
}
