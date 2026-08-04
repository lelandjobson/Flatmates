import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import '../tiles/tiles.dart';

class TileLink {
  const TileLink({
    required this.tile,
    required this.color,
    required this.worldPosition,
  });

  final TileCoordinate tile;
  final Color color;
  final Vector3 worldPosition;
}

enum LinkToggleResult { added, removed, blocked }

class TileLinkManager {
  TileLinkManager({this.maxLinksPerPrefab = 4});

  final int maxLinksPerPrefab;
  final ValueNotifier<Map<String, List<TileLink>>> linksNotifier =
      ValueNotifier<Map<String, List<TileLink>>>(const {});

  LinkToggleResult toggleLink(String prefabId, TileLink link) {
    final current = Map<String, List<TileLink>>.from(linksNotifier.value);
    final links = List<TileLink>.from(current[prefabId] ?? const []);
    final existingIndex = links.indexWhere((existing) {
      final tile = existing.tile;
      final other = link.tile;
      return tile.x == other.x &&
          tile.y == other.y &&
          tile.z == other.z &&
          tile.h == other.h;
    });
    if (existingIndex != -1) {
      links.removeAt(existingIndex);
      current[prefabId] = links;
      linksNotifier.value = Map.unmodifiable(current);
      return LinkToggleResult.removed;
    }
    if (links.length >= maxLinksPerPrefab) {
      return LinkToggleResult.blocked;
    }
    links.add(link);
    current[prefabId] = links;
    linksNotifier.value = Map.unmodifiable(current);
    return LinkToggleResult.added;
  }

  void clear() {
    linksNotifier.value = const {};
  }
}

