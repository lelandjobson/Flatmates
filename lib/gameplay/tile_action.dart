import 'package:flutter/foundation.dart';
import '../rendering/iso/iso_coordinate.dart';

/// A queued action on a tile. The action itself is intentionally opaque --
/// what actually happens is resolved at execution time by the view's
/// [TileActionResolver] based on the friend's state, tile contents, and
/// any structure present.
class TileAction {
  TileAction({required this.id, required this.coordinate})
      : createdAt = DateTime.now();

  final String id;
  final IsoCoordinate coordinate;
  final DateTime createdAt;

  @override
  String toString() => 'TileAction($id @ ${coordinate.key})';
}

/// Tile-keyed queue of pending [TileAction]s.
///
/// Actions are one-shot: consumed (removed) when a friend arrives at the tile
/// and executes the action. The queue is view-independent; the view decides
/// when to queue and how to resolve.
class TileActionQueue extends ChangeNotifier {
  final Map<String, TileAction> _actions = {};
  int _idCounter = 0;

  String _key(IsoCoordinate coord) => coord.key;

  TileAction? getAt(IsoCoordinate coord) => _actions[_key(coord)];

  bool hasActionAt(IsoCoordinate coord) => _actions.containsKey(_key(coord));

  /// Queue a new action at [coord]. Replaces any existing action at that tile.
  TileAction queueAt(IsoCoordinate coord) {
    _idCounter++;
    final action = TileAction(
      id: 'ta_${DateTime.now().millisecondsSinceEpoch}_$_idCounter',
      coordinate: coord,
    );
    _actions[_key(coord)] = action;
    notifyListeners();
    return action;
  }

  /// Remove and return the action at [coord], or null if none.
  TileAction? consumeAt(IsoCoordinate coord) {
    final action = _actions.remove(_key(coord));
    if (action != null) notifyListeners();
    return action;
  }

  void cancelAt(IsoCoordinate coord) {
    if (_actions.remove(_key(coord)) != null) notifyListeners();
  }

  void clear() {
    if (_actions.isNotEmpty) {
      _actions.clear();
      notifyListeners();
    }
  }

  Iterable<TileAction> get allActions => _actions.values;

  /// Coordinates that have a queued action (for rendering icons).
  Iterable<IsoCoordinate> get actionCoordinates =>
      _actions.values.map((a) => a.coordinate);

  int get length => _actions.length;

  bool get isEmpty => _actions.isEmpty;
  bool get isNotEmpty => _actions.isNotEmpty;
}
