import 'dart:async';
import 'dart:ui' show Color;
import '../rendering/iso/iso_coordinate.dart';
import '../rendering/iso/path_geometry.dart' as path_geom;
import '../rendering/iso/path_style.dart';

/// Unique identifier for a path
typedef PathId = String;

/// A first-class path entry with ordered waypoints (corners + endpoints), visual style, and identity.
///
/// [coordinates] are waypoints only; movement is point-to-point along orthogonal segments.
/// Paths can be named, coloured, selected, and assigned to friends for walk or gather actions.
class PathEntry {
  PathEntry({
    required this.id,
    required this.coordinates,
    required this.style,
    this.name = 'Unnamed Path',
    this.color = const Color(
      0xFFFFB3BA,
    ), // default: first pastel swatch (pink light)
    this.metadata = const {},
    this.stops,
  });

  /// Unique path identifier
  final PathId id;

  /// Ordered list of waypoints (corners + endpoints). Movement runs point-to-point along orthogonal segments.
  final List<IsoCoordinate> coordinates;

  /// Indices into [coordinates] where the friend must stop. Null or empty = all waypoints are stops.
  final Set<int>? stops;

  /// Visual style for rendering
  PathStyle style;

  /// Human-readable name (editable by the user)
  String name;

  /// User-chosen colour used for rendering and UI badges
  Color color;

  /// Additional metadata
  final Map<String, dynamic> metadata;

  /// First coordinate (source endpoint)
  IsoCoordinate? get startCoordinate =>
      coordinates.isNotEmpty ? coordinates.first : null;

  /// Last coordinate (target endpoint)
  IsoCoordinate? get endCoordinate =>
      coordinates.isNotEmpty ? coordinates.last : null;

  /// Number of waypoints
  int get tileCount => coordinates.length;

  /// Total path length in tiles (sum of Manhattan distances between consecutive waypoints).
  int pathLengthTiles() => path_geom.pathLengthTiles(coordinates);

  /// Whether a given coordinate lies on this path (on any waypoint or segment).
  bool containsCoordinate(IsoCoordinate coord) {
    for (var i = 0; i < coordinates.length; i++) {
      if (coordinates[i].samePosition(coord)) return true;
      if (i < coordinates.length - 1) {
        for (final t in path_geom.rasterizeSegment(coordinates[i], coordinates[i + 1])) {
          if (t.samePosition(coord)) return true;
        }
      }
    }
    return false;
  }

  /// Index of the waypoint at or after [coord]: if [coord] equals waypoint i return i;
  /// if [coord] is strictly between waypoint i and i+1 return i+1. Returns -1 if not on path.
  int indexOfCoordinate(IsoCoordinate coord) {
    for (var i = 0; i < coordinates.length; i++) {
      if (coordinates[i].samePosition(coord)) return i;
      if (i < coordinates.length - 1) {
        final seg = path_geom.rasterizeSegment(coordinates[i], coordinates[i + 1]);
        for (var k = 0; k < seg.length; k++) {
          if (seg[k].samePosition(coord)) {
            return k == 0 ? i : i + 1;
          }
        }
      }
    }
    return -1;
  }

  /// All grid tiles on the polyline (for spatial index and paint overlay).
  List<IsoCoordinate> tilesOnPath() {
    if (coordinates.isEmpty) return [];
    if (coordinates.length == 1) return [coordinates.first];
    final out = <IsoCoordinate>[];
    for (var i = 0; i < coordinates.length - 1; i++) {
      final seg = path_geom.rasterizeSegment(coordinates[i], coordinates[i + 1]);
      for (var k = 0; k < seg.length; k++) {
        if (i > 0 && k == 0) continue;
        out.add(seg[k]);
      }
    }
    return out;
  }

  /// Return a sub-path from the coordinate at [fromIndex] to [toIndex] (inclusive).
  List<IsoCoordinate> subPath(int fromIndex, int toIndex) {
    if (fromIndex < 0 || toIndex < 0) return [];
    final start = fromIndex < toIndex ? fromIndex : toIndex;
    final end = fromIndex < toIndex ? toIndex : fromIndex;
    final sub = coordinates.sublist(start, end + 1);
    // If original direction was reversed, reverse the result
    return fromIndex <= toIndex ? sub : sub.reversed.toList();
  }

  /// Get bounding box for spatial indexing
  _PathBounds getBounds() {
    if (coordinates.isEmpty) {
      return _PathBounds(0, 0, 0, 0);
    }

    var minX = coordinates[0].x;
    var maxX = coordinates[0].x;
    var minY = coordinates[0].y;
    var maxY = coordinates[0].y;

    for (final coord in coordinates) {
      if (coord.x < minX) minX = coord.x;
      if (coord.x > maxX) maxX = coord.x;
      if (coord.y < minY) minY = coord.y;
      if (coord.y > maxY) maxY = coord.y;
    }

    return _PathBounds(minX, minY, maxX, maxY);
  }

  /// Create a [PathStyle] derived from this entry's [color].
  PathStyle deriveStyle({
    double dotRadius = 9.0,
    double dotSpacing = 8.0,
    double opacity = 0.6,
  }) {
    return PathStyle(
      color: Color.fromRGBO(color.red, color.green, color.blue, opacity),
      dotRadius: dotRadius,
      dotSpacing: dotSpacing,
    );
  }
}

/// Simple bounds class for path bounding box
class _PathBounds {
  const _PathBounds(this.left, this.top, this.right, this.bottom);

  final int left;
  final int top;
  final int right;
  final int bottom;
}

/// Database for storing and querying paths
class PathDatabase {
  PathDatabase({this.gridSize = 10});

  /// Size of spatial grid cells
  final int gridSize;

  /// Main storage: path ID → path entry
  final Map<PathId, PathEntry> _paths = {};

  /// Spatial index: grid cell key → set of path IDs
  final Map<String, Set<PathId>> _spatialIndex = {};

  /// Counter for generating unique IDs
  int _nextId = 0;

  /// Get the number of paths
  int get count => _paths.length;

  /// Get all path IDs
  Iterable<PathId> get pathIds => _paths.keys;

  /// Generate a grid cell key for a coordinate
  String _getCellKey(int x, int y) {
    final cellX = x ~/ gridSize;
    final cellY = y ~/ gridSize;
    return '$cellX:$cellY';
  }

  /// Get all cells that a path touches (every tile on the polyline)
  Set<String> _getPathCells(PathEntry path) {
    final cells = <String>{};
    for (final coord in path.tilesOnPath()) {
      cells.add(_getCellKey(coord.x, coord.y));
    }
    return cells;
  }

  /// Add a path to the database
  Future<PathId> addPath({
    required List<IsoCoordinate> coordinates,
    required PathStyle style,
    PathId? id,
    String name = 'Unnamed Path',
    Color color = const Color(0xFFFFB3BA),
    Map<String, dynamic> metadata = const {},
    Set<int>? stops,
  }) async {
    await Future.delayed(Duration.zero);

    final pathId = id ?? 'path_${_nextId++}';
    final entry = PathEntry(
      id: pathId,
      coordinates: coordinates,
      style: style,
      name: name,
      color: color,
      metadata: metadata,
      stops: stops,
    );

    // Add to main storage
    _paths[pathId] = entry;

    // Add to spatial index
    final cells = _getPathCells(entry);
    for (final cell in cells) {
      _spatialIndex.putIfAbsent(cell, () => {}).add(pathId);
    }

    return pathId;
  }

  /// Remove a path from the database
  Future<bool> removePath(PathId id) async {
    await Future.delayed(Duration.zero);

    final entry = _paths.remove(id);
    if (entry == null) {
      return false;
    }

    // Remove from spatial index
    final cells = _getPathCells(entry);
    for (final cell in cells) {
      _spatialIndex[cell]?.remove(id);
      if (_spatialIndex[cell]?.isEmpty ?? false) {
        _spatialIndex.remove(cell);
      }
    }

    return true;
  }

  /// Total number of paths.
  List<PathEntry> get allPaths => _paths.values.toList();

  /// Get a specific path by ID
  Future<PathEntry?> getPath(PathId id) async {
    await Future.delayed(Duration.zero);
    return _paths[id];
  }

  /// Synchronous path lookup (for hit testing and UI).
  PathEntry? getPathSync(PathId id) => _paths[id];

  /// Find all paths that pass through [coord].
  List<PathEntry> getPathsAtCoordinate(IsoCoordinate coord) {
    return _paths.values.where((p) => p.containsCoordinate(coord)).toList();
  }

  /// Update a path's name.
  void updatePathName(PathId id, String name) {
    _paths[id]?.name = name;
  }

  /// Update a path's colour and re-derive its style.
  void updatePathColor(PathId id, Color color) {
    final entry = _paths[id];
    if (entry == null) return;
    entry.color = color;
    entry.style = entry.deriveStyle();
  }

  /// Query paths within a rectangular range (synchronous; use from game loop).
  List<PathEntry> queryRangeSync({
    required int minX,
    required int maxX,
    required int minY,
    required int maxY,
  }) {
    final results = <PathEntry>[];
    final seenIds = <PathId>{};

    final minCellX = minX ~/ gridSize;
    final maxCellX = maxX ~/ gridSize;
    final minCellY = minY ~/ gridSize;
    final maxCellY = maxY ~/ gridSize;

    for (var cellX = minCellX; cellX <= maxCellX; cellX++) {
      for (var cellY = minCellY; cellY <= maxCellY; cellY++) {
        final cellKey = '$cellX:$cellY';
        final pathIds = _spatialIndex[cellKey];
        if (pathIds == null) continue;

        for (final id in pathIds) {
          if (seenIds.contains(id)) continue;

          final entry = _paths[id];
          if (entry == null) continue;

          final bounds = entry.getBounds();
          if (bounds.right >= minX &&
              bounds.left <= maxX &&
              bounds.bottom >= minY &&
              bounds.top <= maxY) {
            results.add(entry);
            seenIds.add(id);
          }
        }
      }
    }

    return results;
  }

  /// Query paths within a rectangular range (async; kept for compatibility).
  Future<List<PathEntry>> queryRange({
    required int minX,
    required int maxX,
    required int minY,
    required int maxY,
  }) async {
    await Future.delayed(Duration.zero);
    return queryRangeSync(minX: minX, maxX: maxX, minY: minY, maxY: maxY);
  }

  /// Get all paths
  Future<List<PathEntry>> getAllPaths() async {
    await Future.delayed(Duration.zero);
    return _paths.values.toList();
  }

  /// Clear all paths
  Future<void> clear() async {
    await Future.delayed(Duration.zero);
    _paths.clear();
    _spatialIndex.clear();
    _nextId = 0;
  }

  /// Get database statistics
  PathDbStats get stats {
    return PathDbStats(
      totalPaths: _paths.length,
      gridCells: _spatialIndex.length,
      averagePerCell: _spatialIndex.isEmpty
          ? 0.0
          : _paths.length / _spatialIndex.length,
    );
  }
}

/// Database statistics
class PathDbStats {
  const PathDbStats({
    required this.totalPaths,
    required this.gridCells,
    required this.averagePerCell,
  });

  final int totalPaths;
  final int gridCells;
  final double averagePerCell;

  @override
  String toString() =>
      'PathDbStats(paths: $totalPaths, cells: $gridCells, avg: ${averagePerCell.toStringAsFixed(1)})';
}
