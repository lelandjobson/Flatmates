import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/flatmates/flatmate_pathfinder.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final grid = const VolumeGrid(tilesSide: 16, tileSize: 8);

  VolumeStore emptyVolumes() => VolumeStore(grid: grid);

  test('direct ground path is ortho shortest', () {
    final path = FlatmatePathfinder().findOnMap(
      start: (1, 1),
      goal: (3, 1),
      grid: grid,
      volumes: emptyVolumes(),
      paths: PathStore(grid: grid),
    );
    expect(path, [(1, 1), (2, 1), (3, 1)]);
  });

  test('prefers a longer path corridor because it is 50% faster', () {
    final paths = PathStore(grid: grid);
    // Detour: (0,0)->(0,2)->(2,2)->(2,0) is 6 steps on path.
    // Straight (0,0)->(2,0) is 2 ground steps. Time: path 6*(2/3)=4, ground 2.
    // So straight ground wins. Need a corridor that is actually faster.
    // Ground L: (0,0)-(3,0)-(3,3) = 6 ground.
    // Path around closer: (0,0)-(0,1)-(0,2)-(1,2)-(2,2)-(3,2)-(3,3) = 6 path
    //   time 6*(2/3)=4 < 6. Should take path.
    paths.connect(0, 0, 0, 1);
    paths.connect(0, 1, 0, 2);
    paths.connect(0, 2, 1, 2);
    paths.connect(1, 2, 2, 2);
    paths.connect(2, 2, 3, 2);
    paths.connect(3, 2, 3, 3);

    final route = FlatmatePathfinder().findOnMap(
      start: (0, 0),
      goal: (3, 3),
      grid: grid,
      volumes: emptyVolumes(),
      paths: paths,
    );
    expect(route, isNotNull);
    expect(route, containsAllInOrder([(0, 0), (0, 1), (0, 2)]));
    expect(route!.last, (3, 3));
    expect(route.every((t) => paths.contains(t.$1, t.$2)), isTrue);
  });

  test('does not walk through volumes', () {
    final volumes = emptyVolumes();
    volumes.volumes.add(
      Volume(
        id: 1,
        cells: [VolumeCell(tx: 2, ty: 1, box: BoxPrimitive())],
      ),
    );
    final path = FlatmatePathfinder().findOnMap(
      start: (1, 1),
      goal: (3, 1),
      grid: grid,
      volumes: volumes,
      paths: PathStore(grid: grid),
    );
    expect(path, isNotNull);
    expect(path, isNot(contains((2, 1))));
  });

  test('walls block a crossing so the route detours', () {
    final walls = WallStore(grid: grid);
    walls.add(WallEdge(2, 1, 2, 2));
    final path = FlatmatePathfinder().findOnMap(
      start: (1, 1),
      goal: (2, 1),
      grid: grid,
      volumes: emptyVolumes(),
      paths: PathStore(grid: grid),
      walls: walls,
    );
    expect(path, isNotNull);
    for (var i = 0; i < path!.length - 1; i++) {
      expect(
        {path[i], path[i + 1]},
        isNot(unorderedEquals([(1, 1), (2, 1)])),
      );
    }
  });

  test('enters a volume through its door, not a sealed wall', () {
    final volumes = emptyVolumes();
    volumes.volumes.add(
      Volume(
        id: 1,
        cells: [
          VolumeCell(
            tx: 3,
            ty: 2,
            box: BoxPrimitive(),
            accessibleSides: {VolumeSide.east},
          ),
        ],
      ),
    );
    final path = FlatmatePathfinder().findOnMap(
      start: (1, 2),
      goal: (3, 2),
      grid: grid,
      volumes: volumes,
      paths: PathStore(grid: grid),
    );
    expect(path, isNotNull);
    expect(path, containsAllInOrder([(4, 2), (3, 2)]));
    for (var i = 0; i < path!.length - 1; i++) {
      expect(
        {path[i], path[i + 1]},
        isNot(unorderedEquals([(2, 2), (3, 2)])),
      );
    }
  });

  test('walks inside a merged volume after taking a door', () {
    final volumes = emptyVolumes();
    volumes.volumes.add(
      Volume(
        id: 1,
        cells: [
          VolumeCell(
            tx: 3,
            ty: 2,
            box: BoxPrimitive(),
            accessibleSides: {VolumeSide.west},
          ),
          VolumeCell(tx: 4, ty: 2, box: BoxPrimitive()),
        ],
      ),
    );
    final path = FlatmatePathfinder().findOnMap(
      start: (1, 2),
      goal: (4, 2),
      grid: grid,
      volumes: volumes,
      paths: PathStore(grid: grid),
    );
    expect(path, [(1, 2), (2, 2), (3, 2), (4, 2)]);
  });

  test('cannot enter a volume with no door', () {
    final volumes = emptyVolumes();
    volumes.volumes.add(
      Volume(
        id: 1,
        cells: [VolumeCell(tx: 3, ty: 2, box: BoxPrimitive())],
      ),
    );
    final path = FlatmatePathfinder().findOnMap(
      start: (1, 2),
      goal: (3, 2),
      grid: grid,
      volumes: volumes,
      paths: PathStore(grid: grid),
    );
    expect(path, isNull);
  });

  test('movement is 50% faster on path tiles', () {
    final move = FlatmateMovement()..start([(0, 0), (1, 0), (2, 0)]);
    var onPath = true;
    move.advance(
      dt: 0.1,
      baseTilesPerSecond: 10,
      onPath: (_, _) => onPath,
    );
    expect(move.progress, closeTo(1.5, 1e-9));

    move.progress = 0;
    onPath = false;
    move.advance(
      dt: 0.1,
      baseTilesPerSecond: 10,
      onPath: (_, _) => onPath,
    );
    expect(move.progress, closeTo(1.0, 1e-9));
  });
}
