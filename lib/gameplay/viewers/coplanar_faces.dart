import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume.dart';
import 'world_plane.dart';

/// One volume-cell face that lies on a shared [WorldPlane].
class CoplanarFace {
  const CoplanarFace({
    required this.volumeId,
    required this.cell,
    required this.face,
  });

  final int volumeId;
  final VolumeCell cell;
  final VolumeFace face;
}

/// Every volume face whose plane matches [plane] (same facing and offset).
///
/// Includes neighbors in a joined bar and gapped faces on the same plane,
/// such as the two teeth of a C-shaped mouth.
List<CoplanarFace> collectCoplanarFaces({
  required WorldPlane plane,
  required VolumeGrid grid,
  required Iterable<Volume> volumes,
  double eps = 1e-3,
}) {
  final faces = <CoplanarFace>[];
  for (final volume in volumes) {
    for (final cell in volume.cells) {
      final min = cell.box.worldMin(grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(grid, cell.tx, cell.ty);
      for (final face in VolumeFace.values) {
        final (origin, normal) = face.originAndNormal(min, max);
        if (plane.normal.dot(normal) < 0.99) continue;
        if ((origin - plane.origin).dot(plane.normal).abs() > eps) continue;
        faces.add(
          CoplanarFace(volumeId: volume.id, cell: cell, face: face),
        );
      }
    }
  }
  return faces;
}

/// The coplanar face whose finite quad contains [world], or null in a gap.
CoplanarFace? pickCoplanarFace({
  required Vector3 world,
  required WorldPlane plane,
  required VolumeGrid grid,
  required Iterable<Volume> volumes,
  List<CoplanarFace>? faces,
  double eps = 1e-3,
}) {
  if ((world - plane.origin).dot(plane.normal).abs() > eps) return null;
  final candidates =
      faces ??
      collectCoplanarFaces(
        plane: plane,
        grid: grid,
        volumes: volumes,
        eps: eps,
      );
  for (final face in candidates) {
    final min = face.cell.box.worldMin(grid, face.cell.tx, face.cell.ty);
    final max = face.cell.box.worldMax(grid, face.cell.tx, face.cell.ty);
    if (face.face.containsHit(world, min, max, eps: eps)) return face;
  }
  return null;
}
