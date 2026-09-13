/// World mutations that can break a flatmate day route.
enum TileEventKind { path, wall, program, volume }

typedef TileEventCallback = void Function(
  Set<(int, int)> tiles,
  TileEventKind kind,
);

class _TileSubscription {
  _TileSubscription({
    required this.tiles,
    required this.kinds,
    required this.onEvent,
  });

  Set<(int, int)> tiles;
  Set<TileEventKind> kinds;
  TileEventCallback onEvent;
}

/// Light tile-scoped bus. Listeners recompute only when a watched tile fires.
class TileEventHub {
  final Map<String, _TileSubscription> _subs = {};

  void subscribe({
    required String id,
    required Set<(int, int)> tiles,
    required Set<TileEventKind> kinds,
    required TileEventCallback onEvent,
  }) {
    _subs[id] = _TileSubscription(
      tiles: Set<(int, int)>.from(tiles),
      kinds: Set<TileEventKind>.from(kinds),
      onEvent: onEvent,
    );
  }

  void unsubscribe(String id) => _subs.remove(id);

  void emit(Iterable<(int, int)> tiles, TileEventKind kind) {
    final hit = tiles.toSet();
    if (hit.isEmpty) return;
    for (final sub in List<_TileSubscription>.from(_subs.values)) {
      if (!sub.kinds.contains(kind)) continue;
      if (sub.tiles.any(hit.contains)) {
        sub.onEvent(hit, kind);
      }
    }
  }

  bool hasSubscription(String id) => _subs.containsKey(id);

  Set<(int, int)> watchedTiles(String id) =>
      Set<(int, int)>.from(_subs[id]?.tiles ?? const {});
}