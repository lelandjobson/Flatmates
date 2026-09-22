import '../graph/connection_graph.dart';
import '../paths/path_store.dart';
import '../spawns/basement_spawn.dart';
import '../volumes/volume.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_regions.dart';
import '../walls/wall_store.dart';
import 'day_action_store.dart';
import 'flatmate_range.dart';

/// Day routes on [ConnectionGraph]: outdoor paths, subgraphs, and anchors.
class DayRouter {
  DayRouter({this.maxSearchDepth = 200});

  final int maxSearchDepth;

  bool canProgramAction({
    required (int, int) tile,
    required (int, int) home,
    required PathStore paths,
  }) {
    if (!inFlatmateRange(tile, home)) return false;
    return isPathAdjacent(tile: tile, isPath: paths.contains);
  }

  List<(int, int)>? findHop({
    required (int, int) start,
    required (int, int) goal,
    required VolumeGrid grid,
    required VolumeStore volumes,
    required PathStore paths,
    WallStore? walls,
    List<Playground>? regions,
    ConnectionGraph? graph,
    bool goalNeedsPath = true,
  }) {
    if (start == goal) return [start];
    if (goalNeedsPath && !isPathAdjacent(tile: goal, isPath: paths.contains)) {
      return null;
    }
    return _search(
      start: start,
      goal: goal,
      grid: grid,
      volumes: volumes,
      paths: paths,
      walls: walls,
      graph: graph ??
          ConnectionGraph.build(
            volumes: volumes,
            paths: paths,
            walls: walls,
            regions: regions ?? const [],
          ),
    );
  }

  void compute(
    FlatmateDayPlan plan, {
    required (int, int)? home,
    required VolumeGrid grid,
    required VolumeStore volumes,
    required PathStore paths,
    WallStore? walls,
    List<Playground>? regions,
    ConnectionGraph? graph,
  }) {
    if (home != null) plan.bindHome(home);
    final resolvedHome = plan.homeTile;
    plan.firstBrokenHop = null;
    for (var i = 0; i < plan.hops.length; i++) {
      plan.hops[i] = null;
    }
    if (resolvedHome == null) {
      plan.firstBrokenHop = 0;
      return;
    }

    final resolved = graph ??
        ConnectionGraph.build(
          volumes: volumes,
          paths: paths,
          walls: walls,
          regions: regions ?? const [],
        );

    var from = resolvedHome;
    for (var i = 0; i < plan.slots.length; i++) {
      final slot = plan.slots[i];
      if (slot.isEmpty) continue;
      final goal = slot.tile;
      if (goal == null) {
        plan.firstBrokenHop = i;
        return;
      }
      if (!slot.locked) {
        if (!inFlatmateRange(goal, resolvedHome) ||
            !isPathAdjacent(tile: goal, isPath: paths.contains)) {
          plan.firstBrokenHop = i;
          return;
        }
      }
      final hop = findHop(
        start: from,
        goal: goal,
        grid: grid,
        volumes: volumes,
        paths: paths,
        walls: walls,
        regions: regions,
        graph: resolved,
        goalNeedsPath: !slot.locked,
      );
      plan.hops[i] = hop;
      if (hop == null) {
        plan.firstBrokenHop = i;
        return;
      }
      from = goal;
    }
  }

  List<(int, int)>? _search({
    required (int, int) start,
    required (int, int) goal,
    required VolumeGrid grid,
    required VolumeStore volumes,
    required PathStore paths,
    required WallStore? walls,
    required ConnectionGraph graph,
  }) {
    if (!grid.inBounds(start.$1, start.$2) ||
        !grid.inBounds(goal.$1, goal.$2)) {
      return null;
    }
    if (BasementSpawn.blocksWalk(start.$1, start.$2) ||
        BasementSpawn.blocksWalk(goal.$1, goal.$2)) {
      return null;
    }

    final adj = graph.nodeAdjacency();
    final parents = <(int, int), (int, int)>{};
    final seen = {start};
    final queue = [start];
    var explored = 0;
    final limit = maxSearchDepth * maxSearchDepth;

    bool walkable((int, int) from, (int, int) to) {
      if (!grid.inBounds(to.$1, to.$2)) return false;
      if (BasementSpawn.blocksWalk(to.$1, to.$2)) return false;
      if (walls != null && walls.blocksWalk(from, to)) return false;
      return true;
    }

    while (queue.isNotEmpty && explored < limit) {
      final current = queue.removeAt(0);
      explored++;
      if (current == goal) {
        return _reconstruct(start: start, goal: goal, parents: parents);
      }
      for (final next in _neighbors(
        tile: current,
        goal: goal,
        volumes: volumes,
        paths: paths,
        adj: adj,
        graph: graph,
        walkable: walkable,
      )) {
        if (!seen.add(next)) continue;
        parents[next] = current;
        queue.add(next);
      }
    }
    return null;
  }

  Iterable<(int, int)> _neighbors({
    required (int, int) tile,
    required (int, int) goal,
    required VolumeStore volumes,
    required PathStore paths,
    required Map<GraphNode, Set<GraphNode>> adj,
    required ConnectionGraph graph,
    required bool Function((int, int) from, (int, int) to) walkable,
  }) sync* {
    final node = graph.tileNode(tile.$1, tile.$2);
    if (node != null) {
      for (final next in adj[node] ?? const <GraphNode>{}) {
        final dest = (next.x, next.y);
        if (walkable(tile, dest)) yield dest;
      }
    }

    final indoor = volumes.occupant(tile.$1, tile.$2) != null;
    if (indoor) return;
    if (!paths.contains(tile.$1, tile.$2)) {
      for (final next in _ortho(tile)) {
        if (!paths.contains(next.$1, next.$2)) continue;
        if (walkable(tile, next)) yield next;
      }
    }

    if (goal == tile || !_isOrtho(tile, goal)) return;
    if (!walkable(tile, goal)) return;
    if (volumes.occupant(goal.$1, goal.$2) != null) return;
    final fromPath = paths.contains(tile.$1, tile.$2);
    final fromGraph = node != null;
    if (!fromPath && !fromGraph) return;
    yield goal;
  }

  static List<(int, int)>? _reconstruct({
    required (int, int) start,
    required (int, int) goal,
    required Map<(int, int), (int, int)> parents,
  }) {
    final tiles = <(int, int)>[goal];
    var cursor = goal;
    while (cursor != start) {
      final parent = parents[cursor];
      if (parent == null) return [start];
      tiles.add(parent);
      cursor = parent;
    }
    return tiles.reversed.toList();
  }

  static Iterable<(int, int)> _ortho((int, int) tile) sync* {
    yield (tile.$1 + 1, tile.$2);
    yield (tile.$1 - 1, tile.$2);
    yield (tile.$1, tile.$2 + 1);
    yield (tile.$1, tile.$2 - 1);
  }

  static bool _isOrtho((int, int) a, (int, int) b) {
    final dx = (a.$1 - b.$1).abs();
    final dy = (a.$2 - b.$2).abs();
    return dx + dy == 1;
  }
}
