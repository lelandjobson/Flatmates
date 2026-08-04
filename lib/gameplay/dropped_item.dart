import 'package:flutter/foundation.dart';
import '../rendering/iso/iso_coordinate.dart';

/// Represents a dropped item on a tile
class DroppedItem {
  DroppedItem({required this.materialId, required int amount})
    : _amount = amount.clamp(0, maxAmount);

  final String materialId;
  int _amount;

  /// Maximum amount of a single material that can be dropped on one tile
  static const int maxAmount = 100;

  /// Current amount of the dropped item
  int get amount => _amount;

  /// Add to the dropped item stack (respects max)
  /// Returns the amount actually added
  int add(int toAdd) {
    final space = maxAmount - _amount;
    final added = toAdd.clamp(0, space);
    _amount += added;
    return added;
  }

  /// Remove from the dropped item stack
  /// Returns the amount actually removed
  int remove(int toRemove) {
    final removed = toRemove.clamp(0, _amount);
    _amount -= removed;
    return removed;
  }

  /// Check if the stack is full
  bool get isFull => _amount >= maxAmount;

  /// Check if the stack is empty
  bool get isEmpty => _amount <= 0;

  @override
  String toString() => 'DroppedItem($materialId x$_amount)';
}

/// Manages dropped items on tiles across the map
class TileDroppedItems extends ChangeNotifier {
  final Map<String, DroppedItem> _items = {};

  /// Get a unique key for a coordinate
  String _keyFor(IsoCoordinate coord) => '${coord.x}:${coord.y}';

  /// Get the dropped item at a coordinate, if any
  DroppedItem? getAt(IsoCoordinate coord) {
    return _items[_keyFor(coord)];
  }

  /// Check if there's a dropped item at a coordinate
  bool hasDroppedItem(IsoCoordinate coord) {
    final item = _items[_keyFor(coord)];
    return item != null && !item.isEmpty;
  }

  /// Drop material at a coordinate
  /// Returns the amount actually dropped (may be less if stack is full or different material)
  int dropAt(IsoCoordinate coord, String materialId, int amount) {
    final key = _keyFor(coord);
    final existing = _items[key];

    if (existing != null) {
      // Can only add to same material type
      if (existing.materialId != materialId) {
        return 0; // Can't mix materials
      }
      final added = existing.add(amount);
      if (added > 0) notifyListeners();
      return added;
    } else {
      // Create new dropped item
      final actualAmount = amount.clamp(0, DroppedItem.maxAmount);
      if (actualAmount > 0) {
        _items[key] = DroppedItem(materialId: materialId, amount: actualAmount);
        notifyListeners();
      }
      return actualAmount;
    }
  }

  /// Pick up dropped item at a coordinate
  /// Returns the dropped item (removed from tile), or null if none
  DroppedItem? pickupAt(IsoCoordinate coord) {
    final key = _keyFor(coord);
    final item = _items.remove(key);
    if (item != null) notifyListeners();
    return item;
  }

  /// Pick up a specific amount from a coordinate
  /// Returns the amount actually picked up
  int pickupAmountAt(IsoCoordinate coord, int amount) {
    final key = _keyFor(coord);
    final item = _items[key];
    if (item == null) return 0;

    final removed = item.remove(amount);
    if (item.isEmpty) {
      _items.remove(key);
    }
    if (removed > 0) notifyListeners();
    return removed;
  }

  /// Clear all dropped items
  void clear() {
    _items.clear();
    notifyListeners();
  }

  /// Get all coordinates with dropped items
  List<IsoCoordinate> get allDroppedCoordinates {
    return _items.entries.where((e) => !e.value.isEmpty).map((e) {
      final parts = e.key.split(':');
      return IsoCoordinate(x: int.parse(parts[0]), y: int.parse(parts[1]));
    }).toList();
  }

  /// Get the total count of dropped items
  int get totalDroppedCount =>
      _items.values.fold(0, (sum, item) => sum + item.amount);

  @override
  void dispose() {
    _items.clear();
    super.dispose();
  }
}
