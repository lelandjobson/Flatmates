import 'package:flutter/foundation.dart';

import 'inventory.dart';

/// Global persistent inventory for the player.
///
/// Wraps an [Inventory] with 10 material slots and notifies listeners when
/// contents change, so that the inventory bar UI rebuilds.
class PlayerInventory extends ChangeNotifier {
  static const int playerSlots = 10;
  static const int _perSlot = Inventory.maxPerSlot;

  final Inventory _inventory = Inventory(
    capacity: playerSlots * _perSlot,
    useSlots: true,
  );

  Inventory get inventory => _inventory;

  Map<String, int> get contents => _inventory.contents;
  int get totalItems => _inventory.totalItems;
  bool get isEmpty => _inventory.isEmpty;
  bool get isFull => _inventory.isFull;
  int get slotCount => _inventory.slotCount;

  int get(String materialId) => _inventory.get(materialId);

  bool add(String materialId, int amount) {
    final ok = _inventory.add(materialId, amount);
    if (ok) notifyListeners();
    return ok;
  }

  bool remove(String materialId, int amount) {
    final ok = _inventory.remove(materialId, amount);
    if (ok) notifyListeners();
    return ok;
  }

  void clear() {
    _inventory.clear();
    notifyListeners();
  }

  /// Call after external code modifies [inventory] directly (e.g. via
  /// [BlueprintTask.execute]).
  void markChanged() => notifyListeners();

  /// Ordered slot data for the UI bar: list of (materialId, amount) for each
  /// occupied slot, padded to [playerSlots] with nulls.
  List<({String? materialId, int amount})> get slots {
    final entries = _inventory.contents.entries.toList();
    return List.generate(playerSlots, (i) {
      if (i < entries.length) {
        return (materialId: entries[i].key, amount: entries[i].value);
      }
      return (materialId: null, amount: 0);
    });
  }
}
