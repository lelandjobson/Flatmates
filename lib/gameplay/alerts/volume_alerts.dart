import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../ui/game/game_tool_carousel.dart';
import '../paths/path_store.dart';
import '../picking/selectable.dart';
import '../volumes/volume.dart';
import '../volumes/volume_ceiling_reveal.dart';
import '../volumes/volume_door_sync.dart';
import '../volumes/volume_program.dart';
import '../volumes/volume_program_clusters.dart';
import '../volumes/volume_program_graph.dart';
import '../volumes/volume_program_visibility.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_store.dart';
import 'world_alert.dart';

/// Derived volume alerts: one sandwich per mass, all unresolved issues.
List<WorldAlert> collectVolumeAlerts({
  required VolumeStore volumes,
  required VolumeProgramStore programs,
  required WallStore walls,
  required PathStore paths,
}) {
  final out = <WorldAlert>[];
  for (final volume in volumes.visibleVolumes) {
    final alert = volumeAlertFor(
      volume: volume,
      volumes: volumes,
      programs: programs,
      walls: walls,
      paths: paths,
    );
    if (alert != null) out.add(alert);
  }
  return out;
}

WorldAlert? volumeAlertFor({
  required Volume volume,
  required VolumeStore volumes,
  required VolumeProgramStore programs,
  required WallStore walls,
  required PathStore paths,
}) {
  if (volume.cells.isEmpty) return null;
  final graph = buildVolumeProgramGraph(
    volume: volume,
    programs: programs,
    walls: walls,
  );
  final kinds = volumeAlerts(
    programmed: programs.isVolumeProgrammed(volume),
    hasEntry: volume.hasEntry,
    bedroomNeedsAccess: graph.hasDisconnectedBedroom,
  );
  if (kinds.isEmpty) return null;
  return WorldAlert(
    id: 'volume:${volume.id}',
    hostKey: volumeHostKey(volume.id),
    world: volumeTopCenter(volume, volumes.grid),
    issues: [
      for (final kind in kinds)
        switch (kind) {
          VolumeAlertKind.unprogrammed =>
            _unprogrammedIssue(volume, volumes.grid),
          VolumeAlertKind.noEntry => _noEntryIssue(volume, volumes, paths),
          VolumeAlertKind.bedroomAccess =>
            _bedroomIssue(volume, volumes.grid, graph),
        },
    ],
  );
}

WorldAlertIssue _unprogrammedIssue(Volume volume, VolumeGrid grid) {
  final tile = centermostTile([
    for (final cell in volume.cells) (cell.tx, cell.ty),
  ]);
  final cell = volume.cellAt(tile.$1, tile.$2)!;
  return WorldAlertIssue(
    id: 'volume:${volume.id}:unprogrammed',
    requirementIcon: Icons.weekend_outlined,
    remediation: AlertRemediation(
      mode: GameMode.select,
      lookAt: _tileLookAt(cell, grid),
      distance: kVolumeLookInsideDistance,
      select: true,
      tx: cell.tx,
      ty: cell.ty,
      volumeId: volume.id,
      selectKind: SelectableKind.volume,
      openProgramPicker: true,
    ),
  );
}

WorldAlertIssue _noEntryIssue(
  Volume volume,
  VolumeStore volumes,
  PathStore paths,
) {
  final tile = doorCandidateTile(
    volume: volume,
    volumes: volumes,
    paths: paths,
  );
  final cell = volume.cellAt(tile.$1, tile.$2) ?? volume.cells.first;
  return WorldAlertIssue(
    id: 'volume:${volume.id}:noEntry',
    requirementIcon: Icons.door_front_door_outlined,
    remediation: AlertRemediation(
      mode: GameMode.create,
      createTool: GameCreateTool.path,
      lookAt: _tileLookAt(cell, volumes.grid),
      distance: kVolumeLookInsideDistance,
      select: true,
      tx: cell.tx,
      ty: cell.ty,
      volumeId: volume.id,
      selectKind: SelectableKind.volume,
    ),
  );
}

WorldAlertIssue _bedroomIssue(
  Volume volume,
  VolumeGrid grid,
  ProgramGraph graph,
) {
  final bedroom = graph.disconnectedBedrooms.isEmpty
      ? null
      : graph.disconnectedBedrooms.first;
  final tiles = bedroom?.tiles.isNotEmpty == true
      ? bedroom!.tiles
      : {for (final cell in volume.cells) (cell.tx, cell.ty)};
  final tile = centermostTile(tiles);
  final cell = volume.cellAt(tile.$1, tile.$2) ?? volume.cells.first;
  return WorldAlertIssue(
    id: 'volume:${volume.id}:bedroomAccess',
    requirementIcon: Icons.bed_outlined,
    remediation: AlertRemediation(
      mode: GameMode.select,
      lookAt: _tileLookAt(cell, grid),
      distance: kVolumeLookInsideDistance,
      select: true,
      tx: cell.tx,
      ty: cell.ty,
      volumeId: volume.id,
      selectKind: SelectableKind.volume,
    ),
  );
}

String volumeHostKey(int volumeId) => 'volume:$volumeId';

Vector3 _tileLookAt(VolumeCell cell, VolumeGrid grid) {
  final center = cellFloorCenter(cell, grid);
  return Vector3(center.x, 0, center.z);
}

/// Tile nearest the mean of [tiles]. Ties break by smaller (tx, ty).
(int, int) centermostTile(Iterable<(int, int)> tiles) {
  final list = tiles.toList();
  if (list.isEmpty) {
    throw ArgumentError('centermostTile needs at least one tile');
  }
  var meanX = 0.0;
  var meanY = 0.0;
  for (final tile in list) {
    meanX += tile.$1;
    meanY += tile.$2;
  }
  meanX /= list.length;
  meanY /= list.length;
  list.sort((a, b) {
    final da = _dist2(a.$1 - meanX, a.$2 - meanY);
    final db = _dist2(b.$1 - meanX, b.$2 - meanY);
    final cmp = da.compareTo(db);
    if (cmp != 0) return cmp;
    final tx = a.$1.compareTo(b.$1);
    return tx != 0 ? tx : a.$2.compareTo(b.$2);
  });
  return list.first;
}

/// Best tile to paint a door path onto [volume].
(int, int) doorCandidateTile({
  required Volume volume,
  required VolumeStore volumes,
  required PathStore paths,
}) {
  final exterior = [
    for (final cell in volume.cells)
      if (_hasExteriorSide(volume, cell)) (cell.tx, cell.ty),
  ];
  final pool = exterior.isNotEmpty
      ? exterior
      : [for (final cell in volume.cells) (cell.tx, cell.ty)];
  if (pool.isEmpty) {
    throw ArgumentError('doorCandidateTile needs a cell');
  }

  final paintable = [
    for (final tile in pool)
      if (canPaintPathAt(
        volumes: volumes,
        paths: paths,
        tx: tile.$1,
        ty: tile.$2,
      ))
        tile,
  ];
  if (paintable.isNotEmpty) return centermostTile(paintable);

  if (paths.tiles.isNotEmpty) {
    return _nearestToPaths(pool, paths);
  }
  return centermostTile(pool);
}

bool _hasExteriorSide(Volume volume, VolumeCell cell) {
  for (final side in VolumeSide.values) {
    if (!volume.hasNeighborOn(cell, side.handle)) return true;
  }
  return false;
}

(int, int) _nearestToPaths(List<(int, int)> tiles, PathStore paths) {
  (int, int)? best;
  var bestDist = double.infinity;
  for (final tile in tiles) {
    for (final path in paths.tiles) {
      final d = _dist2(
        (tile.$1 - path.$1).toDouble(),
        (tile.$2 - path.$2).toDouble(),
      );
      if (d < bestDist - 1e-9) {
        best = tile;
        bestDist = d;
        continue;
      }
      if ((d - bestDist).abs() <= 1e-9 &&
          best != null &&
          _tileOrder(tile, best) < 0) {
        best = tile;
      }
    }
  }
  return best ?? tiles.first;
}

int _tileOrder((int, int) a, (int, int) b) {
  final tx = a.$1.compareTo(b.$1);
  return tx != 0 ? tx : a.$2.compareTo(b.$2);
}

double _dist2(double dx, double dy) => dx * dx + dy * dy;
