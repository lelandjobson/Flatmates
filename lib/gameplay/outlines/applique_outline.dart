import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import '../volumes/volume_applique.dart';
import '../volumes/volume_door.dart';
import '../volumes/volume_store.dart';
import 'outline_edges.dart';

/// Camera-facing applique paper, skipping tiles / faces that are not visible.
List<OutlineQuad> visibleAppliqueQuads({
  required Iterable<VolumeApplique> appliques,
  required VolumeStore volumes,
  required Vector3 camera,
  bool Function(int tx, int ty)? tileVisible,
}) {
  final quads = <OutlineQuad>[];
  for (final piece in appliques) {
    if (tileVisible != null && !tileVisible(piece.tx, piece.ty)) continue;
    final volume = volumes.volumeById(piece.volumeId);
    final cell = volume?.cellAt(piece.tx, piece.ty);
    if (volume == null || cell == null) continue;
    final corners = appliqueWorldCorners(
      grid: volumes.grid,
      cell: cell,
      piece: piece,
    );
    if (!doorFacesCamera(
      face: piece.face,
      corners: corners,
      cameraPosition: camera,
    )) {
      continue;
    }
    quads.add(OutlineQuad(points: corners, normal: piece.face.worldNormal));
  }
  return quads;
}

/// Outer edges of visible applique paper. Empty when nothing faces the camera.
List<OutlineEdge> buildAppliqueOutline({
  required Iterable<VolumeApplique> appliques,
  required VolumeStore volumes,
  required Vector3 camera,
  bool Function(int tx, int ty)? tileVisible,
}) {
  final quads = visibleAppliqueQuads(
    appliques: appliques,
    volumes: volumes,
    camera: camera,
    tileVisible: tileVisible,
  );
  if (quads.isEmpty) return const [];
  return collectOuterEdges(quads);
}
