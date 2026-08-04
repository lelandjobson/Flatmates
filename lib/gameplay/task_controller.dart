import 'package:flutter/foundation.dart';
import '../data/placed_asset_database.dart';
import '../foliage/foliage_provider.dart';
import '../rendering/iso/iso_coordinate.dart';
import '../tiles/tiles.dart';
import '../user/friend_manager.dart';
import '../user/friend_provider.dart';
import 'crafting_database.dart';
import 'pathfinder.dart';
import 'task.dart';

/// Callback types for task events
typedef OnGatherComplete =
    void Function(
      String friendId,
      IsoCoordinate tile,
      String materialId,
      int amount,
    );
typedef OnFoliageGatherComplete =
    void Function(
      String friendId,
      String foliageId,
      String materialId,
      int amount,
      bool removed,
    );
typedef OnDeliverComplete = void Function(String friendId, String structureId);
typedef OnCraftComplete = void Function(String friendId, CraftingRecipe recipe);

/// Controller for managing task creation and execution
class TaskController extends ChangeNotifier {
  TaskController({
    required this.friendManager,
    required this.friendProvider,
    required this.placedAssetDatabase,
    required this.foliageProvider,
    required this.craftingDatabase,
    required this.isWalkable,
    required this.getTileMaterial,
  }) : pathfinder = Pathfinder(allowDiagonal: false);

  final FriendManager friendManager;
  final FriendProvider friendProvider;
  final PlacedAssetDatabase placedAssetDatabase;
  final FoliageProvider foliageProvider;
  final CraftingDatabase craftingDatabase;
  final Pathfinder pathfinder;

  /// Callback to check if a tile is walkable
  final bool Function(IsoCoordinate) isWalkable;

  /// Callback to get the material yield from a tile
  final MaterialYield? Function(IsoCoordinate) getTileMaterial;

  /// Event callbacks
  OnGatherComplete? onGatherComplete;
  OnFoliageGatherComplete? onFoliageGatherComplete;
  OnDeliverComplete? onDeliverComplete;
  OnCraftComplete? onCraftComplete;

  /// Create a gather task for a friend
  /// Returns the task if successfully created, null otherwise
  Task? createGatherTask({
    required String friendId,
    required IsoCoordinate targetTile,
    bool returnToStart = true,
  }) {
    final friendState = friendManager.getFriendState(friendId);
    if (friendState == null) return null;

    final friend = friendProvider.getFriendById(friendId);
    if (friend == null) return null;

    // Get material from tile
    final materialYield = getTileMaterial(targetTile);
    if (materialYield == null || materialYield.materialId.isEmpty) {
      return null;
    }

    // Find path to target
    final startCoord = IsoCoordinate(
      x: friendState.position.x,
      y: friendState.position.y,
      h: friendState.position.h,
    );
    final path = pathfinder.findPathExcludingStart(
      startCoord,
      targetTile,
      isWalkable,
    );

    if (path == null) return null;

    // Store start position for return
    friendState.gatherStartPosition = friendState.position;

    // Calculate total turns
    final pathLength = path.length;
    final gatherTurns = 1;
    final returnPath = returnToStart ? pathLength : 0;
    final totalTurns = pathLength + gatherTurns + returnPath;

    // Create task
    final task = Task.gatherNoReturn(
      id: TaskIdGenerator.generate(),
      target: targetTile,
      pathLength: returnToStart ? totalTurns : pathLength + gatherTurns,
    );
    task.shouldRepeat = friendState.taskQueue.repeatCurrent;

    // Queue movement actions to target
    for (final coord in path) {
      friendState.queueAction(
        MovementAction(
          friendId: friendId,
          from: _isoToTile(startCoord),
          to: _isoToTile(coord),
          useTurnBasedTiming: true,
        ),
      );
    }

    // Queue gather action
    friendState.queueAction(
      GatherAction(
        friendId: friendId,
        targetCoordinate: _isoToTile(targetTile),
        materialToGather: materialYield.materialId,
        amountToGather: 16, // 16 material units per gather
        onGatherComplete: (materialId, amount) {
          onGatherComplete?.call(friendId, targetTile, materialId, amount);
        },
      ),
    );

    // Queue return movement if needed
    if (returnToStart && friendState.gatherStartPosition != null) {
      final returnPathCoords = pathfinder.findPathExcludingStart(
        targetTile,
        startCoord,
        isWalkable,
      );
      if (returnPathCoords != null) {
        var current = targetTile;
        for (final coord in returnPathCoords) {
          friendState.queueAction(
            MovementAction(
              friendId: friendId,
              from: _isoToTile(current),
              to: _isoToTile(coord),
              useTurnBasedTiming: true,
            ),
          );
          current = coord;
        }
      }
    }

    // Add to task queue
    friendState.taskQueue.enqueue(task);
    notifyListeners();

    return task;
  }

  /// Create a gather task targeting a foliage instance (tree, bush, etc.).
  ///
  /// The friend walks to the tile containing the foliage, then performs a
  /// single gather action that yields the foliage's material and depletes it.
  Task? createFoliageGatherTask({
    required String friendId,
    required FoliageInstance foliage,
    bool returnToStart = true,
  }) {
    final friendState = friendManager.getFriendState(friendId);
    if (friendState == null) return null;

    final friend = friendProvider.getFriendById(friendId);
    if (friend == null) return null;
    if (foliage.isDepleted) return null;

    final targetTile = IsoCoordinate(x: foliage.tileX, y: foliage.tileY, h: 0);

    final startCoord = IsoCoordinate(
      x: friendState.position.x,
      y: friendState.position.y,
      h: friendState.position.h,
    );
    final path = pathfinder.findPathExcludingStart(
      startCoord,
      targetTile,
      isWalkable,
    );
    if (path == null) return null;

    friendState.gatherStartPosition = friendState.position;

    final pathLength = path.length;
    final gatherTurns = 1;
    final returnPathLen = returnToStart ? pathLength : 0;
    final totalTurns = pathLength + gatherTurns + returnPathLen;

    final task = Task.gatherNoReturn(
      id: TaskIdGenerator.generate(),
      target: targetTile,
      pathLength: returnToStart ? totalTurns : pathLength + gatherTurns,
    );
    task.shouldRepeat = friendState.taskQueue.repeatCurrent;

    for (final coord in path) {
      friendState.queueAction(
        MovementAction(
          friendId: friendId,
          from: _isoToTile(startCoord),
          to: _isoToTile(coord),
          useTurnBasedTiming: true,
        ),
      );
    }

    friendState.queueAction(
      FoliageGatherAction(
        friendId: friendId,
        targetFoliageId: foliage.id,
        materialId: foliage.materialId,
        amountPerGather: 16,
        onGatherComplete: (foliageId, materialId, amount) {
          final removed = foliageProvider.depleteGather(foliageId);
          onFoliageGatherComplete?.call(
            friendId, foliageId, materialId, amount, removed,
          );
        },
      ),
    );

    if (returnToStart && friendState.gatherStartPosition != null) {
      final returnPathCoords = pathfinder.findPathExcludingStart(
        targetTile,
        startCoord,
        isWalkable,
      );
      if (returnPathCoords != null) {
        var current = targetTile;
        for (final coord in returnPathCoords) {
          friendState.queueAction(
            MovementAction(
              friendId: friendId,
              from: _isoToTile(current),
              to: _isoToTile(coord),
              useTurnBasedTiming: true,
            ),
          );
          current = coord;
        }
      }
    }

    friendState.taskQueue.enqueue(task);
    notifyListeners();

    return task;
  }

  /// Create a move task for a friend
  Task? createMoveTask({
    required String friendId,
    required IsoCoordinate destination,
  }) {
    final friendState = friendManager.getFriendState(friendId);
    if (friendState == null) return null;

    // Find path to destination
    final startCoord = IsoCoordinate(
      x: friendState.position.x,
      y: friendState.position.y,
      h: friendState.position.h,
    );
    final path = pathfinder.findPathExcludingStart(
      startCoord,
      destination,
      isWalkable,
    );

    if (path == null) return null;

    // Create task
    final task = Task.move(
      id: TaskIdGenerator.generate(),
      destination: destination,
      pathLength: path.length,
    );

    // Queue movement actions
    var current = startCoord;
    for (final coord in path) {
      friendState.queueAction(
        MovementAction(
          friendId: friendId,
          from: _isoToTile(current),
          to: _isoToTile(coord),
          useTurnBasedTiming: true,
        ),
      );
      current = coord;
    }

    friendState.taskQueue.enqueue(task);
    notifyListeners();

    return task;
  }

  /// Create a craft task for a friend at a structure
  Task? createCraftTask({
    required String friendId,
    required String structureId,
    required IsoCoordinate structureCoord,
    required CraftingRecipe recipe,
  }) {
    final friendState = friendManager.getFriendState(friendId);
    if (friendState == null) return null;

    // Check if friend is at structure
    final friendCoord = IsoCoordinate(
      x: friendState.position.x,
      y: friendState.position.y,
      h: friendState.position.h,
    );
    if (friendCoord != structureCoord) {
      // Friend must be at structure to craft
      return null;
    }

    // Check if structure has required materials
    final structureInventory = placedAssetDatabase.getStructureInventory(
      structureId,
    );
    if (!recipe.canCraftWith(structureInventory)) {
      return null;
    }

    // Create task
    final task = Task.craft(
      id: TaskIdGenerator.generate(),
      recipe: recipe,
      structureId: structureId,
      structureCoord: structureCoord,
    );
    task.shouldRepeat = friendState.taskQueue.repeatCurrent;

    // Queue craft action
    friendState.queueAction(
      CraftAction(
        friendId: friendId,
        structureId: structureId,
        recipe: recipe,
        getStructureInventory: (id) =>
            placedAssetDatabase.getStructureInventory(id),
        onCraftComplete: (completedRecipe) {
          // Add crafted item to friend's inventory
          friendState.craftedItems.add(
            CraftedItem(
              recipeId: completedRecipe.id,
              name: completedRecipe.name,
              resultType: completedRecipe.resultType,
            ),
          );
          onCraftComplete?.call(friendId, completedRecipe);
        },
      ),
    );

    friendState.taskQueue.enqueue(task);
    notifyListeners();

    return task;
  }

  /// Cancel all tasks for a friend
  void cancelAllTasks(String friendId) {
    final friendState = friendManager.getFriendState(friendId);
    if (friendState == null) return;

    friendState.clearQueue();
    friendState.taskQueue.cancelAll();
    notifyListeners();
  }

  /// Toggle repeat mode for a friend
  void toggleRepeat(String friendId) {
    final friendState = friendManager.getFriendState(friendId);
    if (friendState == null) return;

    friendState.taskQueue.repeatCurrent = !friendState.taskQueue.repeatCurrent;
    notifyListeners();
  }

  /// Helper to convert IsoCoordinate to TileCoordinate
  TileCoordinate _isoToTile(IsoCoordinate coord) {
    return TileCoordinate(x: coord.x, y: coord.y, z: coord.z, h: coord.h);
  }

  /// Get craftable recipes at a structure
  List<CraftingRecipe> getCraftableRecipes(String structureId) {
    final inventory = placedAssetDatabase.getStructureInventoryIfExists(
      structureId,
    );
    if (inventory == null) return [];
    return craftingDatabase.searchCraftable(inventory);
  }
}
