import 'package:vector_math/vector_math_64.dart';

import '../outlines/outline_edges.dart';
import '../outlines/outline_union.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_regions.dart';
import '../walls/wall_store.dart';
import 'volume.dart';
import 'volume_program.dart';
import 'volume_store.dart';

/// Joined same-program floors (indoor) or one enclosed outdoor region.
class ProgramCluster {
  const ProgramCluster({
    required this.programId,
    required this.tiles,
    required this.edges,
    required this.centroid,
    required this.outdoor,
  });

  final String programId;
  final Set<(int, int)> tiles;
  final List<OutlineEdge> edges;
  final Vector3 centroid;
  final bool outdoor;
}

const _kFloorLift = 0.06;

List<ProgramCluster> indoorProgramClusters({
  required VolumeStore volumes,
  required VolumeProgramStore programs,
  required WallStore walls,
}) {
  final cells = <(int, int), VolumeCell>{};
  final kinds = <(int, int), String>{};
  for (final volume in volumes.visibleVolumes) {
    for (final cell in volume.cells) {
      final id = programs.indoorAt(cell.tx, cell.ty);
      if (id == null) continue;
      final tile = (cell.tx, cell.ty);
      cells[tile] = cell;
      kinds[tile] = id;
    }
  }
  return _floodClusters(
    kinds: kinds,
    walls: walls,
    outdoor: false,
    edgesFor: (tiles, programId) {
      final quads = <OutlineQuad>[
        for (final tile in tiles)
          if (cells[tile] case final cell?)
            _floorQuad(cell, volumes.grid),
      ];
      return collectOuterEdges(unionCoplanarQuads(quads));
    },
    centroidFor: (tiles) => _indoorCentroid(tiles, cells, volumes.grid),
  );
}

List<ProgramCluster> outdoorProgramClusters({
  required Iterable<WallRegion> regions,
  required VolumeProgramStore programs,
  required VolumeGrid grid,
  required WallStore walls,
}) {
  final out = <ProgramCluster>[];
  for (final region in regions) {
    if (region.tiles.isEmpty) continue;
    final programId = programs.outdoorRegionProgram(region.tiles);
    final outline = tileSetOutline(region.tiles);
    final edges = <OutlineEdge>[
      for (final edge in outline) _wallEdgeToOutline(edge, walls),
    ];
    out.add(
      ProgramCluster(
        programId: programId,
        tiles: Set<(int, int)>.from(region.tiles),
        edges: edges,
        centroid: _regionCentroid(region.tiles, grid),
        outdoor: true,
      ),
    );
  }
  return out;
}

Vector3 volumeTopCenter(Volume volume, VolumeGrid grid) {
  var minX = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  var minZ = double.infinity;
  var maxZ = -double.infinity;
  for (final cell in volume.cells) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    if (min.x < minX) minX = min.x;
    if (max.x > maxX) maxX = max.x;
    if (max.y > maxY) maxY = max.y;
    if (min.z < minZ) minZ = min.z;
    if (max.z > maxZ) maxZ = max.z;
  }
  if (minX.isInfinite) return Vector3.zero();
  return Vector3((minX + maxX) * 0.5, maxY + 0.8, (minZ + maxZ) * 0.5);
}

Vector3 regionTopCenter(WallRegion region, VolumeGrid grid) {
  final c = _regionCentroid(region.tiles, grid);
  return Vector3(c.x, 1.2, c.z);
}

Vector3 cellFloorCenter(VolumeCell cell, VolumeGrid grid) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  return Vector3(
    (min.x + max.x) * 0.5,
    min.y + 0.35,
    (min.z + max.z) * 0.5,
  );
}

List<ProgramCluster> _floodClusters({
  required Map<(int, int), String> kinds,
  required WallStore walls,
  required bool outdoor,
  required List<OutlineEdge> Function(Set<(int, int)> tiles, String programId)
      edgesFor,
  required Vector3 Function(Set<(int, int)> tiles) centroidFor,
}) {
  final remaining = Set<(int, int)>.from(kinds.keys);
  final out = <ProgramCluster>[];
  const deltas = [(1, 0), (-1, 0), (0, 1), (0, -1)];
  while (remaining.isNotEmpty) {
    final start = remaining.first;
    final programId = kinds[start]!;
    final tiles = <(int, int)>{};
    final queue = [start];
    remaining.remove(start);
    while (queue.isNotEmpty) {
      final tile = queue.removeLast();
      tiles.add(tile);
      for (final (dx, dy) in deltas) {
        final next = (tile.$1 + dx, tile.$2 + dy);
        if (!remaining.contains(next)) continue;
        if (kinds[next] != programId) continue;
        if (walls.separatesTiles(tile, next)) continue;
        remaining.remove(next);
        queue.add(next);
      }
    }
    out.add(
      ProgramCluster(
        programId: programId,
        tiles: tiles,
        edges: edgesFor(tiles, programId),
        centroid: centroidFor(tiles),
        outdoor: outdoor,
      ),
    );
  }
  return out;
}

OutlineQuad _floorQuad(VolumeCell cell, VolumeGrid grid) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  final y = min.y + _kFloorLift;
  return OutlineQuad(
    points: [
      Vector3(min.x, y, min.z),
      Vector3(max.x, y, min.z),
      Vector3(max.x, y, max.z),
      Vector3(min.x, y, max.z),
    ],
    normal: Vector3(0, 1, 0),
  );
}

Vector3 _indoorCentroid(
  Set<(int, int)> tiles,
  Map<(int, int), VolumeCell> cells,
  VolumeGrid grid,
) {
  final mid = Vector3.zero();
  var n = 0;
  for (final tile in tiles) {
    final cell = cells[tile];
    if (cell == null) continue;
    mid.add(cellFloorCenter(cell, grid));
    n++;
  }
  if (n == 0) return Vector3.zero();
  mid.scale(1 / n);
  return mid;
}

Vector3 _regionCentroid(Set<(int, int)> tiles, VolumeGrid grid) {
  if (tiles.isEmpty) return Vector3.zero();
  final mid = Vector3.zero();
  for (final (tx, ty) in tiles) {
    mid.add(grid.tileCenter(tx, ty));
  }
  mid.scale(1 / tiles.length);
  mid.y = _kFloorLift;
  return mid;
}

OutlineEdge _wallEdgeToOutline(WallEdge edge, WallStore walls) {
  final a = walls.vertexWorld(edge.x0, edge.y0);
  final b = walls.vertexWorld(edge.x1, edge.y1);
  a.y = _kFloorLift;
  b.y = _kFloorLift;
  final mid = (a + b) / 2;
  return OutlineEdge(
    a: a,
    b: b,
    faces: [
      OutlineFace(normal: Vector3(0, 1, 0), center: mid),
    ],
  );
}
