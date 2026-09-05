import 'package:flutter/material.dart';

import '../paths/path_store.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_store.dart';
import 'volume.dart';
import 'volume_applique.dart';
import 'volume_door.dart';
import 'volume_store.dart';

/// True when [tx],[ty] is a volume cell with an outdoor path on an ortho side.
bool volumeHasAdjacentOutdoorPath({
  required VolumeStore volumes,
  required PathStore paths,
  required int tx,
  required int ty,
}) {
  if (!volumes.isOccupied(tx, ty)) return false;
  for (final side in VolumeSide.values) {
    final (dx, dy) = side.tileDelta;
    final nx = tx + dx;
    final ny = ty + dy;
    if (volumes.isOccupied(nx, ny)) continue;
    if (paths.contains(nx, ny)) return true;
  }
  return false;
}

/// Path tool on a volume only if an outdoor path already meets it.
bool canPaintPathAt({
  required VolumeStore volumes,
  required PathStore paths,
  required int tx,
  required int ty,
}) {
  if (!volumes.isOccupied(tx, ty)) return true;
  return volumeHasAdjacentOutdoorPath(
    volumes: volumes,
    paths: paths,
    tx: tx,
    ty: ty,
  );
}

/// Drop path tiles that sit under a committed volume so no path geo is buried.
/// Call only when a volume cell is newly placed, not after painting a door path.
int evictPathsUnderVolumes(PathStore paths, VolumeStore volumes) {
  var removed = 0;
  for (final tile in List<(int, int)>.from(paths.tiles)) {
    if (!_committedOccupied(volumes, tile.$1, tile.$2)) continue;
    if (paths.removeTile(tile.$1, tile.$2)) removed++;
  }
  return removed;
}

bool _committedOccupied(VolumeStore volumes, int tx, int ty) {
  for (final volume in volumes.volumes) {
    if (volume.cellAt(tx, ty) != null) return true;
  }
  return false;
}

/// True when [edge] sits between a volume cell and a non-volume tile.
bool isVolumePathBoundary(WallEdge edge, VolumeStore volumes) {
  final pair = edge.separatedTiles;
  if (pair == null) return false;
  final a = volumes.isOccupied(pair.$1.$1, pair.$1.$2);
  final b = volumes.isOccupied(pair.$2.$1, pair.$2.$2);
  return a != b;
}

/// True when a door already faces across [edge].
bool volumeDoorAcross(WallEdge edge, VolumeStore volumes) {
  final pair = edge.separatedTiles;
  if (pair == null) return false;
  for (final (tile, other) in [(pair.$1, pair.$2), (pair.$2, pair.$1)]) {
    final volume = volumes.volumeAt(tile.$1, tile.$2);
    final cell = volume?.cellAt(tile.$1, tile.$2);
    if (cell == null) continue;
    final side = _sideToward(tile, other);
    if (side != null && cell.accessibleSides.contains(side)) return true;
  }
  return false;
}

VolumeSide? _sideToward((int, int) from, (int, int) to) {
  final dx = to.$1 - from.$1;
  final dy = to.$2 - from.$2;
  for (final side in VolumeSide.values) {
    if (side.tileDelta == (dx, dy)) return side;
  }
  return null;
}

/// Outdoor path on the tile that shares [side]'s edge. Corners do not count.
bool outdoorPathMeetsSide({
  required Volume volume,
  required VolumeCell cell,
  required VolumeSide side,
  required PathStore paths,
}) {
  final (dx, dy) = side.tileDelta;
  final ntx = cell.tx + dx;
  final nty = cell.ty + dy;
  if (volume.cellAt(ntx, nty) != null) return false;
  return paths.contains(ntx, nty);
}

/// Interior path plus an outdoor path on the tile across [side], and no wall.
bool pathRequiresDoor({
  required Volume volume,
  required VolumeCell cell,
  required VolumeSide side,
  required PathStore paths,
  WallStore? walls,
}) {
  final (dx, dy) = side.tileDelta;
  final ntx = cell.tx + dx;
  final nty = cell.ty + dy;
  if (volume.cellAt(ntx, nty) != null) return false;
  if (!paths.contains(cell.tx, cell.ty)) return false;
  if (walls != null && walls.separatesTiles((cell.tx, cell.ty), (ntx, nty))) {
    return false;
  }
  return outdoorPathMeetsSide(
    volume: volume,
    cell: cell,
    side: side,
    paths: paths,
  );
}

/// Create centered doors where an interior path meets an outdoor path across
/// that side; remove doors that no longer qualify. Door papers sit on
/// applique layer max+1.
bool syncVolumeDoorsFromPaths({
  required VolumeStore volumes,
  required PathStore paths,
  required VolumeAppliqueStore appliques,
  WallStore? walls,
  Color? doorColor,
}) {
  var changed = false;
  final wantedDoors = <(int, int, int, VolumeSide)>{};

  for (final volume in volumes.visibleVolumes) {
    for (final cell in volume.cells) {
      for (final side in VolumeSide.values) {
        final need = pathRequiresDoor(
          volume: volume,
          cell: cell,
          side: side,
          paths: paths,
          walls: walls,
        );
        final has = cell.accessibleSides.contains(side);
        if (need) {
          wantedDoors.add((volume.id, cell.tx, cell.ty, side));
          if (!has) {
            final door = volumeDoorForSide(cell.box, side);
            if (door == null) continue;
            if (volumes.placeDoor(
              volume: volume,
              cell: cell,
              side: side,
              originU: door.originU,
            )) {
              changed = true;
            }
          }
          final live = volume.cellAt(cell.tx, cell.ty) ?? cell;
          final door = volumeDoorForSide(
            live.box,
            side,
            originU: live.doorOrigins[side],
          );
          if (door == null) continue;
          final before = appliques.doorOn(
            volumeId: volume.id,
            tx: cell.tx,
            ty: cell.ty,
            side: side,
          );
          final paper = appliques.placeOrMoveDoor(
            volume: volume,
            cell: live,
            side: side,
            door: door,
            color: doorColor,
          );
          if (before == null || before.color != paper.color) {
            changed = true;
          }
        } else if (has) {
          if (volumes.removeDoor(volume: volume, cell: cell, side: side)) {
            changed = true;
          }
          if (appliques.removeDoor(
            volumeId: volume.id,
            tx: cell.tx,
            ty: cell.ty,
            side: side,
          )) {
            changed = true;
          }
        }
      }
    }
  }

  for (final item in List<VolumeApplique>.from(appliques.items)) {
    if (item.kind != VolumeAppliqueKind.door || item.side == null) continue;
    if (wantedDoors.contains((item.volumeId, item.tx, item.ty, item.side!))) {
      continue;
    }
    if (appliques.removeId(item.id)) changed = true;
  }
  return changed;
}
