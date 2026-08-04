import 'package:flutter/material.dart';

enum CraftTreeNodeType { craft, ingredient, tech, achievement }

class CraftTreeNodeData {
  CraftTreeNodeData({
    required this.id,
    required this.label,
    required this.type,
    this.thumbnailUrl,
    this.color,
    Set<String>? aliases,
  }) : aliases = aliases ?? <String>{};

  final String id;
  String label;
  CraftTreeNodeType type;
  String? thumbnailUrl;
  Color? color;
  final Set<String> aliases;
}

class CraftTreeDependencyEdge {
  const CraftTreeDependencyEdge({
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

class CraftTreeDependencyGraph {
  const CraftTreeDependencyGraph({
    required this.rootId,
    required this.nodeIds,
    required this.edges,
  });

  final String rootId;
  final Set<String> nodeIds;
  final List<CraftTreeDependencyEdge> edges;
}

class CraftTreeSearchEntry {
  const CraftTreeSearchEntry({
    required this.id,
    required this.label,
    required this.type,
    this.thumbnailUrl,
  });

  final String id;
  final String label;
  final CraftTreeNodeType type;
  final String? thumbnailUrl;
}

class CraftSearchLibrary {
  CraftSearchLibrary._({
    required Map<String, CraftTreeSearchEntry> entriesById,
    required Map<String, Set<String>> prefixToIds,
    required Map<String, Set<String>> tokenToIds,
    required Map<String, String> normalizedLabelById,
  })  : _entriesById = entriesById,
        _prefixToIds = prefixToIds,
        _tokenToIds = tokenToIds,
        _normalizedLabelById = normalizedLabelById;

  factory CraftSearchLibrary.empty() => CraftSearchLibrary._(
        entriesById: const {},
        prefixToIds: const {},
        tokenToIds: const {},
        normalizedLabelById: const {},
      );

  factory CraftSearchLibrary.build(Iterable<CraftTreeNodeData> nodes) {
    final entriesById = <String, CraftTreeSearchEntry>{};
    final prefixToIds = <String, Set<String>>{};
    final tokenToIds = <String, Set<String>>{};
    final normalizedLabelById = <String, String>{};

    for (final node in nodes) {
      final entry = CraftTreeSearchEntry(
        id: node.id,
        label: node.label,
        type: node.type,
        thumbnailUrl: node.thumbnailUrl,
      );
      entriesById[node.id] = entry;
      normalizedLabelById[node.id] = _normalize(node.label);

      final tokenSources = <String>{node.id, node.label, ...node.aliases};
      final tokens = <String>{};
      for (final source in tokenSources) {
        tokens.addAll(_tokenize(source));
      }
      for (final token in tokens) {
        tokenToIds.putIfAbsent(token, () => <String>{}).add(node.id);
        final maxPrefix = token.length < 24 ? token.length : 24;
        for (var i = 1; i <= maxPrefix; i++) {
          final prefix = token.substring(0, i);
          prefixToIds.putIfAbsent(prefix, () => <String>{}).add(node.id);
        }
      }
    }

    return CraftSearchLibrary._(
      entriesById: entriesById,
      prefixToIds: prefixToIds,
      tokenToIds: tokenToIds,
      normalizedLabelById: normalizedLabelById,
    );
  }

  final Map<String, CraftTreeSearchEntry> _entriesById;
  final Map<String, Set<String>> _prefixToIds;
  final Map<String, Set<String>> _tokenToIds;
  final Map<String, String> _normalizedLabelById;

  bool get isEmpty => _entriesById.isEmpty;

  CraftTreeSearchEntry? byId(String id) => _entriesById[id];

  List<CraftTreeSearchEntry> search(String query, {int limit = 50}) {
    final normalizedQuery = _normalize(query);
    if (normalizedQuery.isEmpty) return const [];

    final queryTokens = _tokenize(normalizedQuery).toList(growable: false);
    if (queryTokens.isEmpty) return const [];

    final candidateIds = <String>{};
    for (final token in queryTokens) {
      final prefixHits = _prefixToIds[token];
      if (prefixHits != null) {
        candidateIds.addAll(prefixHits);
      }
      final tokenHits = _tokenToIds[token];
      if (tokenHits != null) {
        candidateIds.addAll(tokenHits);
      }
    }
    if (candidateIds.isEmpty) return const [];

    final scored = <_ScoredEntry>[];
    for (final id in candidateIds) {
      final entry = _entriesById[id];
      if (entry == null) continue;
      final score = _scoreEntry(entry, normalizedQuery, queryTokens);
      if (score <= 0) continue;
      scored.add(_ScoredEntry(entry: entry, score: score));
    }

    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.entry.label.toLowerCase().compareTo(b.entry.label.toLowerCase());
    });

    if (scored.length > limit) {
      return scored.take(limit).map((e) => e.entry).toList(growable: false);
    }
    return scored.map((e) => e.entry).toList(growable: false);
  }

  int _scoreEntry(
    CraftTreeSearchEntry entry,
    String normalizedQuery,
    List<String> queryTokens,
  ) {
    var score = 0;
    final normalizedLabel =
        _normalizedLabelById[entry.id] ?? _normalize(entry.label);
    final normalizedId = _normalize(entry.id);

    if (normalizedLabel == normalizedQuery ||
        normalizedId == normalizedQuery) {
      score += 400;
    }
    if (normalizedLabel.startsWith(normalizedQuery)) score += 220;
    if (normalizedId.startsWith(normalizedQuery)) score += 170;
    if (normalizedLabel.contains(normalizedQuery)) score += 120;
    if (normalizedId.contains(normalizedQuery)) score += 90;

    for (final token in queryTokens) {
      if (normalizedLabel.contains(token)) score += 30;
      if (normalizedId.contains(token)) score += 20;
    }

    switch (entry.type) {
      case CraftTreeNodeType.craft:
        score += 10;
      case CraftTreeNodeType.ingredient:
      case CraftTreeNodeType.tech:
      case CraftTreeNodeType.achievement:
        break;
    }
    return score;
  }

  static String _normalize(String value) {
    final lower = value.toLowerCase().trim();
    if (lower.isEmpty) return '';
    return lower
        .replaceAll(RegExp(r'[_\-]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static Iterable<String> _tokenize(String value) sync* {
    final normalized = _normalize(value);
    if (normalized.isEmpty) return;
    for (final token in normalized.split(' ')) {
      if (token.isNotEmpty) yield token;
    }
  }
}

class _ScoredEntry {
  const _ScoredEntry({required this.entry, required this.score});
  final CraftTreeSearchEntry entry;
  final int score;
}
