import 'package:vector_math/vector_math_64.dart';

import '../outlines/outline_edges.dart';
import '../viewers/world_plane.dart';
import 'volume.dart';
import 'volume_solid.dart';
import 'volume_store.dart';

typedef VolumeOutlineFace = OutlineFace;
typedef VolumeOutlineEdge = OutlineEdge;

/// View-independent outer edges of one joined mass.
class VolumeOutline {
  const VolumeOutline({
    required this.volumeId,
    required this.edges,
  });

  final int volumeId;
  final List<OutlineEdge> edges;
}

/// Cached outlines, rebuilt when volumes are painted, merged, or edited.
class VolumeOutlineStore {
  final Map<int, VolumeOutline> byVolume = {};

  List<VolumeOutline> get items => byVolume.values.toList(growable: false);

  Iterable<OutlineEdge> get edges sync* {
    for (final outline in byVolume.values) {
      yield* outline.edges;
    }
  }

  void rebuild(VolumeStore volumes) {
    final next = <int, VolumeOutline>{};
    for (final volume in volumes.visibleVolumes) {
      next[volume.id] = buildVolumeOutline(volume, volumes.grid);
    }
    byVolume
      ..clear()
      ..addAll(next);
  }
}

/// True when this edge is a silhouette or a crease on a front face.
bool volumeOutlineEdgeVisible(OutlineEdge edge, Vector3 camera) =>
    outlineEdgeVisible(edge, camera);

/// Unique outer edges of [volume]: drop coplanar joins inside a larger face.
VolumeOutline buildVolumeOutline(Volume volume, VolumeGrid grid) {
  final solid = resolveVolumeSolid(volume, grid);
  final quads = <OutlineQuad>[];

  for (final surface in solid.surfaces) {
    final cell = volume.cellAt(surface.tx, surface.ty);
    if (cell == null) continue;
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    final normal = surface.face.worldNormal;
    for (final fragment in surface.fragments) {
      final quad = volumeFaceFragmentQuad(
        min: min,
        max: max,
        handle: surface.handle,
        fragment: fragment,
        subtileSize: grid.subtileSize,
      );
      quads.add(OutlineQuad(points: quad, normal: normal));
    }
  }

  return VolumeOutline(
    volumeId: volume.id,
    edges: collectOuterEdges(quads),
  );
}
