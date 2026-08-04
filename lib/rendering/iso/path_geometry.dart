import 'package:flutter/material.dart';
import 'iso_camera.dart';
import 'iso_coordinate.dart';

/// Cardinal directions for orthogonal path connections
enum CardinalDirection {
  north,
  south,
  east,
  west;

  /// Get opposite direction
  CardinalDirection get opposite {
    return switch (this) {
      CardinalDirection.north => CardinalDirection.south,
      CardinalDirection.south => CardinalDirection.north,
      CardinalDirection.east => CardinalDirection.west,
      CardinalDirection.west => CardinalDirection.east,
    };
  }
}

/// Type of path segment
enum PathSegmentType {
  terminal, // Start or end of path
  edge, // Straight through
  corner, // Change of direction
}

/// Abstract base class for path segment geometry
abstract class PathSegmentGeometry {
  const PathSegmentGeometry();

  /// Get line points for this segment in screen space
  List<Offset> getPoints(
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport,
    CardinalDirection? entryDirection,
    CardinalDirection? exitDirection,
  );
}

/// Terminal segment: just the tile center (start or end of path)
class TerminalSegmentGeometry extends PathSegmentGeometry {
  const TerminalSegmentGeometry();

  @override
  List<Offset> getPoints(
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport,
    CardinalDirection? entryDirection,
    CardinalDirection? exitDirection,
  ) {
    // Terminal segments are just the tile center point
    // The line drawing will connect to adjacent tile centers
    final center = coord.toScreen(camera, viewport);
    return [center];
  }
}

/// Edge segment: tile center (path goes straight through)
class EdgeSegmentGeometry extends PathSegmentGeometry {
  const EdgeSegmentGeometry();

  @override
  List<Offset> getPoints(
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport,
    CardinalDirection? entryDirection,
    CardinalDirection? exitDirection,
  ) {
    // Edge segments just pass through the tile center
    // The line connects previous and next tile centers
    final center = coord.toScreen(camera, viewport);
    return [center];
  }
}

/// Corner segment: tile center (path makes a turn here)
class CornerSegmentGeometry extends PathSegmentGeometry {
  const CornerSegmentGeometry();

  @override
  List<Offset> getPoints(
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport,
    CardinalDirection? entryDirection,
    CardinalDirection? exitDirection,
  ) {
    // Corner segments pass through the tile center
    // The turn happens at the center, connecting previous and next tile centers
    final center = coord.toScreen(camera, viewport);
    return [center];
  }
}

/// Custom segment geometry provided by path assets
class CustomSegmentGeometry extends PathSegmentGeometry {
  const CustomSegmentGeometry(this.pointsBuilder);

  final List<Offset> Function(
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport,
    CardinalDirection? entryDirection,
    CardinalDirection? exitDirection,
  )
  pointsBuilder;

  @override
  List<Offset> getPoints(
    IsoCoordinate coord,
    IsoCamera camera,
    Size viewport,
    CardinalDirection? entryDirection,
    CardinalDirection? exitDirection,
  ) {
    return pointsBuilder(
      coord,
      camera,
      viewport,
      entryDirection,
      exitDirection,
    );
  }
}

/// Detect the direction from one coordinate to another
CardinalDirection? getDirection(IsoCoordinate from, IsoCoordinate to) {
  final dx = to.x - from.x;
  final dy = to.y - from.y;

  // Only orthogonal movements allowed (any distance, but only one axis changes)
  if (dx == 0 && dy > 0) return CardinalDirection.south;
  if (dx == 0 && dy < 0) return CardinalDirection.north;
  if (dx > 0 && dy == 0) return CardinalDirection.east;
  if (dx < 0 && dy == 0) return CardinalDirection.west;

  return null; // Invalid or non-orthogonal movement
}

/// Detect the segment type and appropriate geometry
PathSegmentInfo detectSegment(
  IsoCoordinate current,
  IsoCoordinate? previous,
  IsoCoordinate? next,
) {
  // Terminal segment (start or end)
  if (previous == null) {
    final exitDir = next != null ? getDirection(current, next) : null;
    return PathSegmentInfo(
      type: PathSegmentType.terminal,
      geometry: const TerminalSegmentGeometry(),
      entryDirection: null,
      exitDirection: exitDir,
    );
  }

  if (next == null) {
    final entryDir = getDirection(previous, current);
    return PathSegmentInfo(
      type: PathSegmentType.terminal,
      geometry: const TerminalSegmentGeometry(),
      entryDirection: entryDir,
      exitDirection: null,
    );
  }

  // Get directions
  final entryDir = getDirection(previous, current);
  final exitDir = getDirection(current, next);

  if (entryDir == null || exitDir == null) {
    // Invalid path, shouldn't happen
    return PathSegmentInfo(
      type: PathSegmentType.terminal,
      geometry: const TerminalSegmentGeometry(),
      entryDirection: null,
      exitDirection: null,
    );
  }

  // Check if straight through or corner (same direction = straight edge)
  if (entryDir == exitDir) {
    // Straight edge
    return PathSegmentInfo(
      type: PathSegmentType.edge,
      geometry: const EdgeSegmentGeometry(),
      entryDirection: entryDir,
      exitDirection: exitDir,
    );
  }

  // Corner
  return PathSegmentInfo(
    type: PathSegmentType.corner,
    geometry: const CornerSegmentGeometry(),
    entryDirection: entryDir,
    exitDirection: exitDir,
  );
}

/// Information about a path segment
class PathSegmentInfo {
  const PathSegmentInfo({
    required this.type,
    required this.geometry,
    required this.entryDirection,
    required this.exitDirection,
  });

  final PathSegmentType type;
  final PathSegmentGeometry geometry;
  final CardinalDirection? entryDirection;
  final CardinalDirection? exitDirection;
}

// =============================================================================
// Waypoint / polyline helpers (orthogonal grid only)
// =============================================================================

/// Rasterize an orthogonal segment from [a] to [b] (inclusive).
/// Returns all grid tiles on the segment. [a] and [b] must be on same row or same column.
List<IsoCoordinate> rasterizeSegment(IsoCoordinate a, IsoCoordinate b) {
  final dx = (b.x - a.x).abs();
  final dy = (b.y - a.y).abs();
  if (dx != 0 && dy != 0) {
    return [a]; // Not orthogonal; return single point
  }
  final out = <IsoCoordinate>[];
  final stepX = dx == 0 ? 0 : (b.x > a.x ? 1 : -1);
  final stepY = dy == 0 ? 0 : (b.y > a.y ? 1 : -1);
  var x = a.x;
  var y = a.y;
  final count = dx + dy;
  for (var i = 0; i <= count; i++) {
    out.add(IsoCoordinate(x: x, y: y, h: a.h));
    if (i < count) {
      x += stepX;
      y += stepY;
    }
  }
  return out;
}

/// Total Manhattan distance along a polyline of waypoints (sum of segment lengths).
int pathLengthTiles(List<IsoCoordinate> waypoints) {
  if (waypoints.length < 2) return 0;
  var len = 0;
  for (var i = 0; i < waypoints.length - 1; i++) {
    len += (waypoints[i + 1].x - waypoints[i].x).abs() +
        (waypoints[i + 1].y - waypoints[i].y).abs();
  }
  return len;
}

/// Reduce a tile-by-tile path to waypoints (keep first, last, and direction changes).
List<IsoCoordinate> reducePathToWaypoints(List<IsoCoordinate> tiles) {
  if (tiles.length <= 2) return List.from(tiles);
  final out = <IsoCoordinate>[tiles.first];
  for (var i = 1; i < tiles.length - 1; i++) {
    final prev = getDirection(tiles[i - 1], tiles[i]);
    final next = getDirection(tiles[i], tiles[i + 1]);
    if (prev != next) {
      out.add(tiles[i]);
    }
  }
  out.add(tiles.last);
  return out;
}
