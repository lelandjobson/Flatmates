import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../geometry/geometry_2d.dart';
import '../../geometry/geometry_algorithms.dart';
import 'iso_coordinate.dart';

/// Utilities for axonometric projection calculations.
///
/// The projection supports any rotation angle but is typically used with
/// discrete [viewCount] steps. At cardinal angles (0, 90, 180, 270 deg)
/// tiles are standard isometric diamonds; at intermediate angles they
/// become parallelogram / military-projection quads.
class IsoProjection {
  IsoProjection._();

  /// Number of discrete view directions. Currently 8 (45-degree steps).
  /// Increasing to 16 (22.5-degree steps) only requires changing this,
  /// [viewStepRad], and expanding the [IsoViewDirection] enum.
  static const int viewCount = 8;

  /// Radians per view step: 2*pi / viewCount.
  static final double viewStepRad = 2 * math.pi / viewCount;

  /// Global angle offset applied to every view direction.
  /// Shifts all projection, depth-sorting, and sprite-generation angles.
  /// Clamped to +/- 45 degrees (pi/4 radians). Change and hot-restart.
  static double baseAngleRad = math.pi / 36;

  /// [baseAngleRad] expressed in degrees for sprite-generation helpers.
  static double get baseAngleDeg => baseAngleRad * 180.0 / math.pi;

  /// Continuous angle for a discrete view index, including [baseAngleRad].
  static double angleForView(int viewIndex) =>
      viewIndex * viewStepRad + baseAngleRad;

  /// Diamond tile dimensions (used as the axonometric basis vectors).
  static const double tileWidth = 128.0;
  static const double tileHeight = 64.0;

  /// Height offset per level (for stacking tiles vertically)
  static const double heightPerLevel = 32.0;

  /// Standard 3D model units per tile width.
  /// OBJ models are authored at this scale: 10 model units = 1 tile.
  static const double worldUnitsPerTile = 10.0;

  /// Default map camera zoom (matches [IsoCamera] initial zoom on the world map
  /// and [TileFriendDisplayView]).
  static const double defaultMapZoom = 3.0;

  /// Draw-time scale for completed crafts placed on map tiles.
  ///
  /// Full OBJ model groups fill one tile at asset scale 1.0 — see
  /// [TileFriendDisplayView] where structures use the same sprite pipeline.
  /// Crafts are small tile props (~96 px wide at [defaultMapZoom]) rather than
  /// structure-sized footprints.
  static const double craftMapDisplayScale =
      96.0 / (tileWidth * defaultMapZoom);

  // ---------- cached tile-quad corner offsets ----------
  static int _cachedQuadViewIndex = -1;
  static double _cachedQuadBaseAngle = double.nan;
  static List<Offset> _cachedQuadOffsets = const [];

  /// Core axonometric projection: converts grid coordinates to screen offset
  /// for an arbitrary rotation angle.
  ///
  /// This is resolution-independent — it works for any angle, not just
  /// the discrete [viewCount] steps.
  static Offset axonToScreen(num x, num y, {required double angleRad}) {
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final rx = x * cosA - y * sinA;
    final ry = x * sinA + y * cosA;
    return Offset((rx - ry) * tileWidth / 2, (rx + ry) * tileHeight / 2);
  }

  /// Convenience wrapper using a discrete view index (0 .. [viewCount]-1).
  static Offset isoToScreen(num x, num y, {int viewIndex = 0}) {
    return axonToScreen(x, y, angleRad: angleForView(viewIndex));
  }

  /// Inverse axonometric projection for a raw angle.
  /// Returns the nearest grid coordinate (rounded).
  static IsoCoordinate? axonToIso(Offset screen, {required double angleRad}) {
    final normalizedX = screen.dx / (tileWidth / 2);
    final normalizedY = screen.dy / (tileHeight / 2);

    // Rotated grid coordinates
    final rx = (normalizedX + normalizedY) / 2;
    final ry = (normalizedY - normalizedX) / 2;

    // Inverse rotation: transpose of rotation matrix
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    final x = (rx * cosA + ry * sinA).round();
    final y = (-rx * sinA + ry * cosA).round();

    return IsoCoordinate(x: x, y: y);
  }

  /// Convenience inverse projection using a discrete view index.
  static IsoCoordinate? screenToIso(Offset screen, {int viewIndex = 0}) {
    return axonToIso(screen, angleRad: angleForView(viewIndex));
  }

  /// Get the four corner offsets of a unit tile quad at the given view index.
  ///
  /// The offsets are relative to the tile's screen-space center and are
  /// cached so they're computed only once per view change.
  static List<Offset> getTileQuadOffsets({int viewIndex = 0}) {
    if (viewIndex == _cachedQuadViewIndex &&
        baseAngleRad == _cachedQuadBaseAngle) {
      return _cachedQuadOffsets;
    }

    final angle = angleForView(viewIndex);

    _cachedQuadOffsets = [
      axonToScreen(-0.5, -0.5, angleRad: angle), // Top
      axonToScreen(0.5, -0.5, angleRad: angle), // Right
      axonToScreen(0.5, 0.5, angleRad: angle), // Bottom
      axonToScreen(-0.5, 0.5, angleRad: angle), // Left
    ];

    _cachedQuadViewIndex = viewIndex;
    _cachedQuadBaseAngle = baseAngleRad;
    return _cachedQuadOffsets;
  }

  /// Get the four corner points of a tile quad in world space.
  ///
  /// At cardinal view indices (0, 2, 4, 6) this produces the classic
  /// isometric diamond. At intermediate indices the shape is a
  /// parallelogram (military / planometric projection).
  static List<Offset> getTileQuad(int x, int y, {int viewIndex = 0}) {
    final center = isoToScreen(x, y, viewIndex: viewIndex);
    final offsets = getTileQuadOffsets(viewIndex: viewIndex);
    return [
      center + offsets[0],
      center + offsets[1],
      center + offsets[2],
      center + offsets[3],
    ];
  }

  /// Legacy name preserved for callers that haven't migrated.
  static List<Offset> getTileDiamond(int x, int y, {int viewIndex = 0}) {
    return getTileQuad(x, y, viewIndex: viewIndex);
  }

  /// Check if a screen point is inside a tile quad
  static bool isPointInTile(
    Offset point,
    int tileX,
    int tileY, {
    int viewIndex = 0,
  }) {
    final quad = getTileQuad(tileX, tileY, viewIndex: viewIndex);
    final polygon = Polygon2D.simple(quad);
    return isPointInPolygon(point, polygon);
  }

  /// Generalized depth formula for an arbitrary angle.
  ///
  /// Matches the four historical cardinal values and interpolates smoothly
  /// for any intermediate angle.
  static double depthForAngle(num x, num y, double angleRad) {
    final cosA = math.cos(angleRad);
    final sinA = math.sin(angleRad);
    return x * (cosA + sinA) + y * (cosA - sinA);
  }

  /// Get visible tile range for a given viewport
  /// Returns the min/max tile coordinates that could be visible
  static TileRange getVisibleRange({
    required Offset cameraPosition,
    required Size viewport,
    required double zoom,
    int viewIndex = 0,
    int padding = 2,
  }) {
    // Calculate corners of viewport in world space
    final corners = [
      _screenToWorld(Offset.zero, cameraPosition, viewport, zoom),
      _screenToWorld(Offset(viewport.width, 0), cameraPosition, viewport, zoom),
      _screenToWorld(
        Offset(viewport.width, viewport.height),
        cameraPosition,
        viewport,
        zoom,
      ),
      _screenToWorld(
        Offset(0, viewport.height),
        cameraPosition,
        viewport,
        zoom,
      ),
    ];

    // Convert corners to iso coordinates and find bounds
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;

    for (final corner in corners) {
      final iso = screenToIso(corner, viewIndex: viewIndex);
      if (iso != null) {
        minX = math.min(minX, iso.x.toDouble());
        maxX = math.max(maxX, iso.x.toDouble());
        minY = math.min(minY, iso.y.toDouble());
        maxY = math.max(maxY, iso.y.toDouble());
      }
    }

    return TileRange(
      minX: (minX - padding).floor(),
      maxX: (maxX + padding).ceil(),
      minY: (minY - padding).floor(),
      maxY: (maxY + padding).ceil(),
    );
  }

  /// Convert screen position to world position (inverse of worldToScreen)
  static Offset _screenToWorld(
    Offset screen,
    Offset cameraPosition,
    Size viewport,
    double zoom,
  ) {
    final centerX = viewport.width / 2;
    final centerY = viewport.height / 2;

    return Offset(
      (screen.dx - centerX) / zoom + cameraPosition.dx,
      (screen.dy - centerY) / zoom + cameraPosition.dy,
    );
  }
}

/// Range of tiles that may be visible
class TileRange {
  const TileRange({
    required this.minX,
    required this.maxX,
    required this.minY,
    required this.maxY,
  });

  final int minX;
  final int maxX;
  final int minY;
  final int maxY;

  /// Check if a coordinate is within this range
  bool contains(int x, int y) {
    return x >= minX && x <= maxX && y >= minY && y <= maxY;
  }

  /// Get total number of tiles in this range
  int get count => (maxX - minX + 1) * (maxY - minY + 1);

  @override
  String toString() => 'TileRange(x: $minX..$maxX, y: $minY..$maxY)';
}
