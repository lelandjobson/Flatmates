import 'package:vector_math/vector_math_64.dart';

import '../../user/friend_provider.dart';
import '../friends/friend_instance.dart';
import '../friends/friend_instance_store.dart';
import '../friends/friend_mesh_sync.dart';
import '../volumes/volume.dart';
import '../volumes/volume_program.dart';
import '../volumes/volume_program_graph.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_store.dart';
import 'day_action_store.dart';
import 'flatmate_range.dart';

class BedroomRosterResult {
  const BedroomRosterResult({
    this.spawnedIds = const [],
    this.removedIds = const [],
  });

  final List<String> spawnedIds;
  final List<String> removedIds;

  bool get changed => spawnedIds.isNotEmpty || removedIds.isNotEmpty;
}

/// One flatmate per contiguous indoor bedroom region.
class BedroomRoster {
  static List<ProgramGraphNode> bedrooms({
    required VolumeStore volumes,
    required VolumeProgramStore programs,
    required WallStore walls,
  }) {
    final out = <ProgramGraphNode>[];
    for (final volume in volumes.volumes) {
      out.addAll(
        buildVolumeProgramGraph(
          volume: volume,
          programs: programs,
          walls: walls,
        ).bedrooms,
      );
    }
    return out;
  }

  static BedroomRosterResult sync({
    required FriendInstanceStore friends,
    required VolumeStore volumes,
    required VolumeProgramStore programs,
    required WallStore walls,
    required VolumeGrid grid,
    FlatmateDayPlanStore? plans,
  }) {
    final regions = bedrooms(
      volumes: volumes,
      programs: programs,
      walls: walls,
    );
    final claimed = <ProgramGraphNode>{};
    final removed = <String>[];

    for (final friend in List<FriendInstance>.from(friends.instances)) {
      if (!friend.hasBedroom) continue;
      final region = _matchRegion(friend, regions);
      if (region == null || claimed.contains(region)) {
        friends.remove(friend.id);
        plans?.remove(friend.id);
        removed.add(friend.id);
        continue;
      }
      claimed.add(region);
      _assignRegion(friend, region, grid);
      plans?.ensure(friend.id, home: friend.bedroomTile);
    }

    final spawned = <String>[];
    for (final region in regions) {
      if (claimed.contains(region)) continue;
      final instance = spawnInRegion(
        region: region,
        grid: grid,
        existing: friends.instances,
      );
      friends.add(instance);
      plans?.ensure(instance.id, home: instance.bedroomTile);
      spawned.add(instance.id);
    }

    return BedroomRosterResult(spawnedIds: spawned, removedIds: removed);
  }

  /// Shift bedroom friends that now sit in [volume] after a [dtx],[dty] move.
  static void remapVolume({
    required FriendInstanceStore friends,
    required Volume volume,
    required int dtx,
    required int dty,
    required VolumeGrid grid,
    FlatmateDayPlanStore? plans,
  }) {
    if (dtx == 0 && dty == 0) return;
    for (final friend in friends.instances) {
      final home = friend.bedroomTile;
      if (home == null) continue;
      final moved = (home.$1 + dtx, home.$2 + dty);
      if (volume.cellAt(moved.$1, moved.$2) == null) continue;
      friend.bedroomTile = moved;
      final next = {
        for (final tile in friend.bedroomTiles) (tile.$1 + dtx, tile.$2 + dty),
      };
      friend.bedroomTiles
        ..clear()
        ..addAll(next);
      friend.position.x += dtx * grid.tileSize;
      friend.position.z += dty * grid.tileSize;
      plans?.byId(friend.id)?.bindHome(moved);
    }
  }

  static FriendInstance spawnInRegion({
    required ProgramGraphNode region,
    required VolumeGrid grid,
    required List<FriendInstance> existing,
    String? id,
  }) {
    final home = centroidTile(region.tiles);
    final index = existing.length + 1;
    final template =
        kBedroomFriendTemplates[existing.length % kBedroomFriendTemplates.length];
    final color =
        kBedroomFriendColors[existing.length % kBedroomFriendColors.length];
    final taken = {
      for (final instance in existing) instance.friend.name,
    };
    var name = template.name;
    if (taken.contains(name)) {
      name = '${template.name} $index';
    }
    final instance = FriendInstance(
      id: id ?? MockFriendProvider.generateGuid(),
      friend: Friend(
        id: MockFriendProvider.generateGuid(),
        name: name,
        geometryType: template.geometryType,
        stats: const FriendStats(tileSpeed: 2.5),
        color: color,
      ),
      position: _sitOn(grid, home),
      bedroomTile: home,
      bedroomTiles: region.tiles,
    );
    return instance;
  }

  static ProgramGraphNode? _matchRegion(
    FriendInstance friend,
    List<ProgramGraphNode> regions,
  ) {
    final home = friend.bedroomTile;
    if (home != null) {
      for (final region in regions) {
        if (region.tiles.contains(home)) return region;
      }
    }
    ProgramGraphNode? best;
    var bestOverlap = 0;
    for (final region in regions) {
      var n = 0;
      for (final tile in friend.bedroomTiles) {
        if (region.tiles.contains(tile)) n++;
      }
      if (n > bestOverlap) {
        bestOverlap = n;
        best = region;
      }
    }
    return bestOverlap > 0 ? best : null;
  }

  static void _assignRegion(
    FriendInstance friend,
    ProgramGraphNode region,
    VolumeGrid grid,
  ) {
    final oldHome = friend.bedroomTile;
    friend.bedroomTiles
      ..clear()
      ..addAll(region.tiles);
    if (oldHome == null || !region.tiles.contains(oldHome)) {
      friend.bedroomTile = centroidTile(region.tiles);
      _moveToHome(friend, grid);
    } else {
      friend.bedroomTile = oldHome;
    }
  }

  static void _moveToHome(FriendInstance friend, VolumeGrid grid) {
    final home = friend.bedroomTile;
    if (home == null) return;
    friend.position.setFrom(_sitOn(grid, home));
  }

  static Vector3 _sitOn(VolumeGrid grid, (int, int) tile) {
    final center = grid.tileCenter(tile.$1, tile.$2);
    center.y = FriendMeshLayout.sitOnGroundY(tileSize: grid.tileSize);
    return center;
  }
}
