import 'dart:ui' show Color;
import 'package:flutter/foundation.dart';
import '../rendering/iso/iso_coordinate.dart';
import '../rendering/iso/path_geometry.dart' as path_geom;

/// Paint mode for the tile painter
enum TilePaintMode {
  /// Paint any tile freely; painting an already-painted tile (from a previous
  /// stroke) toggles it off.
  arbitrary,

  /// Paint a path as waypoints: same row or column as last waypoint, up to [maxMoveTiles] total length.
  path,
}

/// Reusable controller for multi-tile painting / selection.
///
/// Works with two modes:
/// - [TilePaintMode.arbitrary]: click/drag to paint tiles; re-painting a tile
///   from a previous stroke unpaints it (toggle). Tiles painted in the *same*
///   stroke are never toggled off during that stroke.
/// - [TilePaintMode.path]: waypoints only. Each new tile must be in the same
///   row or same column as the last waypoint, and total path length cannot exceed [maxMoveTiles].
class TilePainterController extends ChangeNotifier {
  // ─── public state ──────────────────────────────────────────────────────

  /// Whether paint mode is currently active.
  bool get isActive => _isActive;
  bool _isActive = false;

  /// Current paint mode.
  TilePaintMode get mode => _mode;
  TilePaintMode _mode = TilePaintMode.arbitrary;

  /// Maximum path length in tiles (path mode). Default 10.
  int get maxMoveTiles => _maxMoveTiles;
  int _maxMoveTiles = 10;

  /// Paint overlay colour (default: neon orange).
  Color get paintColor => _paintColor;
  // We store the raw int so that flutter/material is the only import needed.
  int _paintColorValue = 0xFFFF6600;
  Color get _paintColor => Color(_paintColorValue);

  /// Set the paint colour dynamically.
  set paintColor(Color c) {
    if (_paintColorValue != c.value) {
      _paintColorValue = c.value;
      notifyListeners();
    }
  }

  /// Paint overlay opacity.
  double get paintOpacity => _paintOpacity;
  double _paintOpacity = 0.75;

  /// Set of painted tile coordinate keys (`"x:y"`) — all tiles on the polyline (path mode).
  Set<String> get paintedTileKeys => Set.unmodifiable(_paintedTileKeys);
  final Set<String> _paintedTileKeys = {};

  /// Ordered path waypoints (path mode): corners + endpoints only.
  List<IsoCoordinate> get pathCoordinates =>
      List.unmodifiable(_pathCoordinates);
  final List<IsoCoordinate> _pathCoordinates = [];

  /// Number of tiles on the path (path mode: tiles on polyline; arbitrary: painted count).
  int get count => _paintedTileKeys.length;

  // ─── internal stroke tracking ──────────────────────────────────────────

  /// Tiles painted during the current click-drag stroke.  Used to avoid
  /// toggling-off a tile that was just painted in the same gesture.
  final Set<String> _currentStrokeTileKeys = {};

  // ─── lifecycle ─────────────────────────────────────────────────────────

  /// Enter paint mode with the given [mode].
  ///
  /// If [color] is provided, the paint colour is updated; otherwise the
  /// current colour (or default neon orange) is kept.
  ///
  /// If [startingTile] is provided (path mode only), it is automatically
  /// added as the first waypoint. [maxMoveTiles] limits total path length (path mode).
  void activate(
    TilePaintMode mode, {
    Color? color,
    IsoCoordinate? startingTile,
    int maxMoveTiles = 10,
  }) {
    _mode = mode;
    _isActive = true;
    _maxMoveTiles = maxMoveTiles;
    if (color != null) {
      _paintColorValue = color.value;
    }
    _paintedTileKeys.clear();
    _pathCoordinates.clear();
    _currentStrokeTileKeys.clear();

    // Seed the path with the starting tile if provided (path mode).
    if (startingTile != null && mode == TilePaintMode.path) {
      _pathCoordinates.add(startingTile);
      _paintedTileKeys.add(startingTile.key);
    }

    notifyListeners();
  }

  /// Leave paint mode and clear all state.
  void deactivate() {
    _isActive = false;
    _paintedTileKeys.clear();
    _pathCoordinates.clear();
    _currentStrokeTileKeys.clear();
    notifyListeners();
  }

  // ─── stroke management ─────────────────────────────────────────────────

  /// Call at the start of every click-drag gesture.
  void beginStroke() {
    _currentStrokeTileKeys.clear();
  }

  /// Call at the end of every click-drag gesture.
  void endStroke() {
    _currentStrokeTileKeys.clear();
  }

  // ─── painting ──────────────────────────────────────────────────────────

  /// Paint (or unpaint) a tile at [coord].
  ///
  /// In *arbitrary* mode the tile is toggled off if it was painted in a
  /// previous stroke, otherwise it is painted.  In *path* mode the tile is
  /// only accepted if it is in the same row or same column as the last waypoint
  /// and total path length would not exceed [maxMoveTiles].
  ///
  /// [fromTap] when true allows truncating the path when clicking on an
  /// existing path tile (tap-to-delete). When false (e.g. during a drag),
  /// clicking on path tiles does nothing to avoid deleting while painting.
  void paintTile(IsoCoordinate coord, {bool fromTap = false}) {
    if (!_isActive) return;
    final key = coord.key;

    switch (_mode) {
      case TilePaintMode.arbitrary:
        _paintArbitrary(key, coord);
        break;
      case TilePaintMode.path:
        _paintPath(key, coord, fromTap);
        break;
    }
  }

  void _paintArbitrary(String key, IsoCoordinate coord) {
    if (_currentStrokeTileKeys.contains(key)) {
      // Already painted in this stroke – skip to avoid toggling on same drag.
      return;
    }

    if (_paintedTileKeys.contains(key)) {
      // Was painted in a previous stroke → unpaint (toggle off).
      _paintedTileKeys.remove(key);
      _currentStrokeTileKeys.add(key);
      notifyListeners();
    } else {
      // Not painted → paint it.
      _paintedTileKeys.add(key);
      _currentStrokeTileKeys.add(key);
      notifyListeners();
    }
  }

  void _paintPath(String key, IsoCoordinate coord, bool fromTap) {
    // Tap on existing path tile: truncate (remove it and everything after).
    // Only on tap — never during drag, and not when we just added it this stroke.
    if (_paintedTileKeys.contains(key)) {
      if (!fromTap) return; // Drag: don't truncate
      if (_currentStrokeTileKeys.contains(key)) return; // Just added: don't truncate
      _truncatePathAt(coord);
      return;
    }

    if (_pathCoordinates.isEmpty) {
      // First tile – always accepted as first waypoint.
      _pathCoordinates.add(coord);
      _paintedTileKeys.add(key);
      _currentStrokeTileKeys.add(key);
      notifyListeners();
      return;
    }

    final last = _pathCoordinates.last;
    // Same row or same column only (orthogonal).
    final sameRow = coord.y == last.y;
    final sameCol = coord.x == last.x;
    if (!sameRow && !sameCol) return;

    final segmentLen = (coord.x - last.x).abs() + (coord.y - last.y).abs();
    if (segmentLen == 0) return; // same tile

    final currentLength = path_geom.pathLengthTiles(_pathCoordinates);
    if (currentLength + segmentLen > _maxMoveTiles) return;

    _pathCoordinates.add(coord);
    for (final t in path_geom.rasterizeSegment(last, coord)) {
      _paintedTileKeys.add(t.key);
      _currentStrokeTileKeys.add(t.key);
    }
    notifyListeners();
  }

  // ─── utilities ─────────────────────────────────────────────────────────

  /// Truncate the path at [coord]: remove that tile and everything after it.
  /// Used when clicking on an existing path tile to undo painted portions.
  void _truncatePathAt(IsoCoordinate coord) {
    if (_pathCoordinates.isEmpty) return;

    int keepCount = -1;

    // Check if coord is exactly a waypoint
    for (var i = 0; i < _pathCoordinates.length; i++) {
      if (_pathCoordinates[i].samePosition(coord)) {
        keepCount = i;
        break;
      }
    }

    // If not a waypoint, check if coord is on a segment
    if (keepCount < 0) {
      for (var i = 0; i < _pathCoordinates.length - 1; i++) {
        for (final t in path_geom.rasterizeSegment(
          _pathCoordinates[i],
          _pathCoordinates[i + 1],
        )) {
          if (t.samePosition(coord)) {
            keepCount = i + 1;
            break;
          }
        }
        if (keepCount >= 0) break;
      }
    }

    if (keepCount <= 0) {
      clear();
      return;
    }

    _pathCoordinates.removeRange(keepCount, _pathCoordinates.length);
    _rebuildPaintedTileKeysFromPath();
    _currentStrokeTileKeys.clear();
    notifyListeners();
  }

  void _rebuildPaintedTileKeysFromPath() {
    _paintedTileKeys.clear();
    if (_pathCoordinates.isEmpty) return;
    if (_pathCoordinates.length == 1) {
      _paintedTileKeys.add(_pathCoordinates[0].key);
      return;
    }
    for (var i = 0; i < _pathCoordinates.length - 1; i++) {
      for (final t in path_geom.rasterizeSegment(
        _pathCoordinates[i],
        _pathCoordinates[i + 1],
      )) {
        _paintedTileKeys.add(t.key);
      }
    }
  }

  /// Reverse the path direction (path mode only). Swaps gather target and
  /// start; arrows will point the opposite way.
  void flipPathDirection() {
    if (_mode != TilePaintMode.path || _pathCoordinates.length < 2) return;
    final reversed = _pathCoordinates.reversed.toList();
    _pathCoordinates
      ..clear()
      ..addAll(reversed);
    notifyListeners();
  }

  /// Remove all painted tiles (without leaving paint mode).
  void clear() {
    _paintedTileKeys.clear();
    _pathCoordinates.clear();
    _currentStrokeTileKeys.clear();
    notifyListeners();
  }

  /// Return the current selection as a list of coordinates.
  ///
  /// In *path* mode the list preserves order.  In *arbitrary* mode the order
  /// is undefined (set iteration order).
  List<IsoCoordinate> getSelection() {
    if (_mode == TilePaintMode.path) {
      return List.unmodifiable(_pathCoordinates);
    }
    // Arbitrary – parse keys back to coordinates.
    return _paintedTileKeys.map<IsoCoordinate>((key) {
      final parts = key.split(':');
      return IsoCoordinate(x: int.parse(parts[0]), y: int.parse(parts[1]));
    }).toList();
  }
}
