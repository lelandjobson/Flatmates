import '../volumes/volume.dart';

/// A tile that currently sheds vision, plus how far it reaches.
class VisionSource {
  const VisionSource({
    required this.tx,
    required this.ty,
    required this.radius,
  });

  final int tx;
  final int ty;

  /// Chebyshev radius in tiles. `0` is the source tile only.
  final int radius;
}

/// Tunable live-vision rules for GameView.
///
/// The starting rectangle is always revealed. Friends and structures only
/// grant vision while they occupy a tile — there is no explored-memory fog.
class MapVisionConfig {
  const MapVisionConfig({
    this.worldTilesSide = defaultWorldTilesSide,
    this.startingTilesSide = defaultStartingTilesSide,
    this.friendViewRadius = defaultFriendViewRadius,
    this.structureViewRadius = defaultStructureViewRadius,
  });

  static const int defaultWorldTilesSide = 48;
  static const int defaultStartingTilesSide = 16;
  static const int defaultFriendViewRadius = 2;
  static const int defaultStructureViewRadius = 5;

  /// Live GameView defaults: 48×48 world, centered 16×16 start.
  static const game = MapVisionConfig();

  final int worldTilesSide;
  final int startingTilesSide;
  final int friendViewRadius;
  final int structureViewRadius;

  /// Halfway tile of the world (48×48 → 24,24). Look-at starts on its center.
  int get centerTx => worldTilesSide ~/ 2;

  int get centerTy => worldTilesSide ~/ 2;

  int get startingOriginTx => (worldTilesSide - startingTilesSide) ~/ 2;

  int get startingOriginTy => (worldTilesSide - startingTilesSide) ~/ 2;

  int get startingMaxTx => startingOriginTx + startingTilesSide - 1;

  int get startingMaxTy => startingOriginTy + startingTilesSide - 1;

  bool inStartingArea(int tx, int ty) =>
      tx >= startingOriginTx &&
      tx <= startingMaxTx &&
      ty >= startingOriginTy &&
      ty <= startingMaxTy;
}

/// Computes the live visible-tile set. Hidden tiles are simply absent.
class MapVision {
  MapVision({this.config = const MapVisionConfig()}) {
    rebuild(grid: VolumeGrid(tilesSide: config.worldTilesSide));
  }

  final MapVisionConfig config;

  Set<(int, int)> _visible = {};

  Set<(int, int)> get visibleTiles => _visible;

  bool isVisible(int tx, int ty) => _visible.contains((tx, ty));

  void rebuild({
    required VolumeGrid grid,
    Iterable<VisionSource> sources = const [],
  }) {
    final next = <(int, int)>{};
    final originTx = config.startingOriginTx;
    final originTy = config.startingOriginTy;
    final startSide = config.startingTilesSide;
    for (var ty = originTy; ty < originTy + startSide; ty++) {
      for (var tx = originTx; tx < originTx + startSide; tx++) {
        if (grid.inBounds(tx, ty)) next.add((tx, ty));
      }
    }
    for (final source in sources) {
      _addChebyshev(next, grid, source.tx, source.ty, source.radius);
    }
    _visible = next;
  }

  static void _addChebyshev(
    Set<(int, int)> into,
    VolumeGrid grid,
    int cx,
    int cy,
    int radius,
  ) {
    final r = radius < 0 ? 0 : radius;
    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        final tx = cx + dx;
        final ty = cy + dy;
        if (grid.inBounds(tx, ty)) into.add((tx, ty));
      }
    }
  }
}
