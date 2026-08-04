import 'dart:math' as math;

/// Represents a collection of materials with capacity limits.
///
/// Structure inventories enforce a slot-based system: at most [maxSlots]
/// different material types, each capped at [maxPerSlot] units.
/// Friend inventories use a simpler total-capacity model.
class Inventory {
  final Map<String, int> _contents = {};
  final int capacity;

  /// Default capacities
  static const int friendCapacity = 16;

  /// Structure inventory: 9 slots x 1000 per slot = 9000
  static const int maxSlots = 9;
  static const int maxPerSlot = 1000;
  static const int structureCapacity = maxSlots * maxPerSlot;

  /// Whether this inventory enforces slot limits (true for structures).
  final bool useSlots;

  Inventory({this.capacity = friendCapacity, this.useSlots = false});

  /// Creates an inventory for a friend (small capacity, no slot limits)
  factory Inventory.forFriend() =>
      Inventory(capacity: friendCapacity, useSlots: false);

  /// Creates an inventory for a structure (slot-based: 9 types x 100 each)
  factory Inventory.forStructure() =>
      Inventory(capacity: structureCapacity, useSlots: true);

  /// Get the amount of a specific material
  int get(String materialId) => _contents[materialId] ?? 0;

  /// Get all materials and their amounts (excludes zero amounts)
  Map<String, int> get contents => Map.unmodifiable(
    Map.fromEntries(_contents.entries.where((e) => e.value > 0)),
  );

  /// Total number of items across all materials
  int get totalItems =>
      _contents.values.fold(0, (sum, amount) => sum + amount);

  /// Number of distinct material types stored (occupied slots)
  int get slotCount =>
      _contents.values.where((amount) => amount > 0).length;

  /// Whether there is at least one empty slot (only meaningful with useSlots)
  bool get hasEmptySlot => slotCount < maxSlots;

  /// Check if inventory is empty
  bool get isEmpty => totalItems == 0;

  /// Check if inventory is at capacity
  bool get isFull => useSlots
      ? slotCount >= maxSlots &&
          _contents.values.every((v) => v >= maxPerSlot)
      : totalItems >= capacity;

  /// Available space in inventory (total, not per-slot)
  int get availableSpace => capacity - totalItems;

  /// How much more of [materialId] can be added, respecting both total capacity
  /// and slot / per-slot limits.
  int spaceForMaterial(String materialId) {
    if (materialId.isEmpty) return 0;
    final currentAmount = get(materialId);
    final isNewType = currentAmount == 0;

    if (useSlots) {
      // If it's a new type and we're out of slots, no room
      if (isNewType && slotCount >= maxSlots) return 0;
      // Cap at maxPerSlot for this type
      final slotSpace = maxPerSlot - currentAmount;
      // Also cap by total capacity
      final totalSpace = capacity - totalItems;
      return math.min(slotSpace, totalSpace).clamp(0, maxPerSlot);
    }

    return (capacity - totalItems).clamp(0, capacity);
  }

  /// Add material to inventory. Returns true if successful.
  ///
  /// For slot-based inventories: rejects if the material is a new type and all
  /// slots are full, or if adding would exceed [maxPerSlot] for that type.
  bool add(String materialId, int amount) {
    if (materialId.isEmpty) return false;
    if (amount <= 0) return false;

    final currentAmount = get(materialId);
    final isNewType = currentAmount == 0;

    if (useSlots) {
      // Reject new type if no empty slots
      if (isNewType && slotCount >= maxSlots) return false;
      // Reject if would exceed per-slot cap
      if (currentAmount + amount > maxPerSlot) return false;
    }

    // Reject if would exceed total capacity
    if (totalItems + amount > capacity) return false;

    _contents[materialId] = currentAmount + amount;
    return true;
  }

  /// Remove material from inventory. Returns true if successful.
  /// Fails if not enough material is available.
  bool remove(String materialId, int amount) {
    if (amount <= 0) return false;
    final current = get(materialId);
    if (current < amount) return false;

    final newAmount = current - amount;
    if (newAmount == 0) {
      _contents.remove(materialId);
    } else {
      _contents[materialId] = newAmount;
    }
    return true;
  }

  /// Check if inventory has enough of all required materials
  bool hasEnough(Map<String, int> requirements) {
    for (final entry in requirements.entries) {
      if (get(entry.key) < entry.value) return false;
    }
    return true;
  }

  /// Consume materials according to requirements. Returns true if successful.
  bool consume(Map<String, int> requirements) {
    if (!hasEnough(requirements)) return false;

    for (final entry in requirements.entries) {
      remove(entry.key, entry.value);
    }
    return true;
  }

  /// Transfer all contents to another inventory. Returns true if successful.
  /// Fails if target doesn't have enough space.
  bool transferAllTo(Inventory target) {
    if (target.availableSpace < totalItems) return false;

    for (final entry in _contents.entries) {
      if (entry.value > 0) {
        target.add(entry.key, entry.value);
      }
    }
    clear();
    return true;
  }

  /// Transfer specific material to another inventory. Returns amount transferred.
  int transferTo(Inventory target, String materialId, int amount) {
    final available = get(materialId);
    final toTransfer = amount.clamp(0, available);
    final canFit = math.min(toTransfer, target.spaceForMaterial(materialId));

    if (canFit > 0) {
      remove(materialId, canFit);
      target.add(materialId, canFit);
    }
    return canFit;
  }

  /// Clear all contents
  void clear() {
    _contents.clear();
  }

  /// Get a human-readable summary of contents
  String get summary {
    if (isEmpty) return 'Empty';

    final parts = <String>[];
    for (final entry in _contents.entries) {
      if (entry.value > 0) {
        parts.add('${entry.value} ${entry.key}');
      }
    }
    return parts.join(', ');
  }

  /// Copy contents from another inventory (for serialization/cloning)
  void copyFrom(Inventory other) {
    _contents.clear();
    for (final entry in other._contents.entries) {
      if (entry.value > 0) {
        _contents[entry.key] = entry.value;
      }
    }
  }

  @override
  String toString() => 'Inventory($summary, $totalItems/$capacity)';
}
