import '../ui/graph/graph_data.dart';
import 'craft_tree_index.dart';
import 'crafts_tech_provider.dart';

/// Converts [CraftsTechProvider] data into a generic [GraphData] suitable for
/// the graph view, filtering out tech/achievement nodes, collapsing output
/// nodes (e.g. final-apartment -> fm-apartment), and setting [hasChildren].
class CraftGraphAdapter {
  CraftGraphAdapter._();

  static GraphData fromProvider(CraftsTechProvider provider) {
    final treeNodes = provider.treeNodesById;
    final treeIncoming = provider.incomingDepsByNode;

    final nodesById = <String, GraphNodeData>{};
    final incomingByNode = <String, List<GraphEdgeData>>{};
    final outgoingByNode = <String, List<GraphEdgeData>>{};

    bool isCraftOrIngredient(String id) {
      final node = treeNodes[id];
      if (node == null) return false;
      return node.type == CraftTreeNodeType.craft ||
          node.type == CraftTreeNodeType.ingredient;
    }

    // Collect nodes that need output-node collapsing.
    // For a craft like fm-apartment whose only incoming edge is from
    // final-apartment, we redirect the real ingredient edges to fm-apartment.
    final collapsedOutputs = <String, String>{};
    for (final craft in provider.crafts) {
      final outputNode = craft.displayNode;
      if (outputNode == null || outputNode.id == craft.id) continue;
      if (!treeNodes.containsKey(outputNode.id)) continue;
      final incomingToRoot = treeIncoming[craft.id] ?? const [];
      if (incomingToRoot.length == 1 &&
          incomingToRoot.single.sourceId == outputNode.id) {
        collapsedOutputs[outputNode.id] = craft.id;
      }
    }

    void addEdge(GraphEdgeData edge) {
      outgoingByNode
          .putIfAbsent(edge.sourceId, () => <GraphEdgeData>[])
          .add(edge);
      incomingByNode
          .putIfAbsent(edge.targetId, () => <GraphEdgeData>[])
          .add(edge);
    }

    // Build nodes (craft + ingredient only).
    for (final entry in treeNodes.entries) {
      if (!isCraftOrIngredient(entry.key)) continue;
      if (collapsedOutputs.containsKey(entry.key)) continue;

      final treeNode = entry.value;
      final category = _categoryLabel(treeNode.type);

      nodesById[entry.key] = GraphNodeData(
        id: entry.key,
        label: treeNode.label,
        category: category,
        thumbnailUrl: treeNode.thumbnailUrl,
        color: treeNode.color,
        hasChildren: false, // computed after edges
      );
    }

    // Build edges.
    for (final entry in provider.outgoingDepsByNode.entries) {
      final sourceId = entry.key;
      if (!isCraftOrIngredient(sourceId)) continue;
      if (collapsedOutputs.containsKey(sourceId)) continue;

      for (final treeEdge in entry.value) {
        var targetId = treeEdge.targetId;
        if (!isCraftOrIngredient(targetId) &&
            !collapsedOutputs.containsKey(targetId)) {
          continue;
        }
        // Redirect edges to collapsed output nodes.
        if (collapsedOutputs.containsKey(targetId)) {
          targetId = collapsedOutputs[targetId]!;
        }
        if (!nodesById.containsKey(sourceId) ||
            !nodesById.containsKey(targetId)) {
          continue;
        }

        addEdge(GraphEdgeData(
          sourceId: sourceId,
          targetId: targetId,
          amount: treeEdge.amount,
          label: treeEdge.label,
        ));
      }
    }

    // Handle collapsed output nodes: their incoming edges become edges to the craft.
    for (final entry in collapsedOutputs.entries) {
      final outputId = entry.key;
      final craftId = entry.value;
      final outputIncoming = treeIncoming[outputId] ?? const [];
      for (final treeEdge in outputIncoming) {
        final sourceId = treeEdge.sourceId;
        if (!isCraftOrIngredient(sourceId)) continue;
        if (collapsedOutputs.containsKey(sourceId)) continue;
        if (!nodesById.containsKey(sourceId) ||
            !nodesById.containsKey(craftId)) {
          continue;
        }
        addEdge(GraphEdgeData(
          sourceId: sourceId,
          targetId: craftId,
          amount: treeEdge.amount,
          label: treeEdge.label,
        ));
      }
    }

    // Set hasChildren based on whether the node has craft/ingredient predecessors.
    final updatedNodes = <String, GraphNodeData>{};
    for (final entry in nodesById.entries) {
      final incoming = incomingByNode[entry.key] ?? const [];
      final hasChildren = incoming.any((e) => nodesById.containsKey(e.sourceId));
      updatedNodes[entry.key] = GraphNodeData(
        id: entry.value.id,
        label: entry.value.label,
        category: entry.value.category,
        thumbnailUrl: entry.value.thumbnailUrl,
        color: entry.value.color,
        hasChildren: hasChildren,
        metadata: entry.value.metadata,
      );
    }

    return GraphData(
      nodesById: updatedNodes,
      incomingByNode: incomingByNode,
      outgoingByNode: outgoingByNode,
    );
  }

  /// Converts a [CraftTreeNodeType] to a display-friendly category string.
  static String _categoryLabel(CraftTreeNodeType type) {
    switch (type) {
      case CraftTreeNodeType.craft:
        return 'Craft';
      case CraftTreeNodeType.ingredient:
        return 'Ingredient';
      case CraftTreeNodeType.tech:
        return 'Tech';
      case CraftTreeNodeType.achievement:
        return 'Achievement';
    }
  }

  /// Converts JSON thumbnailUrl (e.g. "img/foo.png") to asset path candidates.
  static List<String> resolveImageCandidates(String thumbnailUrl) {
    if (!thumbnailUrl.startsWith('img/')) return [];
    final base = thumbnailUrl.replaceAll(RegExp(r'\.(png|svg)$'), '');
    return [
      'assets/crafts/$base.svg',
      'assets/crafts/$thumbnailUrl',
    ];
  }
}
