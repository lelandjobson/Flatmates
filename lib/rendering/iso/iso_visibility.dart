import 'iso_asset.dart';
import 'iso_painter.dart';

/// Visibility state for a tile
enum TileVisibility {
  /// Tile has never been seen or explored
  hidden,

  /// Tile is in fog-of-war:
  /// - Adjacent to currently visible tiles (creates glow border), OR
  /// - Was previously visible but asset moved away (historical exploration)
  fog,

  /// Tile is currently visible (within view radius of at least one asset)
  visible,
}

/// Manages tile visibility based on asset positions
class IsoVisibilityManager {
  IsoVisibilityManager({this.defaultViewRadius = 1});

  /// Default view radius for assets without specific radius
  final int defaultViewRadius;

  /// Map of tile coordinates to their visibility state
  /// Only stores tiles that are fog or visible (hidden is implicit)
  final Map<String, TileVisibility> _visibilityCache = {};

  /// Calculate visibility for all tiles based on current asset positions and paths
  /// Returns a map of tile coordinate keys to visibility states
  ///
  /// Fog-of-war rules:
  /// 1. Tiles within asset view radius are VISIBLE
  /// 2. Tiles with paths on them are VISIBLE (no fog border)
  /// 3. Tiles adjacent to asset-visible tiles are FOG (creates glow effect)
  /// 4. Previously visible tiles that are no longer in range become FOG
  /// 5. All other tiles are HIDDEN
  ///
  /// Optimized to:
  /// - Only iterate through assets once
  /// - Use hash sets for O(1) lookups
  /// - Preserve historical fog state
  Map<String, TileVisibility> calculateVisibility(
    List<IsoAssetInstance> assets,
    List<IsoTileData> tiles, {
    List<dynamic>? paths,
  }) {
    // Calculate currently visible tiles from assets
    final visibleTiles = <String>{};
    final assetVisibleTiles = <String>{}; // Track tiles visible by assets only

    for (final asset in assets) {
      // Get view radius from asset instance
      final radius = asset.viewRadius;

      // Mark all tiles within radius as visible
      final coord = asset.coordinate;
      for (var dx = -radius; dx <= radius; dx++) {
        for (var dy = -radius; dy <= radius; dy++) {
          final tileX = coord.x + dx;
          final tileY = coord.y + dy;
          final key = _getTileKey(tileX, tileY);
          visibleTiles.add(key);
          assetVisibleTiles.add(key); // Track for fog calculation
        }
      }
    }

    // Add path tiles as visible (no fog border around them)
    if (paths != null) {
      for (final path in paths) {
        final coordinates = path.coordinates as List;
        for (final coord in coordinates) {
          final key = _getTileKey(coord.x as int, coord.y as int);
          visibleTiles.add(key);
        }
      }
    }

    // Calculate fog tiles (tiles adjacent to asset-visible tiles ONLY)
    // This creates a 1-tile border around asset-illuminated areas
    // Path tiles do NOT create fog borders
    final fogTiles = <String>{};

    for (final visibleKey in assetVisibleTiles) {
      final parts = visibleKey.split(':');
      final x = int.parse(parts[0]);
      final y = int.parse(parts[1]);

      // Add all 8 immediate neighbors to fog
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          if (dx == 0 && dy == 0) {
            continue; // Skip center
          }

          final neighborKey = _getTileKey(x + dx, y + dy);
          // Only add to fog if not already visible
          if (!visibleTiles.contains(neighborKey)) {
            fogTiles.add(neighborKey);
          }
        }
      }
    }

    // Build new visibility map
    final newVisibility = <String, TileVisibility>{};

    // Add visible tiles
    for (final key in visibleTiles) {
      newVisibility[key] = TileVisibility.visible;
    }

    // Add fog tiles (both new fog and historical fog)
    for (final key in fogTiles) {
      newVisibility[key] = TileVisibility.fog;
    }

    // Preserve historical fog (tiles that were visible before but no longer)
    for (final entry in _visibilityCache.entries) {
      final key = entry.key;
      // If tile was visible/fog before but not visible now, mark as fog
      if (!newVisibility.containsKey(key) &&
          (entry.value == TileVisibility.visible ||
              entry.value == TileVisibility.fog)) {
        newVisibility[key] = TileVisibility.fog;
      }
    }

    // Update cache
    _visibilityCache.clear();
    _visibilityCache.addAll(newVisibility);

    return newVisibility;
  }

  /// Get visibility state for a specific tile
  /// Returns hidden if not in cache
  TileVisibility getVisibility(int x, int y) {
    final key = _getTileKey(x, y);
    return _visibilityCache[key] ?? TileVisibility.hidden;
  }

  /// Check if a tile should be rendered (visible or fog)
  bool shouldRender(int x, int y) {
    final visibility = getVisibility(x, y);
    return visibility != TileVisibility.hidden;
  }

  /// Clear all visibility state (resets fog-of-war)
  void clear() {
    _visibilityCache.clear();
  }

  /// Clear only fog tiles (keeps visible tiles)
  /// Useful for resetting exploration without affecting current visibility
  void clearFog() {
    _visibilityCache.removeWhere((key, value) => value == TileVisibility.fog);
  }

  /// Get statistics about visibility
  VisibilityStats get stats {
    var visibleCount = 0;
    var fogCount = 0;

    for (final state in _visibilityCache.values) {
      if (state == TileVisibility.visible) {
        visibleCount++;
      } else if (state == TileVisibility.fog) {
        fogCount++;
      }
    }

    return VisibilityStats(
      visibleTiles: visibleCount,
      fogTiles: fogCount,
      totalTracked: _visibilityCache.length,
    );
  }

  String _getTileKey(int x, int y) => '$x:$y';
}

/// Statistics about tile visibility
class VisibilityStats {
  const VisibilityStats({
    required this.visibleTiles,
    required this.fogTiles,
    required this.totalTracked,
  });

  final int visibleTiles;
  final int fogTiles;
  final int totalTracked;

  @override
  String toString() =>
      'VisibilityStats(visible: $visibleTiles, fog: $fogTiles, total: $totalTracked)';
}
