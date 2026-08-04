import 'dropped_item.dart';
import 'inventory.dart';
import '../foliage/foliage_provider.dart';
import '../tiles/tiles.dart';

/// The type of resolved tile action.
enum TileActionType {
  gather,
  gatherFoliage,
  pickup,
  drop,
  enterStructure,
  structureCallback,
  none,
}

/// Result of resolving a [TileAction] against the current game context.
class TileActionResult {
  const TileActionResult({
    required this.type,
    this.materialId,
    this.amount,
    this.foliageId,
  });

  static const none = TileActionResult(type: TileActionType.none);

  final TileActionType type;
  final String? materialId;
  final int? amount;

  /// Set when [type] is [TileActionType.gatherFoliage].
  final String? foliageId;

  @override
  String toString() => 'TileActionResult($type, $materialId x$amount)';
}

/// Context snapshot passed to the resolver so it can decide what to do.
class TileActionContext {
  const TileActionContext({
    required this.friendCarriedMaterial,
    required this.friendCarriedAmount,
    required this.friendInventoryFull,
    required this.droppedItem,
    required this.structureId,
    required this.structureInventory,
    required this.tileMaterial,
    required this.tileOnCooldown,
    this.foliage,
  });

  /// Material the friend is currently carrying (null = empty-handed).
  final String? friendCarriedMaterial;
  final int friendCarriedAmount;
  final bool friendInventoryFull;

  /// Dropped item on this tile (null = nothing dropped here).
  final DroppedItem? droppedItem;

  /// Structure at this tile (null = no structure).
  final String? structureId;
  final Inventory? structureInventory;

  /// Natural tile material (null = barren tile).
  final MaterialYield? tileMaterial;
  final bool tileOnCooldown;

  /// Foliage instance at or near this tile (null = no foliage).
  final FoliageInstance? foliage;

  bool get friendIsCarrying =>
      friendCarriedMaterial != null && friendCarriedAmount > 0;
  bool get hasStructure => structureId != null;
  bool get hasDroppedItem => droppedItem != null && !droppedItem!.isEmpty;
  bool get hasTileMaterial => tileMaterial != null && !tileOnCooldown;
  bool get hasFoliage => foliage != null && !foliage!.isDepleted;
}

/// Determines what should happen when a friend executes a default action at a
/// tile. This is a pure function of the context -- it does not perform the
/// action itself.
class TileActionResolver {
  const TileActionResolver._();

  static TileActionResult resolve(TileActionContext ctx) {
    if (ctx.friendIsCarrying) {
      return _resolveCarrying(ctx);
    }
    return _resolveEmptyHanded(ctx);
  }

  /// Friend is empty-handed: gather, pickup, take from structure, or enter.
  static TileActionResult _resolveEmptyHanded(TileActionContext ctx) {
    if (ctx.hasDroppedItem) {
      return TileActionResult(
        type: TileActionType.pickup,
        materialId: ctx.droppedItem!.materialId,
        amount: ctx.droppedItem!.amount,
      );
    }

    if (ctx.hasStructure && ctx.structureInventory != null) {
      final inv = ctx.structureInventory!;
      if (inv.totalItems > 0) {
        final entries = inv.contents.entries.toList();
        final last = entries.last;
        return TileActionResult(
          type: TileActionType.pickup,
          materialId: last.key,
          amount: last.value.clamp(0, 1),
        );
      }
      return const TileActionResult(type: TileActionType.enterStructure);
    }

    if (ctx.hasFoliage) {
      return TileActionResult(
        type: TileActionType.gatherFoliage,
        materialId: ctx.foliage!.materialId,
        foliageId: ctx.foliage!.id,
      );
    }

    if (ctx.hasTileMaterial) {
      return TileActionResult(
        type: TileActionType.gather,
        materialId: ctx.tileMaterial!.materialId,
      );
    }

    return TileActionResult.none;
  }

  /// Friend is carrying an item: deposit into structure, drop on tile, or
  /// wait if there is no room.
  static TileActionResult _resolveCarrying(TileActionContext ctx) {
    if (ctx.hasStructure && ctx.structureInventory != null) {
      final inv = ctx.structureInventory!;
      final mat = ctx.friendCarriedMaterial!;
      final amt = ctx.friendCarriedAmount;
      // Check if the structure inventory can accept this material.
      if (inv.spaceForMaterial(mat) >= amt) {
        return TileActionResult(
          type: TileActionType.structureCallback,
          materialId: mat,
          amount: amt,
        );
      }
      // No room -- friend idles / waits (same as tile cooldown).
      return TileActionResult.none;
    }

    if (ctx.hasDroppedItem) {
      // Tile already has a dropped item -- no room to drop another.
      return TileActionResult.none;
    }

    return TileActionResult(
      type: TileActionType.drop,
      materialId: ctx.friendCarriedMaterial,
      amount: ctx.friendCarriedAmount,
    );
  }
}
