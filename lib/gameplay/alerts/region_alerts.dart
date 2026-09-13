import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../ui/game/game_tool_carousel.dart';
import '../graph/connection_graph.dart';
import '../paths/path_store.dart';
import '../picking/selectable.dart';
import '../volumes/volume.dart';
import '../volumes/volume_door_sync.dart';
import '../volumes/volume_program_clusters.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_regions.dart';
import '../walls/wall_store.dart';
import 'volume_alerts.dart';
import 'world_alert.dart';

/// True when this yard has a cut-fence gate onto an outdoor path tile.
///
/// Uses [ConnectionGraph.anchors] (the same list the overlay draws) so a
/// copied subgraph list or drifted subgraph id cannot keep the alert up
/// after an opening is already on the graph.
bool regionSubgraphConnectedToPath(
  WallRegion region,
  ConnectionGraph graph, {
  WallStore? walls,
  PathStore? paths,
}) {
  for (final anchor in graph.anchors) {
    if (_regionOpeningJoins(anchor, region)) return true;
  }
  if (walls != null && paths != null) {
    for (final _ in ConnectionGraph.regionOutLinks(
      regions: [region],
      walls: walls,
      paths: paths,
    )) {
      return true;
    }
  }
  return false;
}

bool _regionOpeningJoins(GraphAnchor anchor, WallRegion region) {
  if (anchor.kind != GraphAnchorKind.regionOpening) return false;
  final id = ConnectionGraph.regionSubgraphId(region);
  if (anchor.innerSubgraphId == id || anchor.outerSubgraphId == id) {
    return true;
  }
  final innerIn = region.tiles.contains(anchor.innerTile);
  final outerIn = region.tiles.contains(anchor.outerTile);
  return innerIn != outerIn;
}

String regionHostKey(WallRegion region) =>
    'region:${ConnectionGraph.regionSubgraphId(region)}';

/// One sandwich per enclosed yard whose subgraph has no path attachment.
List<WorldAlert> collectRegionAlerts({
  required ConnectionGraph graph,
  required Iterable<WallRegion> regions,
  required VolumeGrid grid,
  required PathStore paths,
  VolumeStore? volumes,
  WallStore? walls,
}) {
  final out = <WorldAlert>[];
  for (final region in regions) {
    final alert = regionAlertFor(
      region: region,
      graph: graph,
      grid: grid,
      paths: paths,
      volumes: volumes,
      walls: walls,
    );
    if (alert != null) out.add(alert);
  }
  return out;
}

WorldAlert? regionAlertFor({
  required WallRegion region,
  required ConnectionGraph graph,
  required VolumeGrid grid,
  required PathStore paths,
  VolumeStore? volumes,
  WallStore? walls,
}) {
  if (region.tiles.isEmpty) return null;
  if (regionSubgraphConnectedToPath(
    region,
    graph,
    walls: walls,
    paths: paths,
  )) {
    return null;
  }
  if (graph.subgraphById(ConnectionGraph.regionSubgraphId(region)) == null) {
    return null;
  }
  final tile = gateCandidateTile(
    region: region,
    paths: paths,
    volumes: volumes,
  );
  final look = grid.tileCenter(tile.$1, tile.$2);
  return WorldAlert(
    id: regionHostKey(region),
    hostKey: regionHostKey(region),
    world: regionTopCenter(region, grid),
    issues: [
      WorldAlertIssue(
        id: '${regionHostKey(region)}:noPath',
        requirementIcon: Icons.add_road,
        remediation: AlertRemediation(
          mode: GameMode.create,
          createTool: GameCreateTool.path,
          lookAt: Vector3(look.x, 0, look.z),
          select: true,
          tx: tile.$1,
          ty: tile.$2,
          selectKind: SelectableKind.region,
        ),
      ),
    ],
  );
}

/// Outdoor tile where a path (or gate click) would attach this region.
(int, int) gateCandidateTile({
  required WallRegion region,
  required PathStore paths,
  VolumeStore? volumes,
}) {
  final outdoor = <(int, int)>{};
  const deltas = [(0, -1), (1, 0), (0, 1), (-1, 0)];
  for (final (tx, ty) in region.tiles) {
    for (final (dx, dy) in deltas) {
      final n = (tx + dx, ty + dy);
      if (region.tiles.contains(n)) continue;
      if (!paths.grid.inBounds(n.$1, n.$2)) continue;
      outdoor.add(n);
    }
  }

  final withPath = [
    for (final tile in outdoor)
      if (paths.contains(tile.$1, tile.$2)) tile,
  ];
  if (withPath.isNotEmpty) return centermostTile(withPath);

  final pool = outdoor.isNotEmpty ? outdoor.toList() : region.tiles.toList();
  if (volumes != null) {
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
    if (paintable.isNotEmpty) {
      if (paths.tiles.isNotEmpty) return _nearestToPaths(paintable, paths);
      return centermostTile(paintable);
    }
  }
  if (paths.tiles.isNotEmpty) return _nearestToPaths(pool, paths);
  return centermostTile(pool);
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
