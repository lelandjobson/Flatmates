/// Locked basement entrance at the world origin. Datum 0, special-case geometry.
///
/// Column X=0, descending −Z: locked path at (0,2), punched ramp on (0,1)/(0,0),
/// then the slope continues under ordinary landscape at (0,-1)/(0,-2).
class BasementSpawn {
  const BasementSpawn._();

  static const int datum = 0;

  static const (int, int) pathTile = (0, 2);
  static const (int, int) spawnTile = (0, -2);

  /// South face is the shared edge of (0,0) and (0,-1).
  static const (int, int) doorTile = (0, -1);

  static const List<(int, int)> rampTiles = [
    (0, 1),
    (0, 0),
    (0, -1),
    (0, -2),
  ];

  static const Set<(int, int)> rampTileSet = {
    (0, 1),
    (0, 0),
    (0, -1),
    (0, -2),
  };

  /// Landscape tiles removed for the visible hole. Bridged tiles stay on the plane.
  static const List<(int, int)> cutTiles = [
    (0, 1),
    (0, 0),
  ];

  static const Set<(int, int)> cutTileSet = {
    (0, 1),
    (0, 0),
  };

  static const List<(int, int)> hiddenTiles = [
    (0, -1),
    (0, -2),
  ];

  static bool isCutTile(int tx, int ty) => cutTileSet.contains((tx, ty));

  static bool isHiddenTile(int tx, int ty) => hiddenTiles.contains((tx, ty));

  static bool isLockedPath(int tx, int ty) => tx == pathTile.$1 && ty == pathTile.$2;

  /// Flatmates cannot walk the open ramp. Bridged tiles are ordinary ground.
  static bool blocksWalk(int tx, int ty) => isCutTile(tx, ty);

  /// Volumes, walls, and erasers cannot occupy the cut or the locked path.
  static bool blocksBuild(int tx, int ty) => isCutTile(tx, ty) || isLockedPath(tx, ty);

  /// Hole and locked path are not selectable or erasable.
  static bool blocksSelect(int tx, int ty) => isCutTile(tx, ty) || isLockedPath(tx, ty);
}
