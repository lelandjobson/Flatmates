import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'craft_tech_models.dart';
import 'craft_tree_index.dart';

/// Provider that loads crafts.json and techs.json from assets and exposes them
/// with lookup maps for prereq resolution (craftById, techNodeById).
class CraftsTechProvider extends ChangeNotifier {
  CraftsTechProvider();

  List<CraftEntry> _crafts = [];
  List<TechEntry> _techs = [];
  Map<String, CraftEntry> _craftById = {};
  Map<String, GraphNode> _techNodeById = {};
  List<String> _rawCatalogIds = [];
  Map<String, Color> _materialIdToColor = {};
  Map<String, String> _materialIdToThumbnailUrl = {};
  List<String> _craftJsonAssetPaths = [];
  Map<String, CraftTreeNodeData> _treeNodesById = {};
  Map<String, List<CraftTreeDependencyEdge>> _incomingDepsByNode = {};
  Map<String, List<CraftTreeDependencyEdge>> _outgoingDepsByNode = {};
  CraftSearchLibrary _searchLibrary = CraftSearchLibrary.empty();
  bool _loaded = false;
  String? _error;

  List<CraftEntry> get crafts => _crafts;
  List<TechEntry> get techs => _techs;
  Map<String, CraftEntry> get craftById => _craftById;
  Map<String, GraphNode> get techNodeById => _techNodeById;
  List<String> get rawCatalogIds => _rawCatalogIds;
  Map<String, Color> get materialIdToColor => _materialIdToColor;
  Map<String, String> get materialIdToThumbnailUrl => _materialIdToThumbnailUrl;
  List<String> get craftJsonAssetPaths => _craftJsonAssetPaths;
  Map<String, CraftTreeNodeData> get treeNodesById => _treeNodesById;
  Map<String, List<CraftTreeDependencyEdge>> get incomingDepsByNode =>
      _incomingDepsByNode;
  Map<String, List<CraftTreeDependencyEdge>> get outgoingDepsByNode =>
      _outgoingDepsByNode;
  CraftSearchLibrary get searchLibrary => _searchLibrary;
  bool get loaded => _loaded;
  String? get error => _error;

  static const Color _defaultGrey = Color(0xFF6B6B6B);

  /// Fallback palette when crafts.json has no color. Keys: catalogId (sand, coal)
  /// and fm- prefixed (fm-sand, fm-coal). Used for CraftingDatabase recipe IDs.
  static const Map<String, Color> _fallbackPalette = {
    'clay': Color(0xFFCC8855),
    'coal': Color(0xFF444444),
    'cotton': Color(0xFFF5F0E0),
    'sand': Color(0xFFE8D44D),
    'logs': Color(0xFF7B4A2B),
    'iron-ore': Color(0xFFB85C3A),
    'fabric-dye': Color(0xFF5B8DC9),
    'foam-rubber': Color(0xFF66BB6A),
  };

  Color colorFor(String materialId) =>
      _materialIdToColor[materialId] ??
      _fallbackPalette[_normalizeForLookup(materialId)] ??
      _defaultGrey;

  /// Normalizes material ID for fallback lookup (fm-sand -> sand, sand -> sand).
  static String _normalizeForLookup(String id) {
    if (id.startsWith('fm-')) return id.substring(3);
    return id;
  }

  Future<void> load() async {
    try {
      final assets = await _discoverCraftJsonAssets();
      _craftJsonAssetPaths = assets;

      final craftById = <String, CraftEntry>{};
      final techById = <String, TechEntry>{};
      for (final path in assets) {
        final raw = await rootBundle.loadString(path);
        final decoded = jsonDecode(raw);
        _collectEntriesFromDecoded(
          decoded,
          onCraft: (entry) => craftById[entry.id] = entry,
          onTech: (entry) => techById[entry.id] = entry,
        );
      }
      _crafts = craftById.values.toList(growable: false);
      _techs = techById.values.toList(growable: false);

      _craftById = {for (final c in _crafts) c.id: c};
      _techNodeById = {};
      for (final t in _techs) {
        for (final node in t.techTree.nodes) {
          _techNodeById[node.id] = node;
        }
      }
      final rawIds = <String>{};
      _materialIdToColor = {};
      _materialIdToThumbnailUrl = {};
      for (final c in _crafts) {
        final disp = c.displayNode;
        for (final node in c.crafting.nodes) {
          final color = node.color ?? _fallbackPalette[node.catalogId];
          if (node.kind == 'raw' && node.catalogId != null) {
            rawIds.add(node.catalogId!);
            final cid = node.catalogId!;
            if (color != null) {
              _materialIdToColor[cid] = color;
              _materialIdToColor['fm-$cid'] = color;
            }
            if (node.thumbnailUrl != null) {
              _materialIdToThumbnailUrl[cid] = node.thumbnailUrl!;
              _materialIdToThumbnailUrl['fm-$cid'] = node.thumbnailUrl!;
            }
          }
          if (color != null) _materialIdToColor[c.id] = color;
          if (node.thumbnailUrl != null) {
            _materialIdToThumbnailUrl[c.id] = node.thumbnailUrl!;
          }
        }
        if (disp != null) {
          final dispColor = disp.color ?? _fallbackPalette[disp.catalogId];
          if (dispColor != null) _materialIdToColor[c.id] = dispColor;
          if (disp.thumbnailUrl != null) {
            _materialIdToThumbnailUrl[c.id] = disp.thumbnailUrl!;
          }
        }
      }
      for (final e in _fallbackPalette.entries) {
        _materialIdToColor.putIfAbsent(e.key, () => e.value);
        _materialIdToColor.putIfAbsent('fm-${e.key}', () => e.value);
      }
      _rawCatalogIds = rawIds.toList();
      _buildTreeIndex();
      _loaded = true;
      _error = null;
    } catch (e) {
      _error = e.toString();
      _crafts = [];
      _techs = [];
      _craftById = {};
      _techNodeById = {};
      _rawCatalogIds = [];
      _materialIdToColor = {};
      _materialIdToThumbnailUrl = {};
      _craftJsonAssetPaths = [];
      _treeNodesById = {};
      _incomingDepsByNode = {};
      _outgoingDepsByNode = {};
      _searchLibrary = CraftSearchLibrary.empty();
    }
    notifyListeners();
  }

  Future<List<String>> _discoverCraftJsonAssets() async {
    final discovered = <String>{};
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    for (final path in manifest.listAssets()) {
      if (path.startsWith('assets/crafts/') && path.endsWith('.json')) {
        discovered.add(path);
      }
    }
    // Fallbacks (in case asset manifests are trimmed in dev scenarios).
    discovered.add('assets/crafts/crafts.json');
    discovered.add('assets/crafts/techs.json');
    final list = discovered.toList()..sort();
    return list;
  }

  void _collectEntriesFromDecoded(
    Object? decoded, {
    required void Function(CraftEntry entry) onCraft,
    required void Function(TechEntry entry) onTech,
  }) {
    if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          _collectEntryMap(item, onCraft: onCraft, onTech: onTech);
        } else if (item is Map) {
          _collectEntryMap(
            item.cast<String, dynamic>(),
            onCraft: onCraft,
            onTech: onTech,
          );
        }
      }
      return;
    }
    if (decoded is Map<String, dynamic>) {
      _collectEntryMap(decoded, onCraft: onCraft, onTech: onTech);
      return;
    }
    if (decoded is Map) {
      _collectEntryMap(
        decoded.cast<String, dynamic>(),
        onCraft: onCraft,
        onTech: onTech,
      );
    }
  }

  void _collectEntryMap(
    Map<String, dynamic> map, {
    required void Function(CraftEntry entry) onCraft,
    required void Function(TechEntry entry) onTech,
  }) {
    if (map.containsKey('crafting')) {
      onCraft(CraftEntry.fromJson(map));
    }
    if (map.containsKey('techTree')) {
      onTech(TechEntry.fromJson(map));
    }
    final nested = map['entries'];
    if (nested != null) {
      _collectEntriesFromDecoded(nested, onCraft: onCraft, onTech: onTech);
    }
  }

  void _buildTreeIndex() {
    final nodesById = <String, CraftTreeNodeData>{};
    final incoming = <String, List<CraftTreeDependencyEdge>>{};
    final outgoing = <String, List<CraftTreeDependencyEdge>>{};
    final canonicalRootIds = <String>{};

    void upsertNode({
      required String id,
      required String label,
      required CraftTreeNodeType type,
      String? thumbnailUrl,
      Color? color,
      Iterable<String> aliases = const <String>[],
    }) {
      final existing = nodesById[id];
      if (existing == null) {
        nodesById[id] = CraftTreeNodeData(
          id: id,
          label: label,
          type: type,
          thumbnailUrl: thumbnailUrl,
          color: color,
          aliases: aliases.toSet(),
        );
        return;
      }
      if (existing.label.isEmpty && label.isNotEmpty) {
        existing.label = label;
      }
      if (existing.thumbnailUrl == null && thumbnailUrl != null) {
        existing.thumbnailUrl = thumbnailUrl;
      }
      if (existing.color == null && color != null) {
        existing.color = color;
      }
      existing.aliases.addAll(aliases);
    }

    void addEdge(CraftTreeDependencyEdge edge) {
      outgoing.putIfAbsent(edge.sourceId, () => <CraftTreeDependencyEdge>[]).add(edge);
      incoming.putIfAbsent(edge.targetId, () => <CraftTreeDependencyEdge>[]).add(edge);
    }

    for (final tech in _techs) {
      for (final node in tech.techTree.nodes) {
        canonicalRootIds.add(node.id);
        final nodeLabel = node.displayName ?? _labelFromId(node.id);
        upsertNode(
          id: node.id,
          label: nodeLabel,
          type: CraftTreeNodeType.tech,
          thumbnailUrl: node.thumbnailUrl,
          color: node.color,
          aliases: <String>[
            if (node.recipeName != null) node.recipeName!,
            if (node.catalogId != null) node.catalogId!,
            node.id,
            nodeLabel,
          ],
        );
      }
      for (final edge in tech.techTree.edges) {
        addEdge(CraftTreeDependencyEdge(
          sourceId: edge.source,
          targetId: edge.target,
          amount: _edgeAmount(edge),
          label: _edgeLabel(edge),
        ));
      }
    }

    for (final craft in _crafts) {
      canonicalRootIds.add(craft.id);
      final display = craft.displayNode;
      upsertNode(
        id: craft.id,
        label: craft.displayName ?? _labelFromId(craft.id),
        type: CraftTreeNodeType.craft,
        thumbnailUrl: display?.thumbnailUrl,
        color: display?.color ?? _materialIdToColor[craft.id],
        aliases: <String>[craft.id, if (craft.displayName != null) craft.displayName!],
      );

      for (final node in craft.crafting.nodes) {
        final nodeLabel = node.displayName ?? _labelFromId(node.recipeName ?? node.catalogId ?? node.id);
        final nodeType = _nodeTypeFromGraphNode(node);
        upsertNode(
          id: node.id,
          label: nodeLabel,
          type: nodeType,
          thumbnailUrl: node.thumbnailUrl,
          color: node.color,
          aliases: <String>[
            node.id,
            nodeLabel,
            if (node.recipeName != null) node.recipeName!,
            if (node.catalogId != null) node.catalogId!,
            if (node.catalogId != null) 'fm-${node.catalogId!}',
          ],
        );

        for (final prereq in node.prereqs) {
          final prereqType = prereq.type == 'achievement'
              ? CraftTreeNodeType.achievement
              : CraftTreeNodeType.tech;
          upsertNode(
            id: prereq.id,
            label: _labelFromId(prereq.id),
            type: prereqType,
            aliases: <String>[prereq.id],
          );
          addEdge(CraftTreeDependencyEdge(
            sourceId: prereq.id,
            targetId: node.id,
            amount: 1,
            label: prereq.type,
          ));
        }
      }

      for (final edge in craft.crafting.edges) {
        final amount = _edgeAmount(edge);
        final label = _edgeLabel(edge);

        final sourceExists = nodesById.containsKey(edge.source);
        if (!sourceExists) {
          upsertNode(
            id: edge.source,
            label: _labelFromId(edge.source),
            type: CraftTreeNodeType.ingredient,
            aliases: <String>[edge.source],
          );
        }
        if (!nodesById.containsKey(edge.target)) {
          upsertNode(
            id: edge.target,
            label: _labelFromId(edge.target),
            type: CraftTreeNodeType.craft,
            aliases: <String>[edge.target],
          );
        }
        addEdge(CraftTreeDependencyEdge(
          sourceId: edge.source,
          targetId: edge.target,
          amount: amount,
          label: label,
        ));

        for (final cost in edge.costs) {
          if (cost.type != 'element') continue;
          final sourceNode = nodesById[edge.source];
          if (sourceNode != null) {
            if (cost.elementId != null) sourceNode.aliases.add(cost.elementId!);
            if (cost.elementName != null) sourceNode.aliases.add(cost.elementName!);
          }
        }
      }

      // Link the recipe output node to the top-level craft id so the dependency
      // graph from the craft (e.g. fm-apartment) includes the recipe's ingredients.
      final outputNode = craft.displayNode;
      if (outputNode != null &&
          outputNode.id != craft.id &&
          nodesById.containsKey(outputNode.id)) {
        addEdge(CraftTreeDependencyEdge(
          sourceId: outputNode.id,
          targetId: craft.id,
          amount: 1,
        ));
      }
    }

    _treeNodesById = nodesById;
    _incomingDepsByNode = incoming;
    _outgoingDepsByNode = outgoing;
    // Search only indexes canonical roots (one per craft, one per tech/achievement)
    // so we don't show duplicates like "Apartment" from both fm-apartment and final-apartment.
    _searchLibrary = CraftSearchLibrary.build(
      nodesById.values.where((n) => canonicalRootIds.contains(n.id)),
    );
  }

  CraftTreeNodeType _nodeTypeFromGraphNode(GraphNode node) {
    if (node.kind == 'raw') return CraftTreeNodeType.ingredient;
    if (node.id.startsWith('tech-')) return CraftTreeNodeType.tech;
    if (node.id.startsWith('ach-')) return CraftTreeNodeType.achievement;
    return CraftTreeNodeType.craft;
  }

  int _edgeAmount(GraphEdge edge) {
    for (final cost in edge.costs) {
      if (cost.type == 'element' && cost.amount != null && cost.amount! > 0) {
        return cost.amount!;
      }
    }
    return 1;
  }

  String? _edgeLabel(GraphEdge edge) {
    for (final cost in edge.costs) {
      if (cost.type == 'element' && cost.elementName != null) {
        return cost.elementName;
      }
    }
    return null;
  }

  static String _labelFromId(String id) {
    final normalized = id
        .replaceFirst('fm-', '')
        .replaceAll(RegExp(r'^(tech|ach)-'), '')
        .replaceAll(RegExp(r'[_\-]'), ' ')
        .trim();
    if (normalized.isEmpty) return id;
    return normalized
        .split(' ')
        .map((part) => part.isEmpty
            ? part
            : '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }

  List<CraftTreeSearchEntry> searchTreeSync(String query, {int limit = 50}) {
    return _searchLibrary.search(query, limit: limit);
  }

  Future<List<CraftTreeSearchEntry>> searchTree(
    String query, {
    int limit = 50,
  }) async {
    return Future<List<CraftTreeSearchEntry>>.microtask(
      () => _searchLibrary.search(query, limit: limit),
    );
  }

  /// Builds the dependency graph from [rootId], optionally limited to [maxDepth]
  /// levels (1 = only immediate ingredients).
  /// When [rootId] is a craft id whose only predecessor is its recipe output node,
  /// that output node is collapsed so only one node (the craft) is shown, with
  /// edges from the recipe's actual ingredients to the craft.
  CraftTreeDependencyGraph buildDependencyGraph(
    String rootId, {
    int maxNodes = 250,
    int maxDepth = 1,
  }) {
    if (!_treeNodesById.containsKey(rootId)) {
      return CraftTreeDependencyGraph(
        rootId: rootId,
        nodeIds: <String>{},
        edges: const <CraftTreeDependencyEdge>[],
      );
    }

    final craft = _craftById[rootId];
    final outputNodeId = craft?.displayNode?.id;
    if (outputNodeId != null &&
        outputNodeId != rootId &&
        _treeNodesById.containsKey(outputNodeId)) {
      final incomingToRoot = _incomingDepsByNode[rootId] ?? const [];
      if (incomingToRoot.length == 1 &&
          incomingToRoot.single.sourceId == outputNodeId) {
        final outIncoming =
            _incomingDepsByNode[outputNodeId] ?? const <CraftTreeDependencyEdge>[];
        final nodes = <String>{rootId};
        final edgeList = <CraftTreeDependencyEdge>[];
        for (final e in outIncoming) {
          if (!_treeNodesById.containsKey(e.sourceId)) continue;
          if (nodes.length >= maxNodes) break;
          nodes.add(e.sourceId);
          edgeList.add(CraftTreeDependencyEdge(
            sourceId: e.sourceId,
            targetId: rootId,
            amount: e.amount,
            label: e.label,
          ));
        }
        return CraftTreeDependencyGraph(
          rootId: rootId,
          nodeIds: nodes,
          edges: edgeList,
        );
      }
    }

    final visited = <String>{rootId};
    final stack = <String>[rootId];
    final edges = <CraftTreeDependencyEdge>[];
    final seenEdgeKeys = <String>{};
    final distanceFromRoot = <String, int>{rootId: 0};

    while (stack.isNotEmpty) {
      final current = stack.removeLast();
      final currentDepth = distanceFromRoot[current] ?? 0;
      final deps = _incomingDepsByNode[current] ?? const <CraftTreeDependencyEdge>[];
      for (final edge in deps) {
        final key = '${edge.sourceId}->${edge.targetId}:${edge.amount}:${edge.label ?? ''}';
        if (seenEdgeKeys.add(key)) {
          edges.add(edge);
        }
        if (!_treeNodesById.containsKey(edge.sourceId)) continue;
        if (visited.length >= maxNodes) continue;
        if (currentDepth >= maxDepth) continue;
        if (visited.add(edge.sourceId)) {
          distanceFromRoot[edge.sourceId] = currentDepth + 1;
          stack.add(edge.sourceId);
        }
      }
    }

    return CraftTreeDependencyGraph(rootId: rootId, nodeIds: visited, edges: edges);
  }

  /// Converts JSON thumbnailUrl (e.g. "img/foo.png") to asset paths to try.
  /// Returns [svgPath, pngPath] in preferred order. Caller should try each until one loads.
  List<String> resolveImagePathCandidates(String thumbnailUrl) {
    if (!thumbnailUrl.startsWith('img/')) return [];
    final base = thumbnailUrl.replaceAll(RegExp(r'\.(png|svg)$'), '');
    return [
      'assets/crafts/$base.svg',
      'assets/crafts/$thumbnailUrl',
    ];
  }

  /// Legacy: returns SVG path (may not exist; use resolveImagePathCandidates).
  String? resolveImagePath(String thumbnailUrl) {
    final candidates = resolveImagePathCandidates(thumbnailUrl);
    return candidates.isNotEmpty ? candidates.first : null;
  }

  /// Returns literal asset path (e.g. assets/crafts/img/foo.png).
  String? resolveImagePathLiteral(String thumbnailUrl) {
    if (thumbnailUrl.startsWith('img/')) {
      return 'assets/crafts/$thumbnailUrl';
    }
    return null;
  }
}
