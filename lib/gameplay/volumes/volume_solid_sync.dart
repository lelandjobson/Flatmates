import '../paint/face_paint_store.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_store.dart';
import 'volume_outline.dart';
import 'volume_program.dart';
import 'volume_solid.dart';
import 'volume_store.dart';

/// Re-resolve every mass, drop swallowed doors / paint / plans, and strip
/// walls that now sit between two cells of the same volume.
void syncVolumeSurfaces({
  required VolumeStore volumes,
  required FacePaintStore paint,
  required VolumeProgramStore programs,
  VolumeOutlineStore? outlines,
}) {
  for (final volume in volumes.visibleVolumes) {
    final solid = resolveVolumeSolid(volume, volumes.grid);
    clearInternalDoors(volume, solid);
  }
  paint.prune(volumes);
  programs.prune(volumes);
  outlines?.rebuild(volumes);
}

/// Delete wall edges whose two tiles belong to the same volume mass.
int stripSharedVolumeWalls(WallStore walls, VolumeStore volumes) {
  final doomed = <WallEdge>[];
  for (final edge in walls.edges) {
    final tiles = edge.separatedTiles;
    if (tiles == null) continue;
    final a = volumes.volumeAt(tiles.$1.$1, tiles.$1.$2);
    final b = volumes.volumeAt(tiles.$2.$1, tiles.$2.$2);
    if (a == null || b == null || a.id != b.id) continue;
    doomed.add(edge);
  }
  for (final edge in doomed) {
    walls.remove(edge);
  }
  return doomed.length;
}

/// What the volume-interior viewer draws for a resolved solid.
class VolumeInteriorViewSpec {
  const VolumeInteriorViewSpec({
    required this.hideRoof,
    required this.hideOutwardFaces,
  });

  final bool hideRoof;
  final bool hideOutwardFaces;
}

VolumeInteriorViewSpec volumeInteriorViewSpec({required bool showExterior}) {
  return VolumeInteriorViewSpec(
    hideRoof: true,
    hideOutwardFaces: !showExterior,
  );
}
