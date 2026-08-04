import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../gameplay/crafting_database.dart';
import '../gameplay/inventory.dart';
import '../gameplay/task.dart';
import '../geometry/geometry.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/iso/friend_expression.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/scene.dart';
import '../tiles/tiles.dart';
import 'friend_provider.dart';

/// Abstract base class for friend actions
abstract class FriendAction {
  const FriendAction({required this.friendId});

  final String friendId;

  /// Duration this action takes to complete in seconds
  double getDuration(Friend friend);

  /// Called when the action starts executing
  void onStart(FriendState state);

  /// Called during action execution (progress is 0.0 to 1.0)
  void onUpdate(FriendState state, double progress);

  /// Called when the action completes
  void onComplete(FriendState state);
}

/// Action for moving a friend from one tile to another
class MovementAction extends FriendAction {
  const MovementAction({
    required super.friendId,
    required this.from,
    required this.to,
    this.useTurnBasedTiming = true,
  });

  final TileCoordinate from;
  final TileCoordinate to;

  /// Whether to use turn-based timing (0.5s per tile) or speed-based
  final bool useTurnBasedTiming;

  @override
  double getDuration(Friend friend) {
    // With diagonal movement, distance is the maximum of dx, dy, dh (Chebyshev distance)
    final distance = _calculateDistance(from, to);

    if (useTurnBasedTiming) {
      // Turn-based: 0.5 seconds per tile (1 turn per tile)
      return distance * turnDurationSeconds;
    } else {
      // Speed-based: use friend's tile speed
      return distance / friend.stats.tileSpeed;
    }
  }

  double _calculateDistance(TileCoordinate a, TileCoordinate b) {
    final dx = (b.x - a.x).abs();
    final dy = (b.y - a.y).abs();
    final dh = (b.h - a.h).abs();
    // Chebyshev distance: with diagonal movement, distance is the max dimension
    return math.max(dx, math.max(dy, dh)).toDouble();
  }

  @override
  void onStart(FriendState state) {
    // Movement starts from the current position
  }

  @override
  void onUpdate(FriendState state, double progress) {
    // Interpolate position between from and to
    final fromX = from.x.toDouble();
    final fromY = from.y.toDouble();
    final fromH = from.h.toDouble();
    final toX = to.x.toDouble();
    final toY = to.y.toDouble();
    final toH = to.h.toDouble();

    state.position = TileCoordinate(
      x: (fromX + (toX - fromX) * progress).round(),
      y: (fromY + (toY - fromY) * progress).round(),
      z: from.z, // Keep same zoom level
      h: (fromH + (toH - fromH) * progress).round(),
    );
  }

  @override
  void onComplete(FriendState state) {
    state.position = to;
  }

  @override
  String toString() =>
      'MovementAction(friendId: $friendId, from: $from, to: $to)';
}

/// A chain of single-tile movement actions
class MovementChain {
  MovementChain({required this.friendId, required this.actions})
    : assert(actions.isNotEmpty, 'MovementChain must have at least one action');

  final String friendId;
  final List<MovementAction> actions;

  int get length => actions.length;

  TileCoordinate get start => actions.first.from;
  TileCoordinate get destination => actions.last.to;

  /// Create a movement chain from start to end, breaking it into single-tile steps
  static MovementChain create({
    required String friendId,
    required TileCoordinate from,
    required TileCoordinate to,
  }) {
    final actions = _calculatePath(friendId, from, to);
    return MovementChain(friendId: friendId, actions: actions);
  }

  /// Calculate a path allowing diagonal movement (move in multiple dimensions simultaneously)
  static List<MovementAction> _calculatePath(
    String friendId,
    TileCoordinate from,
    TileCoordinate to,
  ) {
    final actions = <MovementAction>[];
    var current = from;

    // Move diagonally: advance in all dimensions simultaneously until we reach target in each
    while (current != to) {
      final nextX = current.x == to.x
          ? current.x
          : (current.x < to.x ? current.x + 1 : current.x - 1);

      final nextY = current.y == to.y
          ? current.y
          : (current.y < to.y ? current.y + 1 : current.y - 1);

      final nextH = current.h == to.h
          ? current.h
          : (current.h < to.h ? current.h + 1 : current.h - 1);

      final next = TileCoordinate(
        x: nextX,
        y: nextY,
        z: current.z, // Keep same zoom level
        h: nextH,
      );

      actions.add(MovementAction(friendId: friendId, from: current, to: next));
      current = next;
    }

    return actions;
  }

  @override
  String toString() =>
      'MovementChain(friendId: $friendId, steps: ${actions.length}, '
      'from: $start, to: $destination)';
}

/// Action for gathering resources from a tile
class GatherAction extends FriendAction {
  GatherAction({
    required super.friendId,
    required this.targetCoordinate,
    required this.materialToGather,
    required this.amountToGather,
    this.onGatherComplete,
  });

  final TileCoordinate targetCoordinate;
  final String materialToGather;
  final int amountToGather;

  /// Callback when gathering is complete (to update tile yields, etc.)
  final void Function(String materialId, int amount)? onGatherComplete;

  @override
  double getDuration(Friend friend) {
    // 1 turn = 0.5 seconds for gathering
    return turnDurationSeconds;
  }

  @override
  void onStart(FriendState state) {
    // Gathering starts - friend should be at targetCoordinate
  }

  @override
  void onUpdate(FriendState state, double progress) {
    // Gathering animation could go here
  }

  @override
  void onComplete(FriendState state) {
    // Add material to friend's inventory
    final added = state.inventory.add(materialToGather, amountToGather);
    if (added) {
      onGatherComplete?.call(materialToGather, amountToGather);
    }
  }

  @override
  String toString() =>
      'GatherAction(friendId: $friendId, material: $materialToGather, amount: $amountToGather)';
}

/// Action for gathering resources from a foliage instance (tree, bush, etc.).
///
/// Unlike [GatherAction] which gathers from a tile, this gathers from a
/// specific foliage object and depletes it. When the foliage is fully depleted
/// (remainingGathers reaches 0), it is removed.
class FoliageGatherAction extends FriendAction {
  FoliageGatherAction({
    required super.friendId,
    required this.targetFoliageId,
    required this.materialId,
    this.amountPerGather = 1,
    this.onGatherComplete,
    this.onAppearanceUpdate,
  });

  final String targetFoliageId;
  final String materialId;
  final int amountPerGather;

  /// Called when gather completes so the caller can deplete the foliage.
  final void Function(String foliageId, String materialId, int amount)?
      onGatherComplete;

  /// Called during the gather animation to update visual appearance (shake,
  /// shrink, etc.). Progress goes from 0.0 to 1.0.
  final void Function(String foliageId, double progress)? onAppearanceUpdate;

  @override
  double getDuration(Friend friend) => turnDurationSeconds;

  @override
  void onStart(FriendState state) {}

  @override
  void onUpdate(FriendState state, double progress) {
    onAppearanceUpdate?.call(targetFoliageId, progress);
  }

  @override
  void onComplete(FriendState state) {
    final added = state.inventory.add(materialId, amountPerGather);
    if (added) {
      onGatherComplete?.call(targetFoliageId, materialId, amountPerGather);
    }
  }

  @override
  String toString() =>
      'FoliageGatherAction(friendId: $friendId, foliage: $targetFoliageId, material: $materialId)';
}

/// Action for delivering materials to a structure
class DeliverAction extends FriendAction {
  DeliverAction({
    required super.friendId,
    required this.structureId,
    required this.structureCoordinate,
    required this.getStructureInventory,
  });

  final String structureId;
  final TileCoordinate structureCoordinate;

  /// Callback to get the structure's inventory
  final Inventory Function(String structureId) getStructureInventory;

  @override
  double getDuration(Friend friend) {
    // 1 turn = 0.5 seconds for delivery
    return turnDurationSeconds;
  }

  @override
  void onStart(FriendState state) {
    // Delivery starts - friend should be at structure
  }

  @override
  void onUpdate(FriendState state, double progress) {
    // Delivery animation could go here
  }

  @override
  void onComplete(FriendState state) {
    // Transfer all materials from friend to structure
    final structureInventory = getStructureInventory(structureId);
    state.inventory.transferAllTo(structureInventory);
  }

  @override
  String toString() =>
      'DeliverAction(friendId: $friendId, structureId: $structureId)';
}

/// Action for crafting an item at a structure
class CraftAction extends FriendAction {
  CraftAction({
    required super.friendId,
    required this.structureId,
    required this.recipe,
    required this.getStructureInventory,
    this.onCraftComplete,
  });

  final String structureId;
  final CraftingRecipe recipe;

  /// Callback to get the structure's inventory
  final Inventory Function(String structureId) getStructureInventory;

  /// Callback when crafting is complete
  final void Function(CraftingRecipe recipe)? onCraftComplete;

  @override
  double getDuration(Friend friend) {
    // Duration based on recipe turns
    return recipe.turnsToComplete * turnDurationSeconds;
  }

  @override
  void onStart(FriendState state) {
    // Crafting starts - consume ingredients from structure
    final structureInventory = getStructureInventory(structureId);
    structureInventory.consume(recipe.scaledIngredients);
  }

  @override
  void onUpdate(FriendState state, double progress) {
    // Crafting animation could go here
  }

  @override
  void onComplete(FriendState state) {
    // Add crafted item to friend's inventory
    // For now, we'll represent crafted items as a special material or just log it
    // In a full implementation, you'd have an item system separate from materials
    onCraftComplete?.call(recipe);
  }

  @override
  String toString() =>
      'CraftAction(friendId: $friendId, recipe: ${recipe.name})';
}

/// Represents a crafted item (result of crafting)
class CraftedItem {
  const CraftedItem({
    required this.recipeId,
    required this.name,
    required this.resultType,
  });

  final String recipeId;
  final String name;
  final String resultType;

  @override
  String toString() => 'CraftedItem($name)';
}

/// Runtime state for a friend (position, actions, inventory, tasks, etc.)
class FriendState {
  FriendState({required this.friendId, required TileCoordinate position})
    : _position = position,
      inventory = Inventory.forFriend(),
      taskQueue = TaskQueue();

  final String friendId;
  TileCoordinate _position;
  TileCoordinate get position => _position;
  set position(TileCoordinate value) => _position = value;

  /// Friend's inventory for carrying materials
  final Inventory inventory;

  /// Task queue for high-level tasks (gather, deliver, craft)
  final TaskQueue taskQueue;

  /// Starting position for gather tasks (to return to)
  TileCoordinate? gatherStartPosition;

  /// Facing direction in sprite-ring degrees (0-360).
  /// See [SimpleFriendState.facingAngleDeg] for the convention.
  double facingAngleDeg = 0.0;

  /// Current emotional expression (holds until changed; no auto-restore to neutral).
  ExpressionType emotionalState = ExpressionType.neutral;

  /// List of crafted items in inventory
  final List<CraftedItem> craftedItems = [];

  final List<FriendAction> _actionQueue = [];
  List<FriendAction> get actionQueue => List.unmodifiable(_actionQueue);

  FriendAction? _currentAction;
  FriendAction? get currentAction => _currentAction;

  double _currentActionProgress = 0.0;
  double get currentActionProgress => _currentActionProgress;

  double _currentActionElapsed = 0.0;

  bool get isIdle => _currentAction == null && _actionQueue.isEmpty;
  bool get isBusy => _currentAction != null;

  /// Check if friend has any tasks pending
  bool get hasTasks => taskQueue.hasTasks;

  void queueAction(FriendAction action) {
    _actionQueue.add(action);
  }

  void clearQueue() {
    _actionQueue.clear();
  }

  void _startNextAction(Friend friend) {
    if (_actionQueue.isEmpty) {
      return;
    }
    _currentAction = _actionQueue.removeAt(0);
    _currentActionProgress = 0.0;
    _currentActionElapsed = 0.0;
    _currentAction!.onStart(this);
  }

  void _updateAction(Friend friend, double deltaSeconds) {
    final action = _currentAction;
    if (action == null) {
      return;
    }

    _currentActionElapsed += deltaSeconds;
    final duration = action.getDuration(friend);
    _currentActionProgress = (duration > 0)
        ? (_currentActionElapsed / duration).clamp(0.0, 1.0)
        : 1.0;

    action.onUpdate(this, _currentActionProgress);

    if (_currentActionProgress >= 1.0) {
      action.onComplete(this);
      _currentAction = null;
      _currentActionProgress = 0.0;
      _currentActionElapsed = 0.0;
      _startNextAction(friend);
    }
  }
}

/// Manages friends, their positions, and actions
class FriendManager {
  FriendManager({
    required Scene scene,
    required FriendProvider friendProvider,
    required this.tileSize,
    required this.heightPerLevel,
  }) : _scene = scene,
       _friendProvider = friendProvider {
    _initializeFriends();
    _buildFriendMeshes();
    _startUpdateLoop();
  }

  final Scene _scene;
  final FriendProvider _friendProvider;
  final double tileSize;
  final double heightPerLevel;

  final Map<String, FriendState> _friendStates = {};
  final Map<String, Mesh> _friendMeshes = {}; // Cache of friend meshes
  final Map<String, bool> _friendContainment =
      {}; // Track if friend is contained
  final ValueNotifier<Map<String, FriendState>> friendStatesNotifier =
      ValueNotifier({});
  final ValueNotifier<Map<TileCoordinate, List<String>>>
  containedFriendsNotifier = ValueNotifier(
    {},
  ); // Map tile coordinates to contained friend IDs

  Timer? _updateTimer;
  DateTime _lastUpdate = DateTime.now();
  bool _isDisposed = false;

  /// Total elapsed game time in seconds
  double _totalElapsedTime = 0.0;

  /// Total turns elapsed (for debug display)
  int get totalTurns => (_totalElapsedTime / turnDurationSeconds).floor();

  /// Total elapsed time for debug display
  double get totalElapsedTime => _totalElapsedTime;

  /// Last action log for debug display
  final List<String> _actionLog = [];
  List<String> get actionLog => List.unmodifiable(_actionLog);

  /// Add to action log (keeps last 10 entries)
  void _logAction(String message) {
    _actionLog.add(message);
    if (_actionLog.length > 10) {
      _actionLog.removeAt(0);
    }
  }

  // Callback to check if a tile has a structure
  bool Function(TileCoordinate)? hasStructureAt;

  void _initializeFriends() {
    for (final friend in _friendProvider.friends) {
      // Initialize friends at origin by default
      _friendStates[friend.id] = FriendState(
        friendId: friend.id,
        position: const TileCoordinate(x: 0, y: 0, z: 0, h: 0),
      );
    }
    _notifyStateChange();
  }

  void _startUpdateLoop() {
    _updateTimer = Timer.periodic(
      const Duration(milliseconds: 16), // ~60 FPS
      (_) => _update(),
    );
  }

  void _update() {
    if (_isDisposed) {
      return;
    }

    final now = DateTime.now();
    final deltaSeconds = now.difference(_lastUpdate).inMilliseconds / 1000.0;
    _lastUpdate = now;

    // Track total elapsed time
    _totalElapsedTime += deltaSeconds;

    bool hasChanges = false;
    for (final friend in _friendProvider.friends) {
      final state = _friendStates[friend.id];
      if (state == null) continue;

      if (state._actionQueue.isNotEmpty && state._currentAction == null) {
        state._startNextAction(friend);
        hasChanges = true;

        // Log action start
        final action = state.currentAction;
        if (action != null) {
          _logAction('${friend.name} started ${_getActionDescription(action)}');
        }
      }

      if (state.isBusy) {
        final actionBefore = state.currentAction;
        state._updateAction(friend, deltaSeconds);
        hasChanges = true;

        // Check if action completed
        if (actionBefore != null && state.currentAction != actionBefore) {
          _logAction(
            '${friend.name} completed ${_getActionDescription(actionBefore)}',
          );
        }
      }
    }

    if (hasChanges) {
      _updateMeshes();
      _notifyStateChange();
    }
  }

  /// Get human-readable action description
  String _getActionDescription(FriendAction action) {
    if (action is MovementAction) {
      return 'moving to (${action.to.x}, ${action.to.y})';
    } else if (action is GatherAction) {
      return 'gathering ${action.amountToGather} ${action.materialToGather.toLowerCase()}';
    } else if (action is DeliverAction) {
      return 'delivering to structure';
    } else if (action is CraftAction) {
      return 'crafting ${action.recipe.name}';
    }
    return action.runtimeType.toString();
  }

  void _notifyStateChange() {
    friendStatesNotifier.value = Map.unmodifiable(_friendStates);
  }

  /// Build all friend meshes once and cache them
  void _buildFriendMeshes() {
    for (final friend in _friendProvider.friends) {
      final state = _friendStates[friend.id];
      if (state != null && !_friendMeshes.containsKey(friend.id)) {
        final mesh = _createFriendMesh(friend);
        _friendMeshes[friend.id] = mesh;
        _updateMeshPosition(mesh, state.position);
      }
    }
    _addFriendMeshesToScene();
  }

  /// Update friend mesh positions without rebuilding geometry
  void _updateMeshes() {
    _updateContainment();

    for (final friend in _friendProvider.friends) {
      final state = _friendStates[friend.id];
      final mesh = _friendMeshes[friend.id];
      if (state != null && mesh != null) {
        _updateMeshPosition(mesh, state.position);
      }
    }
    _scene.markNeedsPaint();
  }

  /// Force a containment check (useful when tiles change)
  void forceContainmentUpdate() {
    // ignore: avoid_print
    print('[FriendManager] Force containment update requested');
    _updateContainment();
  }

  /// Update containment status and visibility for all friends
  void _updateContainment() {
    final newContainment = <TileCoordinate, List<String>>{};

    // ignore: avoid_print
    print('[FriendManager._updateContainment] Starting containment check');
    // ignore: avoid_print
    print(
      '[FriendManager._updateContainment] hasStructureAt callback is ${hasStructureAt == null ? "NULL" : "set"}',
    );

    for (final friend in _friendProvider.friends) {
      final state = _friendStates[friend.id];
      if (state == null) {
        // ignore: avoid_print
        print('[FriendManager]   ${friend.name} has no state, skipping');
        continue;
      }

      final position = state.position;
      final wasContained = _friendContainment[friend.id] ?? false;

      // Check if friend is on a tile with a structure
      // ignore: avoid_print
      print(
        '[FriendManager] Checking ${friend.name} at (${position.x}, ${position.y}, z=${position.z}, h=${position.h})',
      );

      if (hasStructureAt == null) {
        // ignore: avoid_print
        print('[FriendManager]   -> hasStructureAt is NULL, cannot check!');
      }

      final isContained = hasStructureAt?.call(position) ?? false;
      // ignore: avoid_print
      print('[FriendManager]   -> isContained: $isContained');
      _friendContainment[friend.id] = isContained;

      if (isContained) {
        // Add to containment map
        newContainment.putIfAbsent(position, () => []).add(friend.id);
        // Debug: print containment
        if (!wasContained) {
          // ignore: avoid_print
          print(
            '[FriendManager] ${friend.name} entered structure at (${position.x}, ${position.y}, z=${position.z})',
          );
        }
      } else if (wasContained) {
        // ignore: avoid_print
        print(
          '[FriendManager] ${friend.name} left structure at (${position.x}, ${position.y}, z=${position.z})',
        );
      }

      // Update mesh visibility if containment changed
      if (wasContained != isContained) {
        _updateFriendVisibility(friend.id, isContained);
      }
    }

    if (newContainment.isNotEmpty) {
      // ignore: avoid_print
      print(
        '[FriendManager] Contained friends at ${newContainment.length} locations: ${newContainment.entries.map((e) => '(${e.key.x},${e.key.y},z=${e.key.z}): ${e.value.length} friends').join(', ')}',
      );
    }

    containedFriendsNotifier.value = Map.unmodifiable(newContainment);
  }

  /// Update friend mesh visibility based on containment
  void _updateFriendVisibility(String friendId, bool isContained) {
    // Need to rebuild scene meshes to show/hide friend
    _addFriendMeshesToScene();
  }

  /// Add friend meshes to the scene, ensuring they render on top
  /// Only adds friends that are not contained in structures
  void _addFriendMeshesToScene() {
    // Get all existing meshes
    final existingMeshes = _scene.meshes.toList();

    // Remove old friend meshes
    existingMeshes.removeWhere((mesh) => mesh.id.startsWith('friend_'));

    // Add cached friend meshes on top, but only if not contained
    final friendMeshes = <Mesh>[];
    for (final entry in _friendMeshes.entries) {
      final friendId = entry.key;
      final mesh = entry.value;
      final isContained = _friendContainment[friendId] ?? false;

      // Only add mesh if friend is NOT contained
      if (!isContained) {
        friendMeshes.add(mesh);
      }
    }

    // Set all meshes with friends on top (rendered last)
    _scene.setMeshes([...existingMeshes, ...friendMeshes]);
  }

  /// Create a friend mesh once with geometry that will be reused
  Mesh _createFriendMesh(Friend friend) {
    final meshId = 'friend_${friend.id}';

    // Friends are 0.5 tile width (0.25 area when viewed from above)
    // This makes them small enough to be clearly distinguishable from assets
    final scale = calculateGeometryScale(
      friend.geometryType,
      0.5, // Half tile width = 1/4 area from above
      tileSize: tileSize,
    );

    final feature = GeometryFeature(
      id: friend.id,
      geometry: friend.geometryType,
      scale: scale,
      highlightOnClick: true,
    );

    // Build geometry once - no need for stable seed since we're not rebuilding
    final geometry = buildGeometry(feature);

    final mesh = Mesh(
      id: meshId,
      name: 'Friend ${friend.name}',
      geometry: geometry,
      material: const MaterialModel.rainbow(doubleSided: true),
      highlightOnClick: true,
    );

    return mesh;
  }

  /// Update a friend mesh's position without rebuilding geometry
  void _updateMeshPosition(Mesh mesh, TileCoordinate position) {
    final baseX = position.x * tileSize;
    final baseZ = position.y * tileSize;
    // Add a small elevation offset to ensure friends render above tile objects
    final baseY = position.h * heightPerLevel + 5.0;
    mesh.setPosition(Vector3(baseX, baseY, baseZ));
  }

  /// Get the state for a specific friend
  FriendState? getFriendState(String friendId) {
    return _friendStates[friendId];
  }

  /// Get all friend states
  Map<String, FriendState> get friendStates => Map.unmodifiable(_friendStates);

  /// Set a friend's position
  void setFriendPosition(String friendId, TileCoordinate position) {
    final state = _friendStates[friendId];
    final mesh = _friendMeshes[friendId];
    if (state != null && mesh != null) {
      state.position = position;
      _updateMeshPosition(mesh, position);
      _scene.markNeedsPaint();
      _notifyStateChange();
    }
  }

  /// Queue an action for a friend
  void queueAction(FriendAction action) {
    final state = _friendStates[action.friendId];
    if (state != null) {
      state.queueAction(action);
      _notifyStateChange();
    }
  }

  /// Queue multiple actions for a friend
  void queueActions(List<FriendAction> actions) {
    for (final action in actions) {
      queueAction(action);
    }
  }

  /// Clear all queued actions for a friend
  void clearFriendQueue(String friendId) {
    final state = _friendStates[friendId];
    if (state != null) {
      state.clearQueue();
      _notifyStateChange();
    }
  }

  /// Move a friend to a specific tile coordinate (direct movement)
  void moveFriendTo(String friendId, TileCoordinate destination) {
    final state = _friendStates[friendId];
    if (state != null) {
      final action = MovementAction(
        friendId: friendId,
        from: state.position,
        to: destination,
      );
      queueAction(action);
    }
  }

  /// Queue a movement chain (series of single-tile movements)
  void queueMovementChain(MovementChain chain) {
    queueActions(chain.actions);
  }

  /// Create and queue a movement chain from current position to destination
  void moveChainTo(String friendId, TileCoordinate destination) {
    final state = _friendStates[friendId];
    if (state != null) {
      final chain = MovementChain.create(
        friendId: friendId,
        from: state.position,
        to: destination,
      );
      queueMovementChain(chain);
    }
  }

  /// Get friends at a specific tile coordinate
  List<Friend> getFriendsAtCoordinate(TileCoordinate coordinate) {
    final result = <Friend>[];
    for (final friend in _friendProvider.friends) {
      final state = _friendStates[friend.id];
      if (state != null && state.position == coordinate) {
        result.add(friend);
      }
    }
    return result;
  }

  /// Get friends within a certain radius of a coordinate
  List<Friend> getFriendsNearCoordinate(TileCoordinate center, int radius) {
    final result = <Friend>[];
    for (final friend in _friendProvider.friends) {
      final state = _friendStates[friend.id];
      if (state != null) {
        final dx = (state.position.x - center.x).abs();
        final dy = (state.position.y - center.y).abs();
        if (dx <= radius && dy <= radius) {
          result.add(friend);
        }
      }
    }
    return result;
  }

  /// Check if a friend is idle (no current or queued actions)
  bool isFriendIdle(String friendId) {
    final state = _friendStates[friendId];
    return state?.isIdle ?? true;
  }

  /// Check if a friend is busy (has a current action)
  bool isFriendBusy(String friendId) {
    final state = _friendStates[friendId];
    return state?.isBusy ?? false;
  }

  /// Check if a friend is contained in a structure
  bool isFriendContained(String friendId) {
    return _friendContainment[friendId] ?? false;
  }

  /// Get all friends contained at a specific tile coordinate
  List<Friend> getContainedFriendsAt(TileCoordinate coordinate) {
    final friendIds = containedFriendsNotifier.value[coordinate] ?? [];
    return friendIds
        .map((id) => _friendProvider.getFriendById(id))
        .whereType<Friend>()
        .toList();
  }

  void dispose() {
    _isDisposed = true;
    _updateTimer?.cancel();
    _updateTimer = null;
    _friendMeshes.clear();
    friendStatesNotifier.dispose();
    containedFriendsNotifier.dispose();
  }
}
