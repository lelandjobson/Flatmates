import 'package:flatmates/gameplay/flatmates/bedroom_roster.dart';
import 'package:flatmates/gameplay/flatmates/day_action_store.dart';
import 'package:flatmates/gameplay/friends/friend_instance_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

VolumeStore _store(Volume volume, {VolumeGrid? grid}) {
  final volumes = VolumeStore(grid: grid ?? const VolumeGrid(tilesSide: 16, tileSize: 8));
  volumes.volumes.add(volume);
  return volumes;
}

Volume _mass(List<(int, int)> tiles, {int id = 1}) {
  return Volume(
    id: id,
    cells: [
      for (final (tx, ty) in tiles)
        VolumeCell(tx: tx, ty: ty, box: BoxPrimitive()),
    ],
  );
}

void main() {
  final grid = const VolumeGrid(tilesSide: 16, tileSize: 8);

  test('designating a bedroom region spawns one friend in the room', () {
    final volumes = _store(_mass([(2, 2)]), grid: grid);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final friends = FriendInstanceStore();
    final plans = FlatmateDayPlanStore();
    final result = BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: WallStore(grid: grid),
      grid: grid,
      plans: plans,
    );
    expect(result.spawnedIds, hasLength(1));
    expect(friends.instances, hasLength(1));
    final friend = friends.instances.single;
    expect(friend.bedroomTile, (2, 2));
    expect(friend.bedroomTiles, {(2, 2)});
    expect(friend.friend.name, isNotEmpty);
    expect(plans.byId(friend.id), isNotNull);
  });

  test('expanding a bedroom keeps the same friend', () {
    final volume = _mass([(2, 2), (3, 2)]);
    final volumes = _store(volume, grid: grid);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final friends = FriendInstanceStore();
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: WallStore(grid: grid),
      grid: grid,
    );
    final id = friends.instances.single.id;
    programs.assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: WallStore(grid: grid),
      grid: grid,
    );
    expect(friends.instances, hasLength(1));
    expect(friends.instances.single.id, id);
    expect(friends.instances.single.bedroomTiles, {(2, 2), (3, 2)});
  });

  test('clearing the last bedroom tile deletes the friend', () {
    final volumes = _store(_mass([(2, 2)]), grid: grid);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final friends = FriendInstanceStore();
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: WallStore(grid: grid),
      grid: grid,
    );
    expect(friends.instances, hasLength(1));
    programs.clearIndoor(2, 2);
    final result = BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: WallStore(grid: grid),
      grid: grid,
    );
    expect(result.removedIds, hasLength(1));
    expect(friends.instances, isEmpty);
  });

  test('a wall split keeps the home friend and spawns one for the other room', () {
    final volumes = _store(_mass([(2, 2), (3, 2)]), grid: grid);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
    final friends = FriendInstanceStore();
    final walls = WallStore(grid: grid);
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: walls,
      grid: grid,
    );
    expect(friends.instances, hasLength(1));
    final kept = friends.instances.single.id;
    walls.add(WallEdge(3, 2, 3, 3));
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: walls,
      grid: grid,
    );
    expect(friends.instances, hasLength(2));
    expect(friends.byId(kept), isNotNull);
  });

  test('merging two bedroom rooms keeps the older friend', () {
    final volumes = _store(_mass([(2, 2), (3, 2)]), grid: grid);
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom)
      ..assignIndoor(tx: 3, ty: 2, programId: kProgramBedroom);
    final friends = FriendInstanceStore();
    final walls = WallStore(grid: grid)..add(WallEdge(3, 2, 3, 3));
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: walls,
      grid: grid,
    );
    expect(friends.instances, hasLength(2));
    final older = friends.instances.first.id;
    walls.remove(WallEdge(3, 2, 3, 3));
    BedroomRoster.sync(
      friends: friends,
      volumes: volumes,
      programs: programs,
      walls: walls,
      grid: grid,
    );
    expect(friends.instances, hasLength(1));
    expect(friends.instances.single.id, older);
  });
}