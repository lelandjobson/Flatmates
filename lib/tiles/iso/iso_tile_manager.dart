import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../rendering/iso/iso_camera.dart';
import '../../rendering/iso/iso_coordinate.dart';
import '../../rendering/iso/iso_painter.dart';
import '../../rendering/iso/iso_projection.dart';
import 'iso_tile_provider.dart';

/// Loading mode for tiles
enum IsoTileLoadingMode {
  /// Fixed radius around camera
  fixed,

  /// Dynamic radius based on viewport size
  dynamic,
}

/// Manages tile loading and unloading based on camera viewport
class IsoTileManager {
  IsoTileManager({
    required List<IsoTileProvider> providers,
    this.loadingMode = IsoTileLoadingMode.dynamic,
    this.fixedRadius = 3,
    this.viewportBufferPercent = 0.30,
  }) : assert(providers.isNotEmpty, 'Must have at least one provider'),
       assert(
         viewportBufferPercent >= 0 && viewportBufferPercent <= 1.0,
         'viewportBufferPercent must be between 0 and 1',
       ),
       _providers = List.from(providers);

  List<IsoTileProvider> _providers;

  /// Update the tile providers and clear cached tiles
  void setProviders(List<IsoTileProvider> providers) {
    assert(providers.isNotEmpty, 'Must have at least one provider');
    _providers = List.from(providers);
    // Clear tiles to force reload
    tilesNotifier.value = const [];
    _lastAppliedViewport = null;
  }

  final IsoTileLoadingMode loadingMode;
  final int fixedRadius;

  /// Buffer percentage beyond visible viewport (0.0 to 1.0)
  /// 0.30 = 30% extra tiles on each side
  final double viewportBufferPercent;

  final ValueNotifier<List<IsoTileData>> tilesNotifier =
      ValueNotifier<List<IsoTileData>>(const []);

  bool _isFetching = false;
  bool _isDisposed = false;
  IsoTileViewport? _pendingViewport;
  IsoTileViewport? _lastAppliedViewport;

  /// Get the last successfully applied viewport
  IsoTileViewport? get currentViewport => _lastAppliedViewport;

  /// Update visible tiles based on camera state
  Future<void> updateViewport({
    required IsoCamera camera,
    required Size viewportSize,
  }) async {
    if (_isDisposed) return;

    // Calculate viewport - use view-aware conversion
    final centerIso = IsoProjection.screenToIso(
      camera.position,
      viewIndex: camera.view.index,
    );
    if (centerIso == null) return;

    final radius = loadingMode == IsoTileLoadingMode.fixed
        ? fixedRadius
        : _calculateDynamicRadius(camera, viewportSize);

    final viewport = IsoTileViewport(
      centerX: centerIso.x,
      centerY: centerIso.y,
      radius: radius,
      zoom: camera
          .view
          .index, // Track view direction to trigger reload on rotation
      // NOTE: Tile providers should NOT use this for color/material
      // generation - tiles must be consistent across all views
    );

    // Skip if viewport hasn't changed
    if (viewport == _lastAppliedViewport) {
      return;
    }

    _pendingViewport = viewport;

    // If already fetching, let the current fetch handle it
    if (_isFetching) {
      return;
    }

    // Process pending viewport updates
    while (_pendingViewport != null && !_isDisposed) {
      final current = _pendingViewport!;
      _pendingViewport = null;
      _isFetching = true;

      try {
        final allTiles = <IsoTileData>[];

        // Fetch from all providers
        for (final provider in _providers) {
          final tiles = await provider.fetchTiles(current);
          allTiles.addAll(tiles);
        }

        if (!_isDisposed) {
          tilesNotifier.value = List.unmodifiable(allTiles);
          _lastAppliedViewport = current;
        }
      } catch (e) {
        debugPrint('Error fetching tiles: $e');
      } finally {
        _isFetching = false;
      }
    }
  }

  /// Calculate dynamic radius based on viewport size and zoom
  int _calculateDynamicRadius(IsoCamera camera, Size viewportSize) {
    if (viewportSize.isEmpty) return fixedRadius;

    // Calculate how many tiles fit in the viewport at current zoom
    final tilesX =
        (viewportSize.width / (IsoProjection.tileWidth * camera.zoom)).ceil();
    final tilesY =
        (viewportSize.height / (IsoProjection.tileHeight * camera.zoom)).ceil();

    // Use the larger dimension and add percentage-based buffer
    final maxTiles = tilesX > tilesY ? tilesX : tilesY;
    final baseRadius = (maxTiles / 2).ceil();
    final bufferTiles = (baseRadius * viewportBufferPercent).ceil();
    return baseRadius + bufferTiles;
  }

  /// Force reload of current viewport
  Future<void> forceReload() async {
    _lastAppliedViewport = null;
    if (_pendingViewport != null) {
      await updateViewport(
        camera: IsoCamera(position: Offset.zero), // Dummy camera
        viewportSize: Size.zero,
      );
    }
  }

  /// Clear all tiles
  void clear() {
    tilesNotifier.value = const [];
    _lastAppliedViewport = null;
    _pendingViewport = null;
  }

  /// Get tile at specific coordinate (compares x, y only)
  IsoTileData? getTileAt(IsoCoordinate coord) {
    for (final tile in tilesNotifier.value) {
      if (tile.coordinate.samePosition(coord)) {
        return tile;
      }
    }
    return null;
  }

  /// Get all tiles at a specific grid position (ignoring height)
  List<IsoTileData> getTilesAt(int x, int y) {
    return tilesNotifier.value
        .where((tile) => tile.coordinate.x == x && tile.coordinate.y == y)
        .toList();
  }

  /// Dispose of resources
  void dispose() {
    _isDisposed = true;
    _pendingViewport = null;
    tilesNotifier.dispose();
  }

  /// Get current stats
  TileManagerStats get stats => TileManagerStats(
    tileCount: tilesNotifier.value.length,
    isFetching: _isFetching,
    lastViewport: _lastAppliedViewport,
  );
}

/// Statistics about tile manager state
class TileManagerStats {
  const TileManagerStats({
    required this.tileCount,
    required this.isFetching,
    this.lastViewport,
  });

  final int tileCount;
  final bool isFetching;
  final IsoTileViewport? lastViewport;

  @override
  String toString() {
    return 'TileManagerStats(tiles: $tileCount, fetching: $isFetching, viewport: $lastViewport)';
  }
}
