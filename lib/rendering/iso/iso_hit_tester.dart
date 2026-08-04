import 'package:flutter/material.dart';
import '../../geometry/geometry_2d.dart';
import '../../geometry/geometry_algorithms.dart';

import '../../data/path_database.dart';
import 'iso_camera.dart';
import 'iso_coordinate.dart';
import 'iso_painter.dart';
import 'iso_projection.dart';
import 'iso_asset.dart';
import 'iso_sprite.dart';
import 'iso_visibility.dart';

/// Debug info for hit test visualization
class HitTestDebugInfo {
  HitTestDebugInfo({
    required this.clickPosition,
    required this.testedPolygons,
    required this.testedBounds,
    this.hitAssetId,
  });

  final Offset clickPosition;
  final List<(String assetId, List<Offset> polygon)> testedPolygons;
  final List<(String assetId, Rect bounds)> testedBounds;
  final String? hitAssetId;
}

/// Result of a hit test
class IsoHitResult {
  const IsoHitResult({this.tile, this.asset, this.path, this.screenPosition});

  final IsoTileData? tile;
  final IsoAssetInstance? asset;
  final PathEntry? path;
  final Offset? screenPosition;

  bool get hasHit => tile != null || asset != null || path != null;

  @override
  String toString() {
    if (asset != null) {
      return 'IsoHitResult(asset: ${asset!.asset.id} at ${asset!.coordinate})';
    }
    if (path != null) {
      return 'IsoHitResult(path: ${path!.id})';
    }
    if (tile != null) {
      return 'IsoHitResult(tile: ${tile!.coordinate})';
    }
    return 'IsoHitResult(no hit)';
  }
}

/// Hit tester for isometric view
class IsoHitTester {
  const IsoHitTester({
    required this.camera,
    required this.tiles,
    required this.assets,
    required this.viewport,
    this.paths = const [],
    this.visibilityMap,
    this.skipAssetHitTest = false,
    this.hitboxScale = 1.0,
  });

  final IsoCamera camera;
  final List<IsoTileData> tiles;
  final List<IsoAssetInstance> assets;
  final List<PathEntry> paths;
  final Size viewport;
  final Map<String, TileVisibility>? visibilityMap;
  final bool skipAssetHitTest;

  /// Multiplicative factor applied to sprite hit bounds. Values > 1.0 inflate
  /// the hitbox so it's easier to tap at zoomed-out levels.
  final double hitboxScale;

  /// Perform hit test at screen position.
  ///
  /// Priority: assets > paths > tiles.
  IsoHitResult hitTest(Offset screenPosition) {
    // Test assets first (they're on top), unless skipped
    if (!skipAssetHitTest) {
      final assetHit = _testAssets(screenPosition);
      if (assetHit != null) {
        // Use the tile at the asset's coordinate, not tiles behind the asset.
        final tileHit = _getTileAtCoordinate(assetHit.coordinate);
        return IsoHitResult(
          asset: assetHit,
          tile: tileHit,
          screenPosition: screenPosition,
        );
      }
    }

    // Then test paths
    final pathHit = _testPaths(screenPosition);
    if (pathHit != null) {
      // Also include the underlying tile so that path + tile are both present.
      final tileHit = _testTiles(screenPosition);
      return IsoHitResult(
        path: pathHit,
        tile: tileHit,
        screenPosition: screenPosition,
      );
    }

    // Then test tiles
    final tileHit = _testTiles(screenPosition);
    if (tileHit != null) {
      return IsoHitResult(tile: tileHit, screenPosition: screenPosition);
    }

    return IsoHitResult(screenPosition: screenPosition);
  }

  /// Debug method: returns info about all polygons tested at a screen position
  HitTestDebugInfo getDebugInfo(Offset screenPosition) {
    final testedPolygons = <(String, List<Offset>)>[];
    final testedBounds = <(String, Rect)>[];
    String? hitAssetId;

    // Sort all assets by view-aware depth (back to front)
    final sorted = List<IsoAssetInstance>.from(assets)
      ..sort(
        (a, b) => a
            .getDepthForView(camera.view)
            .compareTo(b.getDepthForView(camera.view)),
      );

    // Test from front to back
    for (var i = sorted.length - 1; i >= 0; i--) {
      final asset = sorted[i];
      final assetId =
          '${asset.asset.id}@${asset.coordinate.x},${asset.coordinate.y}';

      // Skip hidden assets
      if (visibilityMap != null) {
        final key = '${asset.coordinate.x}:${asset.coordinate.y}';
        final visibility = visibilityMap![key] ?? TileVisibility.hidden;
        if (visibility == TileVisibility.hidden) continue;
      }

      // Get sprite and compute bounds
      final sprite = asset.asset.getSpriteForView(
        camera.view,
        rotationOffset: asset.rotationOffset,
      );
      final tileCenter = asset.coordinate.toScreen(camera, viewport);

      final spriteWidth = sprite.size.width * asset.asset.scale * camera.zoom;
      final spriteHeight = sprite.size.height * asset.asset.scale * camera.zoom;

      // Simple centering: sprite center = tile center
      final spriteX = tileCenter.dx - spriteWidth / 2;
      final spriteY = tileCenter.dy - spriteHeight / 2;

      // Scale factors
      final scaleX = spriteWidth / sprite.size.width;
      final scaleY = spriteHeight / sprite.size.height;

      // Get outline polygon if available
      if (sprite is VectorIsoSprite && sprite.outlinePolygon != null) {
        final outline = sprite.outlinePolygon!;
        if (outline.length >= 3) {
          final screenPolygon = outline.map((p) {
            return Offset(spriteX + p.dx * scaleX, spriteY + p.dy * scaleY);
          }).toList();

          // Compute bounding box from actual polygon points
          var minX = screenPolygon[0].dx;
          var maxX = screenPolygon[0].dx;
          var minY = screenPolygon[0].dy;
          var maxY = screenPolygon[0].dy;
          for (final p in screenPolygon) {
            if (p.dx < minX) minX = p.dx;
            if (p.dx > maxX) maxX = p.dx;
            if (p.dy < minY) minY = p.dy;
            if (p.dy > maxY) maxY = p.dy;
          }
          final polygonBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

          testedPolygons.add((assetId, screenPolygon));
          testedBounds.add((assetId, polygonBounds));

          // Check if this is a hit (using polygon bounds, not sprite rect)
          if (hitAssetId == null && polygonBounds.contains(screenPosition)) {
            final polygon = Polygon2D.simple(screenPolygon);
            if (isPointInPolygon(screenPosition, polygon)) {
              hitAssetId = assetId;
            }
          }
        }
      } else {
        // Fallback to sprite rect for non-polygon sprites
        final spriteRect = Rect.fromLTWH(
          spriteX,
          spriteY,
          spriteWidth,
          spriteHeight,
        );
        testedBounds.add((assetId, spriteRect));
      }
    }

    return HitTestDebugInfo(
      clickPosition: screenPosition,
      testedPolygons: testedPolygons,
      testedBounds: testedBounds,
      hitAssetId: hitAssetId,
    );
  }

  /// Test if screen position hits any assets
  IsoAssetInstance? _testAssets(Offset screenPosition) {
    if (assets.isEmpty) return null;

    // Sort all assets by view-aware depth (back to front)
    final sorted = List<IsoAssetInstance>.from(assets)
      ..sort(
        (a, b) => a
            .getDepthForView(camera.view)
            .compareTo(b.getDepthForView(camera.view)),
      );

    // Test from front to back (reverse order after sorting back-to-front)
    for (var i = sorted.length - 1; i >= 0; i--) {
      final asset = sorted[i];

      // Check visibility
      if (visibilityMap != null) {
        final key = '${asset.coordinate.x}:${asset.coordinate.y}';
        final visibility = visibilityMap![key] ?? TileVisibility.hidden;
        if (visibility == TileVisibility.hidden) continue;
      }

      if (asset.skipHitTest) continue;
      if (_isPointInAsset(screenPosition, asset)) {
        return asset;
      }
    }

    return null;
  }

  /// Test if screen position hits any path line within a threshold distance.
  PathEntry? _testPaths(Offset screenPosition) {
    if (paths.isEmpty) return null;

    final hitThreshold = 12.0 * camera.zoom;
    PathEntry? bestHit;
    double bestDist = double.infinity;

    for (final path in paths) {
      if (path.coordinates.length < 2) continue;

      for (var i = 0; i < path.coordinates.length - 1; i++) {
        final a = path.coordinates[i].toScreen(camera, viewport);
        final b = path.coordinates[i + 1].toScreen(camera, viewport);

        final dist = _pointToSegmentDistance(screenPosition, a, b);
        if (dist < hitThreshold && dist < bestDist) {
          bestDist = dist;
          bestHit = path;
        }
      }
    }

    return bestHit;
  }

  /// Minimum distance from [point] to line segment [a]-[b].
  static double _pointToSegmentDistance(Offset point, Offset a, Offset b) {
    final ab = b - a;
    final ap = point - a;
    final abLenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (abLenSq == 0) return (point - a).distance;

    var t = (ap.dx * ab.dx + ap.dy * ab.dy) / abLenSq;
    t = t.clamp(0.0, 1.0);

    final closest = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (point - closest).distance;
  }

  /// Get the tile at [coord] from the tiles list, or null if not loaded.
  IsoTileData? _getTileAtCoordinate(IsoCoordinate coord) {
    for (final tile in tiles) {
      if (tile.coordinate.samePosition(coord)) return tile;
    }
    return null;
  }

  /// Test if screen position hits any tiles
  IsoTileData? _testTiles(Offset screenPosition) {
    // Convert screen position to world space
    final worldPos = camera.screenToWorld(screenPosition, viewport);
    if (worldPos == null) return null;

    // Get approximate iso coordinate (account for camera view rotation)
    final isoCoord = IsoProjection.screenToIso(
      worldPos,
      viewIndex: camera.view.index,
    );
    if (isoCoord == null) return null;

    // Check tiles around this coordinate (in case of rounding errors)
    final candidates = <IsoTileData>[];
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final checkX = isoCoord.x + dx;
        final checkY = isoCoord.y + dy;

        for (final tile in tiles) {
          if (tile.coordinate.x == checkX && tile.coordinate.y == checkY) {
            candidates.add(tile);
          }
        }
      }
    }

    // Test each candidate tile using view-aware depth
    IsoTileData? bestMatch;
    var bestDepth = double.negativeInfinity;

    for (final tile in candidates) {
      // Check visibility
      if (visibilityMap != null) {
        final key = '${tile.coordinate.x}:${tile.coordinate.y}';
        final visibility = visibilityMap![key] ?? TileVisibility.hidden;
        if (visibility == TileVisibility.hidden) continue;
      }

      if (_isPointInTile(screenPosition, tile)) {
        final tileDepth = tile.coordinate.getDepthForView(camera.view);
        if (tileDepth > bestDepth) {
          bestMatch = tile;
          bestDepth = tileDepth;
        }
      }
    }

    return bestMatch;
  }

  /// Check if point is inside a tile diamond
  bool _isPointInTile(Offset point, IsoTileData tile) {
    final diamondPoints = tile.coordinate.getDiamondPoints(camera, viewport);
    final polygon = Polygon2D.simple(diamondPoints);
    return isPointInPolygon(point, polygon);
  }

  /// Check if point is inside an asset's visible shape (inflated by
  /// [hitboxScale]).
  bool _isPointInAsset(Offset point, IsoAssetInstance asset) {
    final sprite = asset.asset.getSpriteForInstance(asset, camera);
    final tileCenter = asset.toScreen(camera, viewport);

    final spriteWidth =
        sprite.size.width.toDouble() * asset.asset.scale * camera.zoom;
    final spriteHeight =
        sprite.size.height.toDouble() * asset.asset.scale * camera.zoom;

    final hitWidth = spriteWidth * hitboxScale;
    final hitHeight = spriteHeight * hitboxScale;
    final topLeft = IsoAsset.anchoredTopLeft(
        tileCenter, hitWidth, hitHeight, sprite);
    final hitX = topLeft.dx;
    final hitY = topLeft.dy;

    final scaleX = hitWidth / sprite.size.width;
    final scaleY = hitHeight / sprite.size.height;

    if (sprite is VectorIsoSprite && sprite.outlinePolygon != null) {
      final outline = sprite.outlinePolygon!;
      if (outline.length >= 3) {
        final screenPolygon = outline.map((p) {
          return Offset(hitX + p.dx * scaleX, hitY + p.dy * scaleY);
        }).toList();

        var minX = screenPolygon[0].dx;
        var maxX = screenPolygon[0].dx;
        var minY = screenPolygon[0].dy;
        var maxY = screenPolygon[0].dy;
        for (final p in screenPolygon) {
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
        final polygonBounds = Rect.fromLTRB(minX, minY, maxX, maxY);

        if (!polygonBounds.contains(point)) return false;

        final polygon = Polygon2D.simple(screenPolygon);
        return isPointInPolygon(point, polygon);
      }
    }

    final hitRect = Rect.fromLTWH(hitX, hitY, hitWidth, hitHeight);
    if (!hitRect.contains(point)) return false;

    if (sprite is VectorIsoSprite &&
        sprite.foregroundWireframeEdges.isNotEmpty) {
      final edgeScaleX = hitWidth / sprite.originalSize.width;
      final edgeScaleY = hitHeight / sprite.originalSize.height;

      final screenPoints = <Offset>[];
      for (final edge in sprite.foregroundWireframeEdges) {
        screenPoints.add(
          Offset(hitX + edge.$1.dx * edgeScaleX,
              hitY + edge.$1.dy * edgeScaleY),
        );
        screenPoints.add(
          Offset(hitX + edge.$2.dx * edgeScaleX,
              hitY + edge.$2.dy * edgeScaleY),
        );
      }

      if (screenPoints.length >= 3) {
        final hull = convexHull(screenPoints);
        if (hull.length >= 3) {
          final polygon = Polygon2D.simple(hull);
          return isPointInPolygon(point, polygon);
        }
      }
    }

    if (sprite is RasterIsoSprite && sprite.alphaMask != null) {
      final normalizedX = (point.dx - hitX) / hitWidth;
      final normalizedY = (point.dy - hitY) / hitHeight;
      return sprite.isOpaqueAt(normalizedX, normalizedY);
    }

    return true;
  }

  /// Get the tile coordinate at screen position (may not be loaded)
  IsoCoordinate? getCoordinateAt(Offset screenPosition) {
    final worldPos = camera.screenToWorld(screenPosition, viewport);
    if (worldPos == null) return null;
    return IsoProjection.screenToIso(worldPos, viewIndex: camera.view.index);
  }
}
