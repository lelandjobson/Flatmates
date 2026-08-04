import 'package:flutter/material.dart';
import 'iso_camera.dart';
import 'iso_projection.dart';

/// Represents a position in isometric coordinate space
///
/// The coordinate system uses:
/// - x, y: tile coordinates (increments of 1)
/// - h: height level for vertical stacking
/// - z: zoom level (for compatibility with existing TileCoordinate)
class IsoCoordinate {
  const IsoCoordinate({
    required this.x,
    required this.y,
    this.h = 0,
    this.z = 0,
  });

  final int x;
  final int y;
  final int h; // height level
  final int z; // zoom level

  /// Compare only x and y (tile position), ignoring h and z
  bool samePosition(IsoCoordinate other) => x == other.x && y == other.y;

  /// Convert to screen space given camera view
  /// Returns the center point of the tile in screen coordinates
  Offset toScreen(IsoCamera camera, Size viewport) {
    // Get base isometric position with view rotation
    final isoPos = IsoProjection.isoToScreen(
      x,
      y,
      viewIndex: camera.view.index,
    );

    // Apply height offset (tiles higher up appear higher on screen)
    final heightOffset = h * IsoProjection.heightPerLevel;
    final worldPos = Offset(isoPos.dx, isoPos.dy - heightOffset);

    // Transform through camera
    return camera.worldToScreen(worldPos, viewport);
  }

  /// Get tile bounding box in screen space
  /// Returns the diamond-shaped bounding box as a rectangle
  Rect getTileBoundingBox(IsoCamera camera, Size viewport) {
    final center = toScreen(camera, viewport);
    final halfWidth = IsoProjection.tileWidth / 2 * camera.zoom;
    final halfHeight = IsoProjection.tileHeight / 2 * camera.zoom;

    return Rect.fromCenter(
      center: center,
      width: halfWidth * 2,
      height: halfHeight * 2,
    );
  }

  /// Get the four corner points of the tile quad in screen space.
  ///
  /// At cardinal views this is a classic isometric diamond; at intermediate
  /// views it is a parallelogram (military / planometric projection).
  List<Offset> getDiamondPoints(IsoCamera camera, Size viewport) {
    final center = toScreen(camera, viewport);
    final offsets = IsoProjection.getTileQuadOffsets(
      viewIndex: camera.view.index,
    );
    final z = camera.zoom;
    return [
      Offset(center.dx + offsets[0].dx * z, center.dy + offsets[0].dy * z),
      Offset(center.dx + offsets[1].dx * z, center.dy + offsets[1].dy * z),
      Offset(center.dx + offsets[2].dx * z, center.dy + offsets[2].dy * z),
      Offset(center.dx + offsets[3].dx * z, center.dy + offsets[3].dy * z),
    ];
  }

  /// Calculate depth for rendering order (view-independent)
  /// Use getDepthForView() for view-aware depth sorting
  /// Tiles with higher depth values should be rendered later (on top)
  double get depth => (x + y).toDouble() + h * 0.001;

  /// Calculate depth for rendering order based on camera view.
  /// This ensures correct front-to-back ordering for each view direction.
  /// Works for all 8 (or any number of) view directions.
  double getDepthForView(IsoViewDirection view) {
    final baseDepth = IsoProjection.depthForAngle(x, y, view.angleRad);
    // Add height component (higher tiles render on top)
    return baseDepth + h * 0.001;
  }

  /// Create a copy with optional field changes
  IsoCoordinate copyWith({int? x, int? y, int? h, int? z}) {
    return IsoCoordinate(
      x: x ?? this.x,
      y: y ?? this.y,
      h: h ?? this.h,
      z: z ?? this.z,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is IsoCoordinate &&
        other.x == x &&
        other.y == y &&
        other.h == h &&
        other.z == z;
  }

  @override
  int get hashCode => Object.hash(x, y, h, z);

  @override
  String toString() => 'IsoCoordinate($x, $y, h=$h, z=$z)';

  /// Key for use in maps (position only, ignoring h/z)
  String get key => '$x:$y';

  /// Get all neighbor tile coordinates within a given range.
  ///
  /// Returns all tiles within [range] tiles in any direction (diamond/manhattan pattern).
  /// This is used for hit testing to check assets on nearby tiles that could
  /// visually overlap with the clicked position.
  ///
  /// Returns a list of (x, y) tuples for neighbor tile coordinates (excludes self).
  List<(int, int)> getNeighborsInRange({int range = 3}) {
    final neighbors = <(int, int)>[];

    for (var dx = -range; dx <= range; dx++) {
      for (var dy = -range; dy <= range; dy++) {
        if (dx == 0 && dy == 0) continue; // Skip self
        neighbors.add((x + dx, y + dy));
      }
    }

    return neighbors;
  }
}
