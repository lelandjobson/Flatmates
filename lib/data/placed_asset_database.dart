import 'dart:async';
import '../gameplay/inventory.dart';
import '../rendering/iso/iso_coordinate.dart';

/// Unique identifier for a placed asset instance
typedef PlacedAssetId = String;

/// Unique identifier for an asset type (all houses share the same UUID)
typedef AssetTypeId = String;

/// A placed asset entry with position and type reference
/// Does NOT contain the actual asset data - only position and metadata
class PlacedAssetEntry {
  PlacedAssetEntry({
    required this.id,
    required this.typeId,
    required this.coordinate,
    this.viewRadius = 1,
    this.metadata = const {},
  });

  /// Unique ID for this placed instance
  final PlacedAssetId id;

  /// Type identifier (UUID) - all assets of same type share this
  final AssetTypeId typeId;

  /// World position
  final IsoCoordinate coordinate;

  /// View/visibility radius in tiles (how far this asset can see)
  final int viewRadius;

  /// Game-specific metadata (owner, health, state, etc.)
  final Map<String, dynamic> metadata;
}

/// Spatial database for placed assets
///
/// Stores WHERE assets are placed, not WHAT they look like.
/// Returns placed asset entries with typeId references.
class PlacedAssetDatabase {
  PlacedAssetDatabase({this.gridSize = 10});

  /// Size of spatial grid cells
  final int gridSize;

  /// Main storage: placed asset ID → entry
  final Map<PlacedAssetId, PlacedAssetEntry> _placedAssets = {};

  /// Spatial index: grid cell key → set of placed asset IDs
  final Map<String, Set<PlacedAssetId>> _spatialIndex = {};

  /// Structure inventories: placed asset ID → inventory
  /// Only structures have inventories (large capacity)
  final Map<PlacedAssetId, Inventory> _structureInventories = {};

  /// Counter for generating unique IDs
  int _nextId = 0;

  /// Get the number of placed assets
  int get count => _placedAssets.length;

  /// Get all placed asset IDs
  Iterable<PlacedAssetId> get placedAssetIds => _placedAssets.keys;

  /// Generate a grid cell key for a coordinate
  String _getCellKey(int x, int y) {
    final cellX = x ~/ gridSize;
    final cellY = y ~/ gridSize;
    return '$cellX:$cellY';
  }

  /// Place an asset in the world
  /// Returns the generated placed asset ID
  Future<PlacedAssetId> placeAsset({
    required AssetTypeId typeId,
    required IsoCoordinate coordinate,
    PlacedAssetId? id,
    int viewRadius = 1,
    Map<String, dynamic> metadata = const {},
  }) async {
    await Future.delayed(Duration.zero);

    final placedId = id ?? 'placed_${_nextId++}';
    final entry = PlacedAssetEntry(
      id: placedId,
      typeId: typeId,
      coordinate: coordinate,
      viewRadius: viewRadius,
      metadata: metadata,
    );

    // Add to main storage
    _placedAssets[placedId] = entry;

    // Add to spatial index
    final cellKey = _getCellKey(coordinate.x, coordinate.y);
    _spatialIndex.putIfAbsent(cellKey, () => {}).add(placedId);

    return placedId;
  }

  /// Remove a placed asset
  Future<bool> removeAsset(PlacedAssetId id) async {
    await Future.delayed(Duration.zero);

    final entry = _placedAssets.remove(id);
    if (entry == null) {
      return false;
    }

    // Remove from spatial index
    final cellKey = _getCellKey(entry.coordinate.x, entry.coordinate.y);
    _spatialIndex[cellKey]?.remove(id);
    if (_spatialIndex[cellKey]?.isEmpty ?? false) {
      _spatialIndex.remove(cellKey);
    }

    // Remove structure inventory if exists
    _structureInventories.remove(id);

    return true;
  }

  /// Update a placed asset's position
  Future<bool> updatePosition(
    PlacedAssetId id,
    IsoCoordinate newCoordinate, {
    int? viewRadius,
    Map<String, dynamic>? metadata,
  }) async {
    await Future.delayed(Duration.zero);

    final entry = _placedAssets[id];
    if (entry == null) {
      return false;
    }

    final oldCoord = entry.coordinate;
    final oldCellKey = _getCellKey(oldCoord.x, oldCoord.y);
    final newCellKey = _getCellKey(newCoordinate.x, newCoordinate.y);

    // Only update spatial index if cell changed
    if (oldCellKey != newCellKey) {
      _spatialIndex[oldCellKey]?.remove(id);
      if (_spatialIndex[oldCellKey]?.isEmpty ?? false) {
        _spatialIndex.remove(oldCellKey);
      }
      _spatialIndex.putIfAbsent(newCellKey, () => {}).add(id);
    }

    // Update entry
    _placedAssets[id] = PlacedAssetEntry(
      id: id,
      typeId: entry.typeId,
      coordinate: newCoordinate,
      viewRadius: viewRadius ?? entry.viewRadius,
      metadata: metadata ?? entry.metadata,
    );

    return true;
  }

  /// Get a placed asset by ID
  PlacedAssetEntry? getAsset(PlacedAssetId id) {
    return _placedAssets[id];
  }

  /// Get a specific placed asset by ID
  Future<PlacedAssetEntry?> getPlacedAsset(PlacedAssetId id) async {
    await Future.delayed(Duration.zero);
    return _placedAssets[id];
  }

  // ===== Structure Inventory Management =====

  /// Get or create an inventory for a structure
  Inventory getStructureInventory(PlacedAssetId structureId) {
    return _structureInventories.putIfAbsent(
      structureId,
      () => Inventory.forStructure(),
    );
  }

  /// Check if a structure has an inventory
  bool hasStructureInventory(PlacedAssetId structureId) {
    return _structureInventories.containsKey(structureId);
  }

  /// Get structure inventory if it exists (doesn't create one)
  Inventory? getStructureInventoryIfExists(PlacedAssetId structureId) {
    return _structureInventories[structureId];
  }

  /// Clear a structure's inventory
  void clearStructureInventory(PlacedAssetId structureId) {
    _structureInventories[structureId]?.clear();
  }

  /// Remove a structure's inventory entirely
  void removeStructureInventory(PlacedAssetId structureId) {
    _structureInventories.remove(structureId);
  }

  /// Get all structure inventories (for debug display)
  Map<PlacedAssetId, Inventory> get allStructureInventories =>
      Map.unmodifiable(_structureInventories);

  /// Get all placed assets at a specific coordinate
  Future<List<PlacedAssetEntry>> getPlacedAssetsAtCoordinate(
    int x,
    int y,
  ) async {
    await Future.delayed(Duration.zero);

    final cellKey = _getCellKey(x, y);
    final placedIds = _spatialIndex[cellKey];
    if (placedIds == null) {
      return [];
    }

    return placedIds
        .map((id) => _placedAssets[id])
        .whereType<PlacedAssetEntry>()
        .where((entry) => entry.coordinate.x == x && entry.coordinate.y == y)
        .toList();
  }

  /// Query placed assets within a rectangular range
  /// Primary query method for rendering visible assets
  Future<List<PlacedAssetEntry>> queryRange({
    required int minX,
    required int maxX,
    required int minY,
    required int maxY,
  }) async {
    await Future.delayed(Duration.zero);

    final results = <PlacedAssetEntry>[];
    final seenIds = <PlacedAssetId>{};

    // Calculate grid cells that overlap with the query range
    final minCellX = minX ~/ gridSize;
    final maxCellX = maxX ~/ gridSize;
    final minCellY = minY ~/ gridSize;
    final maxCellY = maxY ~/ gridSize;

    // Iterate through all cells in range
    for (var cellX = minCellX; cellX <= maxCellX; cellX++) {
      for (var cellY = minCellY; cellY <= maxCellY; cellY++) {
        final cellKey = '$cellX:$cellY';
        final placedIds = _spatialIndex[cellKey];
        if (placedIds == null) {
          continue;
        }

        for (final id in placedIds) {
          if (seenIds.contains(id)) {
            continue;
          }

          final entry = _placedAssets[id];
          if (entry == null) {
            continue;
          }

          // Filter to exact range
          final coord = entry.coordinate;
          if (coord.x >= minX &&
              coord.x <= maxX &&
              coord.y >= minY &&
              coord.y <= maxY) {
            results.add(entry);
            seenIds.add(id);
          }
        }
      }
    }

    return results;
  }

  /// Query placed assets within a radius
  Future<List<PlacedAssetEntry>> queryRadius({
    required int centerX,
    required int centerY,
    required int radius,
  }) async {
    final entries = await queryRange(
      minX: centerX - radius,
      maxX: centerX + radius,
      minY: centerY - radius,
      maxY: centerY + radius,
    );

    return entries.where((entry) {
      final dx = entry.coordinate.x - centerX;
      final dy = entry.coordinate.y - centerY;
      return (dx * dx + dy * dy) <= (radius * radius);
    }).toList();
  }

  /// Get all placed assets
  Future<List<PlacedAssetEntry>> getAllPlacedAssets() async {
    await Future.delayed(Duration.zero);
    return _placedAssets.values.toList();
  }

  /// Clear all placed assets
  Future<void> clear() async {
    await Future.delayed(Duration.zero);
    _placedAssets.clear();
    _spatialIndex.clear();
    _structureInventories.clear();
    _nextId = 0;
  }

  /// Get database statistics
  PlacedAssetDbStats get stats {
    return PlacedAssetDbStats(
      totalPlaced: _placedAssets.length,
      gridCells: _spatialIndex.length,
      averagePerCell: _spatialIndex.isEmpty
          ? 0.0
          : _placedAssets.length / _spatialIndex.length,
    );
  }
}

/// Database statistics
class PlacedAssetDbStats {
  const PlacedAssetDbStats({
    required this.totalPlaced,
    required this.gridCells,
    required this.averagePerCell,
  });

  final int totalPlaced;
  final int gridCells;
  final double averagePerCell;

  @override
  String toString() =>
      'PlacedAssetDbStats(placed: $totalPlaced, cells: $gridCells, avg: ${averagePerCell.toStringAsFixed(1)})';
}
