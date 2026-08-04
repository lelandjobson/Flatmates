import 'package:flutter/material.dart';

/// Prerequisite for a craft node. Type is extensible: "tech" (tech tree node),
/// future: "tile", "facility", etc.
class Prereq {
  const Prereq({required this.type, required this.id});

  final String type;
  final String id;

  factory Prereq.fromJson(Map<String, dynamic> json) {
    return Prereq(
      type: json['type'] as String? ?? '',
      id: json['id'] as String? ?? '',
    );
  }
}

/// Position in 2D layout.
class NodePosition {
  const NodePosition({required this.x, required this.y});

  final double x;
  final double y;

  factory NodePosition.fromJson(Map<String, dynamic> json) {
    return NodePosition(
      x: (json['x'] as num?)?.toDouble() ?? 0,
      y: (json['y'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Edge cost: element (resource) or conditional (prerequisite).
class EdgeCost {
  const EdgeCost({
    required this.type,
    this.elementId,
    this.elementName,
    this.amount,
    this.conditionType,
    this.condition,
  });

  final String type;
  final String? elementId;
  final String? elementName;
  final int? amount;
  final String? conditionType;
  final String? condition;

  factory EdgeCost.fromJson(Map<String, dynamic> json) {
    return EdgeCost(
      type: json['type'] as String? ?? '',
      elementId: json['elementId'] as String?,
      elementName: json['elementName'] as String?,
      amount: (json['amount'] as num?)?.toInt(),
      conditionType: json['conditionType'] as String?,
      condition: json['condition'] as String?,
    );
  }
}

/// Parses a hex color string (e.g. "#c8a090") to Flutter Color.
Color? _parseHexColor(String? value) {
  if (value == null || value.isEmpty) return null;
  final hex = value.startsWith('#') ? value.substring(1) : value;
  if (hex.length == 6) {
    final r = int.tryParse(hex.substring(0, 2), radix: 16);
    final g = int.tryParse(hex.substring(2, 4), radix: 16);
    final b = int.tryParse(hex.substring(4, 6), radix: 16);
    if (r != null && g != null && b != null) {
      return Color(0xFF000000 | (r << 16) | (g << 8) | b);
    }
  }
  return null;
}

/// Graph node (craft or tech). ID from instance_id for prereq resolution.
class GraphNode {
  const GraphNode({
    required this.id,
    this.displayName,
    this.kind,
    this.catalogId,
    this.recipeName,
    this.position = const NodePosition(x: 0, y: 0),
    this.thumbnailUrl,
    this.prereqs = const [],
    this.color,
  });

  final String id;
  final String? displayName;
  final String? kind;
  final String? catalogId;
  final String? recipeName;
  final NodePosition position;
  final String? thumbnailUrl;
  final List<Prereq> prereqs;
  final Color? color;

  factory GraphNode.fromJson(Map<String, dynamic> json) {
    final prereqsJson = json['prereqs'] as List<dynamic>?;
    final colorStr = json['color'] as String?;
    return GraphNode(
      id: json['instance_id'] as String? ?? json['id'] as String? ?? '',
      displayName: json['displayName'] as String? ?? json['title'] as String?,
      kind: json['kind'] as String?,
      catalogId: json['catalogId'] as String?,
      recipeName: json['recipeName'] as String?,
      position: json['position'] != null
          ? NodePosition.fromJson(json['position'] as Map<String, dynamic>)
          : const NodePosition(x: 0, y: 0),
      thumbnailUrl: json['thumbnailUrl'] as String?,
      prereqs: prereqsJson != null
          ? prereqsJson
              .map((e) => Prereq.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      color: _parseHexColor(colorStr),
    );
  }
}

/// Graph edge (craft or tech).
class GraphEdge {
  const GraphEdge({
    required this.id,
    required this.source,
    required this.target,
    this.costs = const [],
    this.reversible = false,
  });

  final String id;
  final String source;
  final String target;
  final List<EdgeCost> costs;
  final bool reversible;

  factory GraphEdge.fromJson(Map<String, dynamic> json) {
    final costsJson = json['costs'] as List<dynamic>?;
    return GraphEdge(
      id: json['id'] as String? ?? '',
      source: json['source'] as String? ?? '',
      target: json['target'] as String? ?? '',
      costs: costsJson != null
          ? costsJson
              .map((e) => EdgeCost.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      reversible: json['reversible'] as bool? ?? false,
    );
  }
}

/// Crafting graph (nodes + edges).
class CraftGraph {
  const CraftGraph({
    this.type = 'crafting',
    this.nodes = const [],
    this.edges = const [],
  });

  final String type;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  factory CraftGraph.fromJson(Map<String, dynamic> json) {
    final nodesJson = json['nodes'] as List<dynamic>?;
    final edgesJson = json['edges'] as List<dynamic>?;
    return CraftGraph(
      type: json['type'] as String? ?? 'crafting',
      nodes: nodesJson != null
          ? nodesJson
              .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      edges: edgesJson != null
          ? edgesJson
              .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }
}

/// Tech tree graph (nodes + edges).
class TechGraph {
  const TechGraph({
    this.type = 'tech-tree',
    this.nodes = const [],
    this.edges = const [],
  });

  final String type;
  final List<GraphNode> nodes;
  final List<GraphEdge> edges;

  factory TechGraph.fromJson(Map<String, dynamic> json) {
    final nodesJson = json['nodes'] as List<dynamic>?;
    final edgesJson = json['edges'] as List<dynamic>?;
    return TechGraph(
      type: json['type'] as String? ?? 'tech-tree',
      nodes: nodesJson != null
          ? nodesJson
              .map((e) => GraphNode.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
      edges: edgesJson != null
          ? edgesJson
              .map((e) => GraphEdge.fromJson(e as Map<String, dynamic>))
              .toList()
          : const [],
    );
  }
}

/// Craft entry from crafts.json. ID is the unique craft identifier.
class CraftEntry {
  const CraftEntry({
    required this.id,
    this.displayName,
    this.category,
    this.version,
    this.source,
    required this.crafting,
  });

  final String id;
  final String? displayName;
  final String? category;
  final String? version;
  final String? source;
  final CraftGraph crafting;

  /// Returns the best node for recipe icon display. Prefers non-raw nodes with
  /// thumbnailUrl; falls back to last node with thumbnail, then first with thumbnail.
  GraphNode? get displayNode {
    final withThumb = crafting.nodes.where((n) => n.thumbnailUrl != null).toList();
    if (withThumb.isEmpty) return null;
    final nonRaw = withThumb.where((n) => n.kind != 'raw').toList();
    return (nonRaw.isNotEmpty ? nonRaw.last : withThumb.last);
  }

  factory CraftEntry.fromJson(Map<String, dynamic> json) {
    return CraftEntry(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      displayName: json['displayName'] as String?,
      category: json['category'] as String?,
      version: json['version'] as String?,
      source: json['source'] as String?,
      crafting: json['crafting'] != null
          ? CraftGraph.fromJson(json['crafting'] as Map<String, dynamic>)
          : const CraftGraph(),
    );
  }
}

/// Tech entry from techs.json. ID is the tech-tree identifier.
class TechEntry {
  const TechEntry({
    required this.id,
    this.displayName,
    this.category,
    this.version,
    this.source,
    required this.techTree,
  });

  final String id;
  final String? displayName;
  final String? category;
  final String? version;
  final String? source;
  final TechGraph techTree;

  factory TechEntry.fromJson(Map<String, dynamic> json) {
    return TechEntry(
      id: json['id'] as String? ?? json['name'] as String? ?? '',
      displayName: json['displayName'] as String?,
      category: json['category'] as String?,
      version: json['version'] as String?,
      source: json['source'] as String?,
      techTree: json['techTree'] != null
          ? TechGraph.fromJson(json['techTree'] as Map<String, dynamic>)
          : const TechGraph(),
    );
  }
}
