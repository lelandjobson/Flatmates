/// What the map eraser is allowed to delete.
class EraserFilter {
  EraserFilter({
    this.eraseAllOnTile = true,
    this.walls = true,
    this.paths = true,
    this.volumes = true,
    this.radiusTiles = 0.85,
  });

  /// When true, a click clears every enabled kind on that tile.
  bool eraseAllOnTile;

  bool walls;
  bool paths;
  bool volumes;

  /// Brush radius in tile units. World radius is this times [tileSize].
  double radiusTiles;

  static const double minRadiusTiles = 0.25;
  static const double maxRadiusTiles = 3.0;

  double worldRadius(double tileSize) => radiusTiles * tileSize;

  EraserFilter copy() => EraserFilter(
        eraseAllOnTile: eraseAllOnTile,
        walls: walls,
        paths: paths,
        volumes: volumes,
        radiusTiles: radiusTiles,
      );
}
