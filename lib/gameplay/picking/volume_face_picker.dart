import 'package:flutter/painting.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../rendering/scene/camera.dart';
import '../viewers/world_plane.dart';
import '../volumes/volume.dart';
import '../volumes/volume_solid.dart';
import '../volumes/volume_store.dart';

class VolumeFaceHit {
  const VolumeFaceHit({
    required this.volumeId,
    required this.cell,
    required this.face,
    required this.worldPoint,
    required this.t,
  });

  final int volumeId;
  final VolumeCell cell;
  final VolumeFace face;
  final Vector3 worldPoint;
  final double t;
}

/// Closest remaining solid face under a screen ray.
class VolumeFacePicker {
  const VolumeFacePicker();

  VolumeFaceHit? pick({
    required Offset screen,
    required Size viewport,
    required Camera camera,
    required VolumeStore store,
  }) {
    final ray = camera.unprojectRay(screen, viewport);
    if (ray == null) return null;

    VolumeFaceHit? best;
    for (final volume in store.visibleVolumes) {
      final solid = resolveVolumeSolid(volume, store.grid);
      for (final cell in volume.cells) {
        final min = cell.box.worldMin(store.grid, cell.tx, cell.ty);
        final max = cell.box.worldMax(store.grid, cell.tx, cell.ty);
        for (final face in VolumeFace.values) {
          final (origin, normal) = face.originAndNormal(min, max);
          final denom = ray.direction.dot(normal);
          if (denom.abs() < 1e-8) continue;
          final t = (origin - ray.origin).dot(normal) / denom;
          if (t < 1e-4) continue;
          final hit = ray.pointAt(t);
          if (!solid.containsFaceHit(
            cell: cell,
            face: face,
            grid: store.grid,
            world: hit,
          )) {
            continue;
          }
          if (best == null || t < best.t) {
            best = VolumeFaceHit(
              volumeId: volume.id,
              cell: cell,
              face: face,
              worldPoint: hit,
              t: t,
            );
          }
        }
      }
    }
    return best;
  }
}
