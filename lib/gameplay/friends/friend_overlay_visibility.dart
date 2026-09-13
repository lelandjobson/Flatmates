import 'package:vector_math/vector_math_64.dart';

import '../volumes/volume_store.dart';

/// Indoor friends skip 2D overlays so eyes/outlines do not punch through a
/// closed roof. Once [interiorOpen] says that tile is open, draw them.
bool hideFriendOverlay({
  required Vector3 position,
  VolumeStore? volumes,
  bool Function(int tx, int ty)? interiorOpen,
}) {
  if (volumes == null) return false;
  if (!volumes.containsWorld(position)) return false;
  if (interiorOpen == null) return true;
  final tile = volumes.grid.tileAtWorld(position);
  if (tile == null) return true;
  return !interiorOpen(tile.$1, tile.$2);
}
