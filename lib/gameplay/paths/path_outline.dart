import 'package:vector_math/vector_math_64.dart';

import '../outlines/outline_edges.dart';
import '../spawns/basement_spawn.dart';
import '../spawns/basement_spawn_mesh.dart';
import '../volumes/volume_store.dart';
import 'path_mesh.dart';
import 'path_shape.dart';
import 'path_store.dart';

/// Cached outer edges of joined path footprints, rebuilt on path edits.
class PathOutlineStore {
  List<OutlineEdge> edges = const [];

  void rebuild({
    required PathStore paths,
    required VolumeStore volumes,
  }) {
    edges = buildPathOutline(paths: paths, volumes: volumes);
  }
}

/// Unique outer edges of the path paper: drop coplanar joins between pieces.
List<OutlineEdge> buildPathOutline({
  required PathStore paths,
  required VolumeStore volumes,
}) {
  final grid = paths.grid;
  final s = grid.subtileSize;
  final y = kPathHeight;
  final up = Vector3(0, 1, 0);
  final quads = <OutlineQuad>[];
  final byTile = pathFootprintsByTile(volumes: volumes, paths: paths);
  for (final entry in byTile.entries) {
    final origin = grid.tileOrigin(entry.key.$1, entry.key.$2);
    for (final piece in entry.value) {
      final minX = origin.x + piece.originXSubtiles * s;
      final maxX = origin.x + (piece.originXSubtiles + piece.widthSubtiles) * s;
      final minZ = origin.z + piece.originZSubtiles * s;
      final maxZ = origin.z + (piece.originZSubtiles + piece.depthSubtiles) * s;
      quads.add(
        OutlineQuad(
          points: [
            Vector3(minX, y, minZ),
            Vector3(maxX, y, minZ),
            Vector3(maxX, y, maxZ),
            Vector3(minX, y, maxZ),
          ],
          normal: up,
        ),
      );
    }
  }
  if (paths.contains(BasementSpawn.pathTile.$1, BasementSpawn.pathTile.$2)) {
    quads.addAll(basementRampPathOutlineQuads(grid));
  }
  return collectOuterEdges(quads, keepCreases: false);
}
