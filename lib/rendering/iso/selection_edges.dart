import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../animation/edge_morph_animation.dart';
import '../../animation/polygon_morph.dart';
import 'iso_asset.dart';
import 'iso_camera.dart';
import 'iso_painter.dart';
import 'iso_projection.dart';
import 'iso_sprite.dart';

/// Utility class to extract edges and polygons from various selection types
class SelectionEdgeExtractor {
  const SelectionEdgeExtractor({
    required this.camera,
    required this.viewportSize,
  });

  final IsoCamera camera;
  final Size viewportSize;

  /// Default selection style
  static const EdgeMorphStyle defaultStyle = EdgeMorphStyle(
    color: Colors.cyanAccent,
    thickness: 1.5,
    glowThickness: 3.0,
    glowOpacity: 0.4,
  );

  // ============ POLYGON-BASED EXTRACTION (NEW) ============

  /// Extract outline polygon from a tile selection
  MorphablePolygon extractTilePolygon(IsoTileData tile) {
    final points = tile.coordinate.getDiamondPoints(camera, viewportSize);
    return MorphablePolygon(
      points: points,
      color: Colors.cyanAccent,
      thickness: 2.0,
    );
  }

  /// Extract outline polygon from an asset selection
  MorphablePolygon extractAssetPolygon(IsoAssetInstance asset) {
    final sprite = asset.asset.getSpriteForInstance(asset, camera);

    // For vector sprites with outline polygon, use the outline
    if (sprite is VectorIsoSprite && sprite.outlinePolygon != null) {
      final outline = sprite.outlinePolygon!;
      if (outline.length >= 3) {
        // Transform to screen coordinates (use fractional pos when moving)
        final tileCenter = asset.toScreen(camera, viewportSize);
        final spriteWidth = sprite.size.width * camera.zoom * asset.asset.scale;
        final spriteHeight =
            sprite.size.height * camera.zoom * asset.asset.scale;

        final tileBBoxWidth = IsoProjection.tileWidth * camera.zoom;
        final tileBBoxHeight = IsoProjection.tileHeight * camera.zoom;

        final bboxLeft = tileCenter.dx - tileBBoxWidth / 2;
        final bboxBottom = tileCenter.dy + tileBBoxHeight / 2;

        final anchorOffset = asset.asset.anchorOffset;
        final spriteX = bboxLeft + anchorOffset.dx * spriteWidth;
        final spriteY =
            bboxBottom - spriteHeight + anchorOffset.dy * spriteHeight;

        final scaleX = spriteWidth / sprite.size.width;
        final scaleY = spriteHeight / sprite.size.height;

        final screenPoints = outline.map((p) {
          return Offset(spriteX + p.dx * scaleX, spriteY + p.dy * scaleY);
        }).toList();

        return MorphablePolygon(
          points: screenPoints,
          color: Colors.cyanAccent,
          thickness: 2.0,
        );
      }
    }

    // Fallback: use diamond at asset's current position (fractional when moving)
    final center = asset.toScreen(camera, viewportSize);
    final offsets = IsoProjection.getTileQuadOffsets(
      viewIndex: camera.view.index,
    );
    final z = camera.zoom;
    final tilePoints = [
      Offset(center.dx + offsets[0].dx * z, center.dy + offsets[0].dy * z),
      Offset(center.dx + offsets[1].dx * z, center.dy + offsets[1].dy * z),
      Offset(center.dx + offsets[2].dx * z, center.dy + offsets[2].dy * z),
      Offset(center.dx + offsets[3].dx * z, center.dy + offsets[3].dy * z),
    ];
    return MorphablePolygon(
      points: tilePoints,
      color: Colors.cyanAccent,
      thickness: 2.0,
    );
  }

  /// Extract a bounding-box rectangle from the outline polygon's extents.
  /// Falls back to the full sprite rect when no outline is available.
  MorphablePolygon extractFoliageBBox(IsoAssetInstance asset) {
    final sprite = asset.asset.getSpriteForInstance(asset, camera);
    final tileCenter = asset.toScreen(camera, viewportSize);
    final spriteWidth = sprite.size.width * camera.zoom * asset.asset.scale;
    final spriteHeight = sprite.size.height * camera.zoom * asset.asset.scale;
    final spriteX = tileCenter.dx - spriteWidth / 2;
    final spriteY = tileCenter.dy - spriteHeight / 2;

    final List<Offset> points;

    if (sprite is VectorIsoSprite &&
        sprite.outlinePolygon != null &&
        sprite.outlinePolygon!.length >= 3) {
      final scaleX = spriteWidth / sprite.originalSize.width;
      final scaleY = spriteHeight / sprite.originalSize.height;

      double minPx = double.infinity, minPy = double.infinity;
      double maxPx = double.negativeInfinity, maxPy = double.negativeInfinity;
      for (final pt in sprite.outlinePolygon!) {
        final sx = spriteX + pt.dx * scaleX;
        final sy = spriteY + pt.dy * scaleY;
        if (sx < minPx) minPx = sx;
        if (sy < minPy) minPy = sy;
        if (sx > maxPx) maxPx = sx;
        if (sy > maxPy) maxPy = sy;
      }

      points = [
        Offset(minPx, minPy),
        Offset(maxPx, minPy),
        Offset(maxPx, maxPy),
        Offset(minPx, maxPy),
      ];
    } else {
      points = [
        Offset(spriteX, spriteY),
        Offset(spriteX + spriteWidth, spriteY),
        Offset(spriteX + spriteWidth, spriteY + spriteHeight),
        Offset(spriteX, spriteY + spriteHeight),
      ];
    }

    return MorphablePolygon(
      points: points,
      color: Colors.lightGreenAccent,
      thickness: 2.0,
    );
  }

  // ============ EDGE-BASED EXTRACTION (LEGACY) ============

  /// Extract edges from a tile selection
  List<MorphableEdge> extractTileEdges(IsoTileData tile) {
    final points = tile.coordinate.getDiamondPoints(camera, viewportSize);
    return _pointsToEdges(points);
  }

  /// Extract edges from an asset selection
  List<MorphableEdge> extractAssetEdges(IsoAssetInstance asset) {
    final sprite = asset.asset.getSpriteForInstance(asset, camera);

    if (sprite is VectorIsoSprite &&
        (sprite.foregroundWireframeEdges.isNotEmpty ||
            sprite.backgroundWireframeEdges.isNotEmpty)) {
      // Calculate destination rect (use fractional pos when moving)
      final tileCenter = asset.toScreen(camera, viewportSize);
      final spriteWidth = sprite.size.width * camera.zoom * asset.asset.scale;
      final spriteHeight = sprite.size.height * camera.zoom * asset.asset.scale;

      // Get the tile's bounding box dimensions in screen space
      final tileBBoxWidth = IsoProjection.tileWidth * camera.zoom;
      final tileBBoxHeight = IsoProjection.tileHeight * camera.zoom;

      // Position sprite so its bottom-left corner is at the tile bounding box's bottom-left
      final bboxLeft = tileCenter.dx - tileBBoxWidth / 2;
      final bboxBottom = tileCenter.dy + tileBBoxHeight / 2;

      final anchorOffset = asset.asset.anchorOffset;
      final spriteX = bboxLeft + anchorOffset.dx * spriteWidth;
      final spriteY =
          bboxBottom - spriteHeight + anchorOffset.dy * spriteHeight;

      final dest = Rect.fromLTWH(spriteX, spriteY, spriteWidth, spriteHeight);

      // Combine foreground and background edges
      final edges = <MorphableEdge>[];

      // Transform edges to screen coordinates
      final scaleX = dest.width / sprite.originalSize.width;
      final scaleY = dest.height / sprite.originalSize.height;

      for (final edge in sprite.foregroundWireframeEdges) {
        final start = Offset(
          dest.left + edge.$1.dx * scaleX,
          dest.top + edge.$1.dy * scaleY,
        );
        final end = Offset(
          dest.left + edge.$2.dx * scaleX,
          dest.top + edge.$2.dy * scaleY,
        );
        edges.add(
          MorphableEdge(
            start: start,
            end: end,
            color: Colors.cyanAccent,
            thickness: 1.5,
          ),
        );
      }

      // Include background edges with lower opacity
      for (final edge in sprite.backgroundWireframeEdges) {
        final start = Offset(
          dest.left + edge.$1.dx * scaleX,
          dest.top + edge.$1.dy * scaleY,
        );
        final end = Offset(
          dest.left + edge.$2.dx * scaleX,
          dest.top + edge.$2.dy * scaleY,
        );
        edges.add(
          MorphableEdge(
            start: start,
            end: end,
            color: Colors.cyanAccent.withOpacity(0.4),
            thickness: 0.8,
          ),
        );
      }

      return edges;
    } else {
      // Fallback: create a circle approximation for raster sprites
      final center = asset.toScreen(camera, viewportSize);
      final radius = 30 * camera.zoom;
      return _circleToEdges(center, radius, segments: 16);
    }
  }

  /// Convert a list of points (closed polygon) to edges
  List<MorphableEdge> _pointsToEdges(List<Offset> points) {
    if (points.length < 2) return [];

    final edges = <MorphableEdge>[];
    for (var i = 0; i < points.length; i++) {
      final start = points[i];
      final end = points[(i + 1) % points.length];
      edges.add(
        MorphableEdge(
          start: start,
          end: end,
          color: Colors.cyanAccent,
          thickness: 1.5,
        ),
      );
    }
    return edges;
  }

  /// Create edges approximating a circle
  List<MorphableEdge> _circleToEdges(
    Offset center,
    double radius, {
    int segments = 16,
  }) {
    final edges = <MorphableEdge>[];
    for (var i = 0; i < segments; i++) {
      final angle1 = (i / segments) * 2 * 3.14159;
      final angle2 = ((i + 1) / segments) * 2 * 3.14159;

      final start = Offset(
        center.dx + radius * math.cos(angle1),
        center.dy + radius * math.sin(angle1),
      );
      final end = Offset(
        center.dx + radius * math.cos(angle2),
        center.dy + radius * math.sin(angle2),
      );

      edges.add(
        MorphableEdge(
          start: start,
          end: end,
          color: Colors.cyanAccent,
          thickness: 1.5,
        ),
      );
    }
    return edges;
  }
}
