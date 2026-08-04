import 'dart:collection';
import 'dart:ui';

import 'graph_data.dart';

class GraphLayoutResult {
  const GraphLayoutResult({
    required this.positions,
    required this.levelByNodeId,
    required this.maxLevel,
  });

  final Map<String, Offset> positions;
  final Map<String, int> levelByNodeId;
  final int maxLevel;
}

class GraphLayoutEngine {
  const GraphLayoutEngine({
    this.horizontalGap = 320,
    this.verticalGap = 130,
  });

  final double horizontalGap;
  final double verticalGap;

  GraphLayoutResult layout({
    required GraphSubgraph graph,
    required Map<String, GraphNodeData> nodesById,
  }) {
    if (graph.nodeIds.isEmpty) {
      return const GraphLayoutResult(
        positions: {},
        levelByNodeId: {},
        maxLevel: 0,
      );
    }

    final incomingFromGraph = <String, List<GraphEdgeData>>{};
    for (final edge in graph.edges) {
      incomingFromGraph
          .putIfAbsent(edge.targetId, () => <GraphEdgeData>[])
          .add(edge);
    }

    final distanceFromRoot = <String, int>{graph.rootId: 0};
    final queue = Queue<String>()..add(graph.rootId);

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      final currentDistance = distanceFromRoot[current] ?? 0;
      final deps = incomingFromGraph[current] ?? const <GraphEdgeData>[];
      for (final edge in deps) {
        final source = edge.sourceId;
        if (!graph.nodeIds.contains(source)) continue;
        final nextDistance = currentDistance + 1;
        final previous = distanceFromRoot[source];
        if (previous == null || nextDistance > previous) {
          distanceFromRoot[source] = nextDistance;
          queue.add(source);
        }
      }
    }

    var maxDistance = 0;
    for (final dist in distanceFromRoot.values) {
      if (dist > maxDistance) maxDistance = dist;
    }

    final levelByNodeId = <String, int>{};
    for (final id in graph.nodeIds) {
      final dist = distanceFromRoot[id] ?? 0;
      levelByNodeId[id] = maxDistance - dist;
    }

    final byLevel = <int, List<String>>{};
    for (final entry in levelByNodeId.entries) {
      byLevel.putIfAbsent(entry.value, () => <String>[]).add(entry.key);
    }

    var maxCount = 0;
    for (final ids in byLevel.values) {
      if (ids.length > maxCount) maxCount = ids.length;
    }
    final positions = <String, Offset>{};

    byLevel.forEach((level, ids) {
      ids.sort((a, b) {
        final aLabel = nodesById[a]?.label ?? a;
        final bLabel = nodesById[b]?.label ?? b;
        return aLabel.toLowerCase().compareTo(bLabel.toLowerCase());
      });
      final layerHeight = (ids.length - 1) * verticalGap;
      final canvasHeight = (maxCount - 1) * verticalGap;
      final topOffset = (canvasHeight - layerHeight) / 2;
      for (var i = 0; i < ids.length; i++) {
        positions[ids[i]] =
            Offset(level * horizontalGap, topOffset + i * verticalGap);
      }
    });

    return GraphLayoutResult(
      positions: positions,
      levelByNodeId: levelByNodeId,
      maxLevel: maxDistance,
    );
  }
}
