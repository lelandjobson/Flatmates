import '../graph/connection_graph.dart';
import '../paths/path_store.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_store.dart';

/// Travel-time A* on the GameView tile grid.
///
/// Drawn [PathStore] tiles cost [pathCost] (50% faster than ground), so the
/// search prefers corridors when they are actually quicker.
class FlatmatePathfinder {
  FlatmatePathfinder({this.maxSearchDepth = 200});

  static const double pathSpeedMultiplier = 1.5;
  static const double groundCost = 1.0;
  static const double pathCost = groundCost / pathSpeedMultiplier;

  final int maxSearchDepth;

  List<(int, int)>? findPath({
    required (int, int) start,
    required (int, int) goal,
    required VolumeGrid grid,
    required bool Function(int tx, int ty) isWalkable,
    required bool Function(int tx, int ty) isPath,
    bool Function((int, int) from, (int, int) to)? blockedEdge,
  }) {
    if (start == goal) return [start];
    if (!grid.inBounds(start.$1, start.$2) ||
        !grid.inBounds(goal.$1, goal.$2)) {
      return null;
    }

    final gScores = <(int, int), double>{start: 0};
    final parents = <(int, int), (int, int)>{};
    final closed = <(int, int)>{};
    final open = _Heap()
      ..add(_Node(start, 0, _heuristic(start, goal)));

    var explored = 0;
    final limit = maxSearchDepth * maxSearchDepth;

    while (open.isNotEmpty && explored < limit) {
      final current = open.removeFirst();
      explored++;
      if (closed.contains(current.tile)) continue;
      closed.add(current.tile);

      if (current.tile == goal) {
        return _reconstruct(start, goal, parents);
      }

      for (final next in _neighbors(current.tile)) {
        if (closed.contains(next)) continue;
        if (!grid.inBounds(next.$1, next.$2)) continue;
        if (next != goal && !isWalkable(next.$1, next.$2)) continue;
        if (next == goal && !isWalkable(next.$1, next.$2)) continue;
        if (blockedEdge?.call(current.tile, next) ?? false) continue;

        final step = isPath(next.$1, next.$2) ? pathCost : groundCost;
        final tentative = (gScores[current.tile] ?? double.infinity) + step;
        if (tentative < (gScores[next] ?? double.infinity)) {
          gScores[next] = tentative;
          parents[next] = current.tile;
          open.add(_Node(next, tentative, tentative + _heuristic(next, goal)));
        }
      }
    }
    return null;
  }

  /// Outdoor tiles plus volume interiors, entered only through doors.
  List<(int, int)>? findOnMap({
    required (int, int) start,
    required (int, int) goal,
    required VolumeGrid grid,
    required VolumeStore volumes,
    required PathStore paths,
    WallStore? walls,
  }) {
    final doors = doorSteps(volumes);
    return findPath(
      start: start,
      goal: goal,
      grid: grid,
      isWalkable: (tx, ty) => grid.inBounds(tx, ty),
      isPath: paths.contains,
      blockedEdge: (from, to) {
        if (walls != null && walls.separatesTiles(from, to)) return true;
        return !canTraverseVolume(volumes, from, to, doors: doors);
      },
    );
  }

  /// Outdoor ↔ volume steps that have an [InOutLink] door.
  static Set<((int, int), (int, int))> doorSteps(VolumeStore volumes) {
    final steps = <((int, int), (int, int))>{};
    for (final link in ConnectionGraph.inOutLinks(volumes)) {
      final inside = (link.cell.tx, link.cell.ty);
      final outside = (link.outTx, link.outTy);
      steps.add(_undirected(inside, outside));
    }
    return steps;
  }

  /// True when [from]→[to] is a legal outdoor, in-volume, or door step.
  static bool canTraverseVolume(
    VolumeStore volumes,
    (int, int) from,
    (int, int) to, {
    Set<((int, int), (int, int))>? doors,
  }) {
    final fromId = volumes.occupant(from.$1, from.$2);
    final toId = volumes.occupant(to.$1, to.$2);
    if (fromId == null && toId == null) return true;
    if (fromId != null && fromId == toId) return true;
    if (fromId != null && toId != null) return false;
    return (doors ?? doorSteps(volumes)).contains(_undirected(from, to));
  }

  static ((int, int), (int, int)) _undirected((int, int) a, (int, int) b) {
    if (a.$1 < b.$1 || (a.$1 == b.$1 && a.$2 <= b.$2)) return (a, b);
    return (b, a);
  }

  static double _heuristic((int, int) a, (int, int) b) {
    final dx = (a.$1 - b.$1).abs();
    final dy = (a.$2 - b.$2).abs();
    return (dx + dy) * pathCost;
  }

  static Iterable<(int, int)> _neighbors((int, int) tile) sync* {
    yield (tile.$1 + 1, tile.$2);
    yield (tile.$1 - 1, tile.$2);
    yield (tile.$1, tile.$2 + 1);
    yield (tile.$1, tile.$2 - 1);
  }

  static List<(int, int)> _reconstruct(
    (int, int) start,
    (int, int) goal,
    Map<(int, int), (int, int)> parents,
  ) {
    final path = <(int, int)>[goal];
    var cursor = goal;
    while (cursor != start) {
      final parent = parents[cursor];
      if (parent == null) return [start];
      path.add(parent);
      cursor = parent;
    }
    return path.reversed.toList();
  }
}

class _Node {
  _Node(this.tile, this.g, this.f);
  final (int, int) tile;
  final double g;
  final double f;
}

class _Heap {
  final List<_Node> _items = [];

  bool get isNotEmpty => _items.isNotEmpty;

  void add(_Node node) {
    _items.add(node);
    var i = _items.length - 1;
    while (i > 0) {
      final parent = (i - 1) >> 1;
      if (_items[parent].f <= _items[i].f) break;
      final tmp = _items[parent];
      _items[parent] = _items[i];
      _items[i] = tmp;
      i = parent;
    }
  }

  _Node removeFirst() {
    final first = _items.first;
    final last = _items.removeLast();
    if (_items.isEmpty) return first;
    _items[0] = last;
    var i = 0;
    while (true) {
      final left = i * 2 + 1;
      final right = left + 1;
      var smallest = i;
      if (left < _items.length && _items[left].f < _items[smallest].f) {
        smallest = left;
      }
      if (right < _items.length && _items[right].f < _items[smallest].f) {
        smallest = right;
      }
      if (smallest == i) break;
      final tmp = _items[i];
      _items[i] = _items[smallest];
      _items[smallest] = tmp;
      i = smallest;
    }
    return first;
  }
}
