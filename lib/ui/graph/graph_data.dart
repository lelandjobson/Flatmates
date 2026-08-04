import 'dart:collection';

import 'package:flutter/material.dart';

class GraphNodeData {
  const GraphNodeData({
    required this.id,
    required this.label,
    this.category,
    this.thumbnailUrl,
    this.color,
    this.hasChildren = false,
    this.metadata,
  });

  final String id;
  final String label;
  final String? category;
  final String? thumbnailUrl;
  final Color? color;
  final bool hasChildren;
  final Map<String, dynamic>? metadata;
}

class GraphEdgeData {
  const GraphEdgeData({
    required this.sourceId,
    required this.targetId,
    this.amount = 1,
    this.label,
  });

  final String sourceId;
  final String targetId;
  final int amount;
  final String? label;
}

class GraphSubgraph {
  const GraphSubgraph({
    required this.rootId,
    required this.nodeIds,
    required this.edges,
  });

  final String rootId;
  final Set<String> nodeIds;
  final List<GraphEdgeData> edges;
}

class GraphData {
  GraphData({
    required Map<String, GraphNodeData> nodesById,
    required Map<String, List<GraphEdgeData>> incomingByNode,
    required Map<String, List<GraphEdgeData>> outgoingByNode,
  })  : _nodesById = nodesById,
        _incomingByNode = incomingByNode,
        _outgoingByNode = outgoingByNode;

  final Map<String, GraphNodeData> _nodesById;
  final Map<String, List<GraphEdgeData>> _incomingByNode;
  final Map<String, List<GraphEdgeData>> _outgoingByNode;

  Map<String, GraphNodeData> get nodesById => _nodesById;
  Map<String, List<GraphEdgeData>> get incomingByNode => _incomingByNode;
  Map<String, List<GraphEdgeData>> get outgoingByNode => _outgoingByNode;

  GraphNodeData? nodeById(String id) => _nodesById[id];

  List<GraphEdgeData> incomingEdges(String nodeId) =>
      _incomingByNode[nodeId] ?? const [];

  List<GraphEdgeData> outgoingEdges(String nodeId) =>
      _outgoingByNode[nodeId] ?? const [];

  /// Builds a subgraph rooted at [rootId], traversing incoming edges up to
  /// [maxDepth] levels deep. A depth of 1 returns only immediate predecessors.
  GraphSubgraph subgraph(String rootId, {int maxDepth = 1, int maxNodes = 250}) {
    if (!_nodesById.containsKey(rootId)) {
      return GraphSubgraph(rootId: rootId, nodeIds: {}, edges: const []);
    }

    final visited = <String>{rootId};
    final stack = <String>[rootId];
    final edges = <GraphEdgeData>[];
    final seenEdgeKeys = <String>{};
    final depth = <String, int>{rootId: 0};

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final currentDepth = depth[current] ?? 0;
      if (currentDepth >= maxDepth) continue;
      for (final edge in incomingEdges(current)) {
        if (!_nodesById.containsKey(edge.sourceId)) continue;
        final key = '${edge.sourceId}->${edge.targetId}:${edge.amount}';
        if (seenEdgeKeys.add(key)) edges.add(edge);
        if (visited.length >= maxNodes) continue;
        if (visited.add(edge.sourceId)) {
          depth[edge.sourceId] = currentDepth + 1;
          stack.add(edge.sourceId);
        }
      }
    }

    return GraphSubgraph(rootId: rootId, nodeIds: visited, edges: edges);
  }

  /// Builds a full subgraph (unlimited depth) from [rootId].
  GraphSubgraph fullSubgraph(String rootId, {int maxNodes = 500}) {
    if (!_nodesById.containsKey(rootId)) {
      return GraphSubgraph(rootId: rootId, nodeIds: {}, edges: const []);
    }

    final visited = <String>{rootId};
    final queue = Queue<String>()..add(rootId);
    final edges = <GraphEdgeData>[];
    final seenEdgeKeys = <String>{};

    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      for (final edge in incomingEdges(current)) {
        final key = '${edge.sourceId}->${edge.targetId}:${edge.amount}';
        if (seenEdgeKeys.add(key)) edges.add(edge);
        if (!_nodesById.containsKey(edge.sourceId)) continue;
        if (visited.length >= maxNodes) continue;
        if (visited.add(edge.sourceId)) {
          queue.add(edge.sourceId);
        }
      }
    }

    return GraphSubgraph(rootId: rootId, nodeIds: visited, edges: edges);
  }
}
