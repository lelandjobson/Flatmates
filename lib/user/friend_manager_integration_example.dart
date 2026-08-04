/// Example showing how to integrate FriendManager into MapView
///
/// This file demonstrates the integration pattern - copy the relevant parts
/// into your actual map_view.dart implementation.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../geometry/prefabs/prefab_factory.dart';
import '../rendering/scene/scene.dart';
import '../tiles/tiles.dart';
import 'friend_manager.dart';
import 'friend_provider.dart';

// ============================================================================
// STEP 1: Add FriendManager fields to your _MapViewState class
// ============================================================================
//
// Add these fields alongside your existing MapTileManager:
//
// class _MapViewState extends State<MapView> {
//   late final MapTileManager _tileManager;
//   late final FriendProvider _friendProvider;     // <-- Add this
//   late final FriendManager _friendManager;       // <-- Add this
//   ...
// }

// ============================================================================
// STEP 2: Initialize FriendManager in initState()
// ============================================================================
//
// In your initState() method, after creating _scene and _tileManager:
//
// @override
// void initState() {
//   super.initState();
//
//   _scene = Scene(globalIllumination: 0.55);
//   // ... camera setup ...
//
//   _tileManager = MapTileManager(
//     scene: _scene,
//     tileProviders: [_tileProvider],
//     tileSize: _tileSize,
//     heightPerLevel: 60,
//   );
//
//   // Add FriendManager initialization:
//   _friendProvider = MockFriendProvider();
//   _friendManager = FriendManager(
//     scene: _scene,
//     friendProvider: _friendProvider,
//     tileSize: _tileSize,
//     heightPerLevel: 60,
//   );
//
//   // Set initial friend positions
//   _friendManager.setFriendPosition(
//     'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d', // Frogman
//     const TileCoordinate(x: 0, y: 0, z: 0, h: 0),
//   );
//   _friendManager.setFriendPosition(
//     'b2c9f5e1-7a3d-4f8b-9c6e-1d4a8b2f7e3c', // Cubeboy
//     const TileCoordinate(x: 2, y: 2, z: 0, h: 0),
//   );
//
//   // ... rest of initialization ...
// }

// ============================================================================
// STEP 3: Dispose FriendManager in dispose()
// ============================================================================
//
// @override
// void dispose() {
//   _tileManager.dispose();
//   _friendManager.dispose();  // <-- Add this
//   _scene.dispose();
//   super.dispose();
// }

// ============================================================================
// STEP 4: Using FriendManager - Examples
// ============================================================================

class FriendManagerUsageExamples {
  /// Example 1: Move a friend to a specific tile
  static void moveExample(FriendManager friendManager) {
    // Move Frogman to tile (5, 5)
    friendManager.moveFriendTo(
      'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d',
      const TileCoordinate(x: 5, y: 5, z: 0, h: 0),
    );

    // This will automatically:
    // 1. Create a MovementAction from current position to (5,5)
    // 2. Calculate duration based on friend's tileSpeed
    // 3. Queue and execute the action
    // 4. Animate the friend's movement
  }

  /// Example 2: Queue multiple movements (path)
  static void pathExample(FriendManager friendManager) {
    final friendId = 'b2c9f5e1-7a3d-4f8b-9c6e-1d4a8b2f7e3c'; // Cubeboy
    final state = friendManager.getFriendState(friendId);

    if (state != null) {
      // Create a path: current -> (3,0) -> (3,3) -> (0,3)
      final waypoints = [
        const TileCoordinate(x: 3, y: 0, z: 0, h: 0),
        const TileCoordinate(x: 3, y: 3, z: 0, h: 0),
        const TileCoordinate(x: 0, y: 3, z: 0, h: 0),
      ];

      final actions = <FriendAction>[];
      var currentPos = state.position;

      for (final waypoint in waypoints) {
        actions.add(
          MovementAction(friendId: friendId, from: currentPos, to: waypoint),
        );
        currentPos = waypoint;
      }

      friendManager.queueActions(actions);
      // Actions will execute sequentially
    }
  }

  /// Example 3: Check friend status
  static void statusExample(FriendManager friendManager) {
    final friendId = 'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d';

    if (friendManager.isFriendBusy(friendId)) {
      print('Friend is executing an action');

      final state = friendManager.getFriendState(friendId);
      if (state != null) {
        print('Current action: ${state.currentAction}');
        print(
          'Progress: ${(state.currentActionProgress * 100).toStringAsFixed(1)}%',
        );
        print('Queued actions: ${state.actionQueue.length}');
      }
    } else {
      print('Friend is idle');
    }
  }

  /// Example 4: Find friends at or near a location
  static void queryExample(
    FriendManager friendManager,
    FriendProvider friendProvider,
  ) {
    final targetCoord = const TileCoordinate(x: 5, y: 5, z: 0, h: 0);

    // Find friends exactly at this tile
    final friendsHere = friendManager.getFriendsAtCoordinate(targetCoord);
    print('Friends at (5,5): ${friendsHere.length}');

    // Find friends within 3 tiles
    final nearbyFriends = friendManager.getFriendsNearCoordinate(
      targetCoord,
      3,
    );
    print('Friends near (5,5): ${nearbyFriends.length}');

    for (final friend in nearbyFriends) {
      final state = friendManager.getFriendState(friend.id);
      if (state != null) {
        print('  ${friend.name} at ${state.position}');
      }
    }
  }

  /// Example 5: Cancel friend actions
  static void cancelExample(FriendManager friendManager) {
    final friendId = 'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d';

    // Clear all queued actions (current action will still complete)
    friendManager.clearFriendQueue(friendId);

    // If you want to stop immediately, you can teleport:
    friendManager.setFriendPosition(
      friendId,
      const TileCoordinate(x: 0, y: 0, z: 0, h: 0),
    );
  }

  /// Example 6: Listen to friend state changes
  static Widget buildFriendStateListener(FriendManager friendManager) {
    return ValueListenableBuilder<Map<String, FriendState>>(
      valueListenable: friendManager.friendStatesNotifier,
      builder: (context, states, child) {
        return Column(
          children: [
            for (final entry in states.entries)
              Text(
                'Friend ${entry.key.substring(0, 8)}: '
                '${entry.value.position} '
                '${entry.value.isBusy ? "BUSY" : "IDLE"}',
              ),
          ],
        );
      },
    );
  }

  /// Example 7: Get all friends and their stats
  static void friendInfoExample(
    FriendProvider friendProvider,
    FriendManager friendManager,
  ) {
    for (final friend in friendProvider.friends) {
      final state = friendManager.getFriendState(friend.id);
      print('${friend.name} (${friend.geometryType.name}):');
      print('  Speed: ${friend.stats.tileSpeed} tiles/sec');
      print('  Position: ${state?.position}');
      print('  Status: ${state?.isBusy == true ? "Busy" : "Idle"}');
    }
  }
}

// ============================================================================
// STEP 5: UI Integration - Add friend controls to your UI
// ============================================================================

class FriendControlsWidget extends StatelessWidget {
  const FriendControlsWidget({
    super.key,
    required this.friendManager,
    required this.friendProvider,
  });

  final FriendManager friendManager;
  final FriendProvider friendProvider;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Friends',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            ValueListenableBuilder<Map<String, FriendState>>(
              valueListenable: friendManager.friendStatesNotifier,
              builder: (context, states, _) {
                return Column(
                  children: [
                    for (final friend in friendProvider.friends)
                      _buildFriendRow(friend, states[friend.id]),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendRow(Friend friend, FriendState? state) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(
            friend.geometryType == GeometryPrefabs.frog
                ? Icons.pets
                : Icons.square,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  friend.name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                if (state != null) ...[
                  Text(
                    'Position: (${state.position.x}, ${state.position.y})',
                    style: const TextStyle(fontSize: 12),
                  ),
                  if (state.isBusy)
                    LinearProgressIndicator(value: state.currentActionProgress),
                ],
              ],
            ),
          ),
          if (state?.isIdle == true)
            const Icon(Icons.check_circle, color: Colors.green, size: 16)
          else
            const Icon(Icons.directions_walk, color: Colors.orange, size: 16),
        ],
      ),
    );
  }
}

// ============================================================================
// EXAMPLE: Complete minimal widget showing integration
// ============================================================================

class SimpleFriendMapExample extends StatefulWidget {
  const SimpleFriendMapExample({super.key});

  @override
  State<SimpleFriendMapExample> createState() => _SimpleFriendMapExampleState();
}

class _SimpleFriendMapExampleState extends State<SimpleFriendMapExample> {
  late final Scene _scene;
  late final FriendProvider _friendProvider;
  late final FriendManager _friendManager;

  @override
  void initState() {
    super.initState();

    _scene = Scene();
    _friendProvider = MockFriendProvider();
    _friendManager = FriendManager(
      scene: _scene,
      friendProvider: _friendProvider,
      tileSize: 220,
      heightPerLevel: 60,
    );

    // Set initial positions
    _friendManager.setFriendPosition(
      'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d', // Frogman
      const TileCoordinate(x: 0, y: 0, z: 0, h: 0),
    );
    _friendManager.setFriendPosition(
      'b2c9f5e1-7a3d-4f8b-9c6e-1d4a8b2f7e3c', // Cubeboy
      const TileCoordinate(x: 3, y: 3, z: 0, h: 0),
    );
  }

  @override
  void dispose() {
    _friendManager.dispose();
    _scene.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Friend Manager Example')),
      body: Column(
        children: [
          Expanded(child: Center(child: Text('Scene would be rendered here'))),
          FriendControlsWidget(
            friendManager: _friendManager,
            friendProvider: _friendProvider,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Example: Move Frogman to a random position
          _friendManager.moveFriendTo(
            'a7f3e8d2-4b6c-4a9f-8e2d-5c1b3a7f9e4d',
            TileCoordinate(
              x: (math.Random().nextDouble() * 10).toInt(),
              y: (math.Random().nextDouble() * 10).toInt(),
              z: 0,
              h: 0,
            ),
          );
        },
        child: const Icon(Icons.play_arrow),
      ),
    );
  }
}
