/// What the map eraser is allowed to delete.
class EraserFilter {
  EraserFilter({
    this.walls = true,
    this.paths = true,
    this.volumes = true,
    this.radiusTiles = 0.85,
  });

  bool walls;
  bool paths;
  bool volumes;

  /// Brush radius in tile units. World radius is this times [tileSize].
  double radiusTiles;

  static const double minRadiusTiles = 0.25;
  static const double maxRadiusTiles = 3.0;

  double worldRadius(double tileSize) => radiusTiles * tileSize;

  EraserFilter copy() => EraserFilter(
        walls: walls,
        paths: paths,
        volumes: volumes,
        radiusTiles: radiusTiles,
      );
}
