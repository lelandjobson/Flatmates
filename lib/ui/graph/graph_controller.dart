import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'graph_data.dart';
import 'graph_layout_engine.dart';
import 'graph_theme.dart';

enum GraphViewMode { focus, all }

class GraphViewController extends ChangeNotifier {
  GraphViewController({
    this.theme = GraphViewTheme.dark,
  });

  final GraphViewTheme theme;

  GraphData? _data;
  String? _rootId;
  String? _selectedNodeId;
  final Set<String> _expandedNodeIds = {};
  GraphViewMode _viewMode = GraphViewMode.focus;

  /// Cached layout for the base (1-level) subgraph in focus mode.
  String? _cachedBaseRootId;
  Map<String, Offset>? _cachedBasePositions;

  /// Exiting nodes: id -> position at time of removal.
  Map<String, Offset> exitingNodes = const {};

  /// Maps synthetic IDs (e.g. "parentId/childId") back to original node IDs
  /// when a child appears under multiple parents in the expanded view.
  Map<String, String> _syntheticToOriginal = const {};

  GraphData? get data => _data;
  String? get rootId => _rootId;
  String? get selectedNodeId => _selectedNodeId;
  Set<String> get expandedNodeIds => _expandedNodeIds;
  GraphViewMode get viewMode => _viewMode;
  bool get isFocusMode => _viewMode == GraphViewMode.focus;
  bool get isAllMode => _viewMode == GraphViewMode.all;

  /// Resolves a node ID (possibly synthetic) to its [GraphNodeData].
  GraphNodeData? resolveNode(String id) {
    final originalId = _syntheticToOriginal[id] ?? id;
    return _data?.nodeById(originalId);
  }

  void setData(GraphData data) {
    if (identical(_data, data)) return;
    _data = data;
    notifyListeners();
  }

  void setRoot(String id) {
    if (_rootId == id) return;
    _rootId = id;
    _selectedNodeId = null;
    _expandedNodeIds.clear();
    _cachedBaseRootId = null;
    _cachedBasePositions = null;
    exitingNodes = {};
    notifyListeners();
  }

  void select(String id) {
    if (_selectedNodeId == id) return;
    _selectedNodeId = id;
    notifyListeners();
  }

  void deselect() {
    if (_selectedNodeId == null) return;
    _selectedNodeId = null;
    notifyListeners();
  }

  void toggleSelect(String id) {
    _selectedNodeId = _selectedNodeId == id ? null : id;
    notifyListeners();
  }

  void expand(String id, Map<String, Offset> currentPositions) {
    if (id == _rootId) return;
    final data = _data;
    if (data == null || !isFocusMode) return;
    final node = data.nodeById(id);
    if (node == null || !node.hasChildren) return;

    _expandedNodeIds.add(id);
    exitingNodes = {};
    notifyListeners();
  }

  void collapse(String id, Map<String, Offset> currentPositions) {
    if (!_expandedNodeIds.contains(id)) return;
    final data = _data;
    if (data == null) return;

    final baseGraph = _currentBaseGraph();
    if (baseGraph == null) return;

    final childGraph = data.subgraph(id, maxDepth: 1);
    final removedChildren = childGraph.nodeIds.difference(baseGraph.nodeIds);

    // Also remove any deeper expansions within this subtree
    final descendantsToRemove = <String>{};
    for (final eid in _expandedNodeIds) {
      if (eid == id) continue;
      if (_depthOf(eid, id) != null) descendantsToRemove.add(eid);
    }

    final exitPositions = <String, Offset>{};
    for (final cid in removedChildren) {
      final pos = currentPositions[cid];
      if (pos != null) exitPositions[cid] = pos;
    }

    _expandedNodeIds.remove(id);
    _expandedNodeIds.removeAll(descendantsToRemove);
    exitingNodes = exitPositions;
    notifyListeners();
  }

  void toggleExpand(String id, Map<String, Offset> currentPositions) {
    smartToggle(id, currentPositions);
  }

  /// Context-aware expand/collapse that works one level at a time.
  ///
  /// - If any descendants of [id] are expanded, collapses only the deepest
  ///   expanded level within that subtree.
  /// - If [id] itself is expanded but has no expanded descendants, collapses it.
  /// - If [id] is not expanded, expands it (showing its children).
  /// - For root: only collapses descendant expansions (base graph is always
  ///   visible).
  void smartToggle(String id, Map<String, Offset> currentPositions) {
    final resolvedId = _syntheticToOriginal[id] ?? id;
    final data = _data;
    if (data == null || !isFocusMode) return;
    final node = data.nodeById(resolvedId);
    if (node == null || !node.hasChildren) return;

    // Find expanded descendants of this node and their depths
    final descendantDepths = <String, int>{};
    for (final eid in _expandedNodeIds) {
      if (eid == resolvedId) continue;
      final depth = _depthOf(eid, resolvedId);
      if (depth != null && depth > 0) {
        descendantDepths[eid] = depth;
      }
    }

    if (descendantDepths.isNotEmpty) {
      // Collapse only the deepest expanded descendants (one level at a time)
      final maxDepth = descendantDepths.values.reduce(math.max);
      final toCollapse = descendantDepths.entries
          .where((e) => e.value == maxDepth)
          .map((e) => e.key)
          .toSet();

      final baseGraph = _currentBaseGraph();
      final exitPositions = <String, Offset>{};
      if (baseGraph != null) {
        for (final collapseId in toCollapse) {
          final childGraph = data.subgraph(collapseId, maxDepth: 1);
          for (final cid in childGraph.nodeIds) {
            if (cid == collapseId) continue;
            if (baseGraph.nodeIds.contains(cid)) continue;
            final pos = currentPositions[cid] ??
                currentPositions['$collapseId/$cid'];
            if (pos != null) exitPositions[cid] = pos;
          }
        }
      }

      _expandedNodeIds.removeAll(toCollapse);
      exitingNodes = exitPositions;
      notifyListeners();
    } else if (_expandedNodeIds.contains(resolvedId)) {
      collapse(resolvedId, currentPositions);
    } else if (resolvedId != _rootId) {
      expand(resolvedId, currentPositions);
    }
  }

  /// Returns the graph depth from [ancestor] to [descendant], or null if
  /// [descendant] is not reachable from [ancestor] via incoming edges.
  int? _depthOf(String descendant, String ancestor) {
    if (descendant == ancestor) return 0;
    final data = _data;
    if (data == null) return null;

    final queue = <(String, int)>[(ancestor, 0)];
    final visited = <String>{ancestor};
    var qi = 0;

    while (qi < queue.length) {
      final (current, depth) = queue[qi++];
      for (final edge in data.incomingEdges(current)) {
        if (edge.sourceId == descendant) return depth + 1;
        if (visited.add(edge.sourceId)) {
          queue.add((edge.sourceId, depth + 1));
        }
      }
    }
    return null;
  }

  void clearExitingNodes() {
    if (exitingNodes.isEmpty) return;
    exitingNodes = {};
    notifyListeners();
  }

  /// Restore expanded node IDs without animation (for session restore).
  void restoreExpandedIds(Set<String> ids) {
    _expandedNodeIds
      ..clear()
      ..addAll(ids);
    notifyListeners();
  }

  void setMode(GraphViewMode mode) {
    if (_viewMode == mode) return;
    _viewMode = mode;
    _expandedNodeIds.clear();
    _selectedNodeId = null;
    exitingNodes = {};
    notifyListeners();
  }

  bool isExpanded(String id) => _expandedNodeIds.contains(id);
  bool isSelected(String id) => _selectedNodeId == id;

  GraphSubgraph? _currentBaseGraph() {
    final root = _rootId;
    final data = _data;
    if (root == null || data == null) return null;
    return data.subgraph(root, maxDepth: 1);
  }

  /// Builds the visible graph and positions based on current state.
  ({
    GraphSubgraph graph,
    Map<String, Offset> positions,
    Set<String> dimmedNodeIds,
  })? buildVisibleGraph() {
    final root = _rootId;
    final data = _data;
    if (root == null || data == null) return null;

    if (root != _cachedBaseRootId) {
      _cachedBaseRootId = null;
      _cachedBasePositions = null;
    }

    final engine = GraphLayoutEngine(
      horizontalGap: theme.horizontalGap,
      verticalGap: theme.verticalGap,
    );

    if (isAllMode) {
      _syntheticToOriginal = const {};
      final graph = data.fullSubgraph(root);
      if (graph.nodeIds.isEmpty) return null;
      final layout = engine.layout(graph: graph, nodesById: data.nodesById);
      final positions = _shiftPositions(layout.positions);
      return (graph: graph, positions: positions, dimmedNodeIds: <String>{});
    }

    final baseGraph = data.subgraph(root, maxDepth: 1);
    if (baseGraph.nodeIds.isEmpty) return null;

    final rootDirectChildren = {
      for (final e in baseGraph.edges)
        if (e.targetId == root) e.sourceId,
    };

    if (_expandedNodeIds.isEmpty) {
      _syntheticToOriginal = const {};
      final layout =
          engine.layout(graph: baseGraph, nodesById: data.nodesById);
      final positions = _shiftPositions(layout.positions);
      _cachedBaseRootId = root;
      _cachedBasePositions = Map.from(positions);
      return (graph: baseGraph, positions: positions, dimmedNodeIds: <String>{});
    }

    // Cache base positions if needed.
    if (_cachedBaseRootId != root || _cachedBasePositions == null) {
      final layout =
          engine.layout(graph: baseGraph, nodesById: data.nodesById);
      final positions = _shiftPositions(layout.positions);
      _cachedBaseRootId = root;
      _cachedBasePositions = Map.from(positions);
    }

    final positions = Map<String, Offset>.from(_cachedBasePositions!);

    var mergedNodeIds = Set<String>.from(baseGraph.nodeIds);
    var mergedEdges = List<GraphEdgeData>.from(baseGraph.edges);
    final syntheticMap = <String, String>{};

    // Process expanded nodes level by level (BFS) so that multi-level
    // expansions are built outward from the base graph.
    final expandQueue = <String>[
      for (final eid in _expandedNodeIds)
        if (baseGraph.nodeIds.contains(eid)) eid,
    ];
    final processedExpanded = <String>{};
    var qi = 0;

    while (qi < expandQueue.length) {
      final expandedId = expandQueue[qi++];
      if (!processedExpanded.add(expandedId)) continue;

      final expandedPos = positions[expandedId];
      if (expandedPos == null) continue;

      final childGraph = data.subgraph(expandedId, maxDepth: 1);
      final childEdges = childGraph.edges
          .where((e) => e.targetId == expandedId)
          .toList();
      final childIds = childEdges.map((e) => e.sourceId).toSet().toList();
      childIds.sort((a, b) {
        final aLabel = data.nodeById(a)?.label ?? a;
        final bLabel = data.nodeById(b)?.label ?? b;
        return aLabel.toLowerCase().compareTo(bLabel.toLowerCase());
      });

      final idMap = <String, String>{};
      for (var i = 0; i < childIds.length; i++) {
        final originalId = childIds[i];
        final String nodeId;
        if (mergedNodeIds.contains(originalId)) {
          nodeId = '$expandedId/$originalId';
          syntheticMap[nodeId] = originalId;
        } else {
          nodeId = originalId;
        }
        idMap[originalId] = nodeId;
        positions[nodeId] = Offset(
          expandedPos.dx - theme.horizontalGap,
          expandedPos.dy +
              (i - (childIds.length - 1) / 2) * theme.verticalGap,
        );
        mergedNodeIds.add(nodeId);
      }

      for (final edge in childEdges) {
        final nodeId = idMap[edge.sourceId];
        if (nodeId == null) continue;
        mergedEdges.add(GraphEdgeData(
          sourceId: nodeId,
          targetId: expandedId,
          amount: edge.amount,
        ));
      }

      // Queue any newly visible children that are themselves expanded
      for (final originalId in childIds) {
        if (_expandedNodeIds.contains(originalId) &&
            !processedExpanded.contains(originalId)) {
          final nodeId = idMap[originalId]!;
          if (nodeId != originalId) {
            positions[originalId] = positions[nodeId]!;
          }
          expandQueue.add(originalId);
        }
      }
    }

    _syntheticToOriginal = syntheticMap;

    final dimmedNodeIds = <String>{};
    if (_expandedNodeIds.isNotEmpty) {
      dimmedNodeIds.add(root);
      for (final childId in rootDirectChildren) {
        if (!_expandedNodeIds.contains(childId)) {
          dimmedNodeIds.add(childId);
        }
      }
    }

    final graph = GraphSubgraph(
      rootId: root,
      nodeIds: mergedNodeIds,
      edges: mergedEdges,
    );
    return (graph: graph, positions: positions, dimmedNodeIds: dimmedNodeIds);
  }

  /// Computes a zoom-to-fit matrix for all nodes present in [positions].
  Matrix4? zoomToFitMatrix({
    required String nodeId,
    required Map<String, Offset> positions,
    required Size viewportSize,
  }) {
    if (positions.isEmpty) return null;

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (final pos in positions.values) {
      if (pos.dx < minX) minX = pos.dx;
      if (pos.dy < minY) minY = pos.dy;
      if (pos.dx + theme.nodeWidth > maxX) maxX = pos.dx + theme.nodeWidth;
      if (pos.dy + theme.nodeHeight > maxY) maxY = pos.dy + theme.nodeHeight;
    }

    if (minX == double.infinity) return null;

    const padding = 60.0;
    minX -= padding;
    minY -= padding;
    maxX += padding;
    maxY += padding;

    final contentWidth = maxX - minX;
    final contentHeight = maxY - minY;
    if (contentWidth <= 0 || contentHeight <= 0) return null;

    final scaleX = viewportSize.width / contentWidth;
    final scaleY = viewportSize.height / contentHeight;
    final scale = math.min(scaleX, scaleY).clamp(theme.minScale, 1.0);

    final centerX = (minX + maxX) / 2;
    final centerY = (minY + maxY) / 2;

    final tx = viewportSize.width / 2 - centerX * scale;
    final ty = viewportSize.height / 2 - centerY * scale;

    return Matrix4(
      scale, 0, 0, 0,
      0, scale, 0, 0,
      0, 0, 1, 0,
      tx, ty, 0, 1,
    );
  }

  Map<String, Offset> _shiftPositions(Map<String, Offset> source) {
    if (source.isEmpty) return const {};
    var minX = double.infinity;
    var minY = double.infinity;
    for (final p in source.values) {
      if (p.dx < minX) minX = p.dx;
      if (p.dy < minY) minY = p.dy;
    }
    final shift = Offset(theme.canvasPadding - minX, theme.canvasPadding - minY);
    return {
      for (final entry in source.entries) entry.key: entry.value + shift,
    };
  }
}
