import '../rendering/iso/iso_coordinate.dart';

/// A* pathfinding for isometric tile grid.
///
/// Uses a binary-heap priority queue that correctly handles nodes with
/// equal f-scores (the previous SplayTreeSet silently dropped them).
class Pathfinder {
  final bool allowDiagonal;
  final int maxSearchDepth;

  Pathfinder({this.allowDiagonal = false, this.maxSearchDepth = 200});

  /// Find the shortest path from [start] to [goal].
  ///
  /// [isWalkable] returns true if a tile can be traversed.
  /// The [goal] is always treated as reachable even if [isWalkable] returns
  /// false for it (e.g. structures are obstacles *en route* but valid
  /// destinations).
  /// Returns null if no path exists.
  List<IsoCoordinate>? findPath(
    IsoCoordinate start,
    IsoCoordinate goal,
    bool Function(IsoCoordinate) isWalkable,
  ) {
    if (start.samePosition(goal)) return [start];

    final gScores = <String, double>{};
    final parents = <String, IsoCoordinate>{};
    final closed = <String>{};

    gScores[start.key] = 0;

    final open = _BinaryHeap();
    open.add(_Node(start, 0, _heuristic(start, goal)));

    var explored = 0;

    while (open.isNotEmpty && explored < maxSearchDepth * maxSearchDepth) {
      final current = open.removeFirst();
      explored++;

      if (current.coord.samePosition(goal)) {
        return _reconstructPath(start, goal, parents);
      }

      final currentKey = current.coord.key;
      if (closed.contains(currentKey)) continue;
      closed.add(currentKey);

      for (final neighbor in _getNeighbors(current.coord)) {
        final neighborKey = neighbor.key;
        if (closed.contains(neighborKey)) continue;
        if (!neighbor.samePosition(goal) && !isWalkable(neighbor)) continue;

        final moveCost = _moveCost(current.coord, neighbor);
        final tentativeG = (gScores[currentKey] ?? double.infinity) + moveCost;

        if (tentativeG < (gScores[neighborKey] ?? double.infinity)) {
          gScores[neighborKey] = tentativeG;
          parents[neighborKey] = current.coord;

          final f = tentativeG + _heuristic(neighbor, goal);
          open.add(_Node(neighbor, tentativeG, f));
        }
      }
    }

    return null;
  }

  /// Like [findPath] but returns diagnostic info about why a path failed.
  PathfindDiag findPathDiag(
    IsoCoordinate start,
    IsoCoordinate goal,
    bool Function(IsoCoordinate) isWalkable,
  ) {
    if (start.samePosition(goal)) {
      return PathfindDiag(path: [start], nodesExplored: 0);
    }

    final gScores = <String, double>{};
    final parents = <String, IsoCoordinate>{};
    final closed = <String>{};
    final obstacles = <IsoCoordinate>[];

    gScores[start.key] = 0;
    final open = _BinaryHeap();
    open.add(_Node(start, 0, _heuristic(start, goal)));
    var explored = 0;

    while (open.isNotEmpty && explored < maxSearchDepth * maxSearchDepth) {
      final current = open.removeFirst();
      explored++;

      if (current.coord.samePosition(goal)) {
        return PathfindDiag(
          path: _reconstructPath(start, goal, parents),
          nodesExplored: explored,
          obstacles: obstacles,
        );
      }

      final currentKey = current.coord.key;
      if (closed.contains(currentKey)) continue;
      closed.add(currentKey);

      for (final neighbor in _getNeighbors(current.coord)) {
        final neighborKey = neighbor.key;
        if (closed.contains(neighborKey)) continue;
        if (!neighbor.samePosition(goal) && !isWalkable(neighbor)) {
          if (obstacles.length < 20) obstacles.add(neighbor);
          continue;
        }
        final moveCost = _moveCost(current.coord, neighbor);
        final tentativeG = (gScores[currentKey] ?? double.infinity) + moveCost;
        if (tentativeG < (gScores[neighborKey] ?? double.infinity)) {
          gScores[neighborKey] = tentativeG;
          parents[neighborKey] = current.coord;
          final f = tentativeG + _heuristic(neighbor, goal);
          open.add(_Node(neighbor, tentativeG, f));
        }
      }
    }

    final reason = explored >= maxSearchDepth * maxSearchDepth
        ? 'Search limit reached ($explored nodes explored)'
        : 'No path exists (explored $explored nodes)';
    return PathfindDiag(
      failReason: reason,
      nodesExplored: explored,
      obstacles: obstacles,
    );
  }

  /// Find path excluding the start coordinate from the result.
  List<IsoCoordinate>? findPathExcludingStart(
    IsoCoordinate start,
    IsoCoordinate goal,
    bool Function(IsoCoordinate) isWalkable,
  ) {
    final path = findPath(start, goal, isWalkable);
    if (path == null || path.isEmpty) return null;
    if (path.length == 1) return [];
    return path.sublist(1);
  }

  double _heuristic(IsoCoordinate a, IsoCoordinate b) {
    final dx = (a.x - b.x).abs().toDouble();
    final dy = (a.y - b.y).abs().toDouble();
    if (allowDiagonal) {
      // Octile distance: exact for grids with diagonal movement at cost sqrt(2)
      return dx > dy
          ? 1.414 * dy + (dx - dy)
          : 1.414 * dx + (dy - dx);
    }
    return dx + dy;
  }

  double _moveCost(IsoCoordinate from, IsoCoordinate to) {
    final dx = (from.x - to.x).abs();
    final dy = (from.y - to.y).abs();
    return (dx == 1 && dy == 1) ? 1.414 : 1.0;
  }

  List<IsoCoordinate> _getNeighbors(IsoCoordinate c) {
    final neighbors = <IsoCoordinate>[
      c.copyWith(x: c.x + 1),
      c.copyWith(x: c.x - 1),
      c.copyWith(y: c.y + 1),
      c.copyWith(y: c.y - 1),
    ];
    if (allowDiagonal) {
      neighbors.addAll([
        c.copyWith(x: c.x + 1, y: c.y + 1),
        c.copyWith(x: c.x + 1, y: c.y - 1),
        c.copyWith(x: c.x - 1, y: c.y + 1),
        c.copyWith(x: c.x - 1, y: c.y - 1),
      ]);
    }
    return neighbors;
  }

  List<IsoCoordinate> _reconstructPath(
    IsoCoordinate start,
    IsoCoordinate goal,
    Map<String, IsoCoordinate> parents,
  ) {
    final path = <IsoCoordinate>[goal];
    var current = goal;
    while (!current.samePosition(start)) {
      final parent = parents[current.key];
      if (parent == null) break;
      path.add(parent);
      current = parent;
    }
    return path.reversed.toList();
  }
}

/// A* node.
class _Node {
  final IsoCoordinate coord;
  final double g;
  final double f;
  _Node(this.coord, this.g, this.f);
}

/// Min-heap priority queue that tolerates duplicate f-scores.
class _BinaryHeap {
  final _data = <_Node>[];

  bool get isNotEmpty => _data.isNotEmpty;

  void add(_Node node) {
    _data.add(node);
    _siftUp(_data.length - 1);
  }

  _Node removeFirst() {
    final first = _data.first;
    final last = _data.removeLast();
    if (_data.isNotEmpty) {
      _data[0] = last;
      _siftDown(0);
    }
    return first;
  }

  void _siftUp(int i) {
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_data[i].f < _data[parent].f) {
        _swap(i, parent);
        i = parent;
      } else {
        break;
      }
    }
  }

  void _siftDown(int i) {
    final n = _data.length;
    while (true) {
      var smallest = i;
      final left = 2 * i + 1;
      final right = 2 * i + 2;
      if (left < n && _data[left].f < _data[smallest].f) smallest = left;
      if (right < n && _data[right].f < _data[smallest].f) smallest = right;
      if (smallest == i) break;
      _swap(i, smallest);
      i = smallest;
    }
  }

  void _swap(int a, int b) {
    final tmp = _data[a];
    _data[a] = _data[b];
    _data[b] = tmp;
  }
}

/// Diagnostic result from pathfinding, capturing why a path failed.
class PathfindDiag {
  final List<IsoCoordinate>? path;
  final String? failReason;
  final int nodesExplored;
  final List<IsoCoordinate> obstacles;

  PathfindDiag({
    this.path,
    this.failReason,
    this.nodesExplored = 0,
    this.obstacles = const [],
  });

  bool get succeeded => path != null && path!.isNotEmpty;
}

/// Utility for calculating path statistics.
class PathStats {
  final List<IsoCoordinate> path;
  PathStats(this.path);

  int get length => path.length;
  int get moves => length > 0 ? length - 1 : 0;
  int get turns => moves;
  double get durationSeconds => turns * 0.5;
}
