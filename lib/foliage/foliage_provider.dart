import 'dart:ui' show Color;

typedef FoliageId = String;

/// Default number of times a foliage instance can be gathered before removal.
const int kDefaultFoliageGathers = 3;

/// A single foliage object placed in the world (e.g. a tree).
///
/// Position is expressed as an integer tile coordinate plus UV offsets (0..1)
/// within that tile, enabling fast tile-based retrieval and facing-angle
/// calculations.
class FoliageInstance {
  FoliageInstance({
    required this.id,
    required this.typeId,
    required this.materialId,
    required this.tileX,
    required this.tileY,
    this.u = 0.5,
    this.v = 0.5,
    this.remainingGathers = kDefaultFoliageGathers,
    this.maxGathers = kDefaultFoliageGathers,
    this.scale = 1.0,
    this.facingAngleDeg = 0.0,
    this.tint,
  });

  final FoliageId id;

  /// Asset type used for rendering (e.g. `type_tree`).
  final String typeId;

  /// Material yielded when gathered (e.g. `fm-logs`).
  final String materialId;

  /// Integer tile coordinate.
  final int tileX;
  final int tileY;

  /// Relative position within the tile (0..1).  (0,0) and (1,1) are opposite
  /// corners.  Used for rendering offsets and facing-angle calculation.
  final double u;
  final double v;

  /// Fractional world position derived from tile + UV.
  /// Integer coordinates are tile centres, so UV [0,1] maps to offset [-0.5, +0.5].
  double get worldX => tileX + u - 0.5;
  double get worldY => tileY + v - 0.5;

  /// How many more gather actions this instance can sustain.
  int remainingGathers;

  /// Initial gather count (used for appearance calculations).
  final int maxGathers;

  /// Visual parameters (deterministically randomised at creation).
  final double scale;
  final double facingAngleDeg;
  final Color? tint;

  /// Whether the instance has been fully depleted.
  bool get isDepleted => remainingGathers <= 0;

  /// Normalized depletion ratio (1.0 = full, 0.0 = depleted).
  double get depletionRatio =>
      maxGathers > 0 ? remainingGathers / maxGathers : 0.0;

  /// Scale multiplier that shrinks as gathers are consumed.
  double get appearanceScale {
    if (maxGathers <= 0) return 1.0;
    return 0.4 + 0.6 * depletionRatio;
  }

  String get _tileKey => '$tileX:$tileY';
}

/// Spatial database for foliage instances.
///
/// Uses a tile-key index (`"tileX:tileY"`) for fast per-tile retrieval and a
/// coarser grid-cell index for range queries.
class FoliageProvider {
  FoliageProvider({this.gridSize = 10});

  final int gridSize;

  final Map<FoliageId, FoliageInstance> _foliage = {};

  /// Tile-level index: `"tileX:tileY"` -> set of IDs on that tile.
  final Map<String, Set<FoliageId>> _tileIndex = {};

  /// Coarse grid-cell index for range queries.
  final Map<String, Set<FoliageId>> _spatialIndex = {};

  int _nextId = 0;

  int get count => _foliage.length;

  String _cellKey(int cellX, int cellY) => '$cellX:$cellY';

  String _cellKeyForInstance(FoliageInstance f) {
    return _cellKey(f.tileX ~/ gridSize, f.tileY ~/ gridSize);
  }

  /// Add a foliage instance. Returns its ID.
  FoliageId addFoliage(FoliageInstance instance) {
    _foliage[instance.id] = instance;
    _tileIndex.putIfAbsent(instance._tileKey, () => {}).add(instance.id);
    final cell = _cellKeyForInstance(instance);
    _spatialIndex.putIfAbsent(cell, () => {}).add(instance.id);
    return instance.id;
  }

  /// Convenience method to add foliage and auto-generate an ID.
  FoliageId addNew({
    required String typeId,
    required String materialId,
    required int tileX,
    required int tileY,
    double u = 0.5,
    double v = 0.5,
    int remainingGathers = kDefaultFoliageGathers,
    double scale = 1.0,
    double facingAngleDeg = 0.0,
    Color? tint,
  }) {
    final id = 'foliage_${_nextId++}';
    final instance = FoliageInstance(
      id: id,
      typeId: typeId,
      materialId: materialId,
      tileX: tileX,
      tileY: tileY,
      u: u,
      v: v,
      remainingGathers: remainingGathers,
      maxGathers: remainingGathers,
      scale: scale,
      facingAngleDeg: facingAngleDeg,
      tint: tint,
    );
    return addFoliage(instance);
  }

  /// Remove a foliage instance by ID.
  bool removeFoliage(FoliageId id) {
    final instance = _foliage.remove(id);
    if (instance == null) return false;
    _tileIndex[instance._tileKey]?.remove(id);
    if (_tileIndex[instance._tileKey]?.isEmpty ?? false) {
      _tileIndex.remove(instance._tileKey);
    }
    final cell = _cellKeyForInstance(instance);
    _spatialIndex[cell]?.remove(id);
    if (_spatialIndex[cell]?.isEmpty ?? false) _spatialIndex.remove(cell);
    return true;
  }

  /// Deplete one gather from a foliage instance.
  /// Returns `true` if the instance was removed (fully depleted).
  bool depleteGather(FoliageId id) {
    final instance = _foliage[id];
    if (instance == null) return false;
    instance.remainingGathers--;
    if (instance.isDepleted) {
      removeFoliage(id);
      return true;
    }
    return false;
  }

  /// Look up a foliage instance by ID.
  FoliageInstance? getById(FoliageId id) => _foliage[id];

  /// Get all foliage on a specific tile (O(1) lookup via tile index).
  List<FoliageInstance> getAtTile(int tileX, int tileY) {
    final key = '$tileX:$tileY';
    final ids = _tileIndex[key];
    if (ids == null) return const [];
    return ids
        .map((id) => _foliage[id])
        .whereType<FoliageInstance>()
        .toList();
  }

  /// Query all foliage within an axis-aligned rectangle (tile coordinates).
  List<FoliageInstance> queryRange({
    required int minX,
    required int maxX,
    required int minY,
    required int maxY,
  }) {
    final results = <FoliageInstance>[];
    final seen = <FoliageId>{};

    final minCellX = minX ~/ gridSize;
    final maxCellX = maxX ~/ gridSize;
    final minCellY = minY ~/ gridSize;
    final maxCellY = maxY ~/ gridSize;

    for (var cx = minCellX; cx <= maxCellX; cx++) {
      for (var cy = minCellY; cy <= maxCellY; cy++) {
        final ids = _spatialIndex[_cellKey(cx, cy)];
        if (ids == null) continue;
        for (final id in ids) {
          if (seen.contains(id)) continue;
          final f = _foliage[id];
          if (f == null) continue;
          if (f.tileX >= minX &&
              f.tileX <= maxX &&
              f.tileY >= minY &&
              f.tileY <= maxY) {
            results.add(f);
            seen.add(id);
          }
        }
      }
    }

    return results;
  }

  /// Find the nearest foliage instance within [radius] of world (x, y).
  FoliageInstance? getNearestAt(double x, double y, {double radius = 0.6}) {
    final radiusSq = radius * radius;
    FoliageInstance? best;
    double bestDistSq = double.infinity;

    final candidates = queryRange(
      minX: (x - radius).floor(),
      maxX: (x + radius).ceil(),
      minY: (y - radius).floor(),
      maxY: (y + radius).ceil(),
    );

    for (final f in candidates) {
      final dx = f.worldX - x;
      final dy = f.worldY - y;
      final distSq = dx * dx + dy * dy;
      if (distSq <= radiusSq && distSq < bestDistSq) {
        bestDistSq = distSq;
        best = f;
      }
    }

    return best;
  }

  /// Clear all foliage.
  void clear() {
    _foliage.clear();
    _tileIndex.clear();
    _spatialIndex.clear();
    _nextId = 0;
  }
}
