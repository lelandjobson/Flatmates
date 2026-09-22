import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import '../volumes/volume_applique.dart';
import '../volumes/volume_door.dart';
import '../volumes/volume_store.dart';
import 'outline_edges.dart';

/// One drawn applique quad — outer paper, or the inside-face door.
class AppliquePaperQuad {
  const AppliquePaperQuad({
    required this.piece,
    required this.corners,
    required this.face,
    required this.inward,
  });

  final VolumeApplique piece;
  final List<Vector3> corners;
  final VolumeFace face;
  final bool inward;
}

/// Camera-facing applique paper, skipping tiles / faces that are not visible.
///
/// Open interiors also emit an inward door quad so the opening reads from
/// inside remaining walls. Cutaway faces (same as walls) emit nothing.
List<AppliquePaperQuad> visibleAppliquePapers({
  required Iterable<VolumeApplique> appliques,
  required VolumeStore volumes,
  required Vector3 camera,
  bool Function(int tx, int ty)? tileVisible,
  bool Function(int tx, int ty, VolumeFace face)? faceHidden,
  bool Function(int tx, int ty)? interiorRevealed,
}) {
  final papers = <AppliquePaperQuad>[];
  for (final piece in appliques) {
    if (tileVisible != null && !tileVisible(piece.tx, piece.ty)) continue;
    if (faceHidden != null && faceHidden(piece.tx, piece.ty, piece.face)) {
      continue;
    }
    final volume = volumes.volumeById(piece.volumeId);
    final cell = volume?.cellAt(piece.tx, piece.ty);
    if (volume == null || cell == null) continue;

    final exterior = appliqueWorldCorners(
      grid: volumes.grid,
      cell: cell,
      piece: piece,
    );
    if (doorFacesCamera(
      face: piece.face,
      corners: exterior,
      cameraPosition: camera,
    )) {
      papers.add(
        AppliquePaperQuad(
          piece: piece,
          corners: exterior,
          face: piece.face,
          inward: false,
        ),
      );
    }

    final revealed = interiorRevealed?.call(piece.tx, piece.ty) ?? false;
    if (!revealed || piece.kind != VolumeAppliqueKind.door) continue;
    final interior = appliqueWorldCorners(
      grid: volumes.grid,
      cell: cell,
      piece: piece,
      inward: true,
    );
    final inwardFace = piece.face.opposite;
    if (doorFacesCamera(
      face: inwardFace,
      corners: interior,
      cameraPosition: camera,
    )) {
      papers.add(
        AppliquePaperQuad(
          piece: piece,
          corners: interior,
          face: inwardFace,
          inward: true,
        ),
      );
    }
  }
  return papers;
}

/// Camera-facing applique paper, skipping tiles / faces that are not visible.
List<OutlineQuad> visibleAppliqueQuads({
  required Iterable<VolumeApplique> appliques,
  required VolumeStore volumes,
  required Vector3 camera,
  bool Function(int tx, int ty)? tileVisible,
  bool Function(int tx, int ty, VolumeFace face)? faceHidden,
  bool Function(int tx, int ty)? interiorRevealed,
}) {
  return [
    for (final paper in visibleAppliquePapers(
      appliques: appliques,
      volumes: volumes,
      camera: camera,
      tileVisible: tileVisible,
      faceHidden: faceHidden,
      interiorRevealed: interiorRevealed,
    ))
      OutlineQuad(points: paper.corners, normal: paper.face.worldNormal),
  ];
}

/// Outer edges of visible applique paper. Empty when nothing faces the camera.
List<OutlineEdge> buildAppliqueOutline({
  required Iterable<VolumeApplique> appliques,
  required VolumeStore volumes,
  required Vector3 camera,
  bool Function(int tx, int ty)? tileVisible,
  bool Function(int tx, int ty, VolumeFace face)? faceHidden,
  bool Function(int tx, int ty)? interiorRevealed,
}) {
  final quads = visibleAppliqueQuads(
    appliques: appliques,
    volumes: volumes,
    camera: camera,
    tileVisible: tileVisible,
    faceHidden: faceHidden,
    interiorRevealed: interiorRevealed,
  );
  if (quads.isEmpty) return const [];
  return collectOuterEdges(quads);
}
