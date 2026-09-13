import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('rejects non-unit and out-of-bounds edges', () {
    final store = WallStore();
    final lo = store.grid.originTile;
    expect(store.add(WallEdge(0, 0, 2, 0)), isFalse);
    expect(store.add(WallEdge(0, 0, 1, 1)), isFalse);
    expect(store.add(WallEdge(lo - 1, 0, lo, 0)), isFalse);
    expect(store.add(WallEdge(-1, 0, 0, 0)), isTrue);
    expect(store.add(WallEdge(0, 0, 1, 0)), isTrue);
    expect(store.add(WallEdge(0, 0, 1, 0)), isFalse);
  });

  test('hit test only accepts points near an edge midpoint', () {
    final store = WallStore();
    final a = store.vertexWorld(3, 4);
    final b = store.vertexWorld(4, 4);
    final mid = Vector3((a.x + b.x) * 0.5, 0, a.z);
    expect(store.hitEdgeAtMidpoint(mid), WallEdge(3, 4, 4, 4));
    expect(store.hitEdgeAtMidpoint(a), isNull);
    final near = Vector3(mid.x, 0, mid.z + store.grid.tileSize * 0.22);
    expect(store.hitEdgeAtMidpoint(near), WallEdge(3, 4, 4, 4));
    final far = Vector3(mid.x, 0, mid.z + store.grid.tileSize * 0.4);
    expect(store.hitEdgeAtMidpoint(far), isNull);
  });

  test('tap toggles a midpoint wall; drag only adds', () {
    final store = WallStore();
    final a = store.vertexWorld(2, 3);
    final b = store.vertexWorld(3, 3);
    final mid = Vector3((a.x + b.x) * 0.5, 0, a.z);
    expect(store.toggleAtMidpoint(mid), isTrue);
    expect(store.contains(WallEdge(2, 3, 3, 3)), isTrue);
    expect(store.toggleAtMidpoint(mid), isTrue);
    expect(store.contains(WallEdge(2, 3, 3, 3)), isFalse);

    store.add(WallEdge(2, 3, 3, 3));
    final from = Vector3((a.x + b.x) * 0.5, 0, a.z);
    final to = Vector3(from.x + store.grid.tileSize * 2, 0, from.z);
    expect(store.paintStroke(from, to), isTrue);
    expect(store.contains(WallEdge(2, 3, 3, 3)), isTrue);
    expect(store.contains(WallEdge(3, 3, 4, 3)), isTrue);
    expect(store.contains(WallEdge(4, 3, 5, 3)), isTrue);
  });

  test('eraseNear removes only walls inside the radius', () {
    final store = WallStore();
    expect(store.add(WallEdge(1, 1, 2, 1)), isTrue);
    expect(store.add(WallEdge(5, 5, 6, 5)), isTrue);
    final mid = store.vertexWorld(1, 1);
    final center = Vector3(mid.x + store.grid.tileSize * 0.5, 0, mid.z);
    expect(store.eraseNear(center, store.grid.tileSize * 0.6), isTrue);
    expect(store.contains(WallEdge(1, 1, 2, 1)), isFalse);
    expect(store.contains(WallEdge(5, 5, 6, 5)), isTrue);
  });

  test('separatesTiles is true only for a wall on the shared side', () {
    final store = WallStore();
    expect(store.separatesTiles((2, 2), (3, 2)), isFalse);
    expect(store.add(WallEdge(3, 2, 3, 3)), isTrue);
    expect(store.separatesTiles((2, 2), (3, 2)), isTrue);
    expect(store.separatesTiles((2, 2), (2, 3)), isFalse);
  });

  test('cut fence still separates tiles but does not block walking', () {
    final store = WallStore();
    final edge = WallEdge(3, 2, 3, 3);
    expect(store.add(edge), isTrue);
    expect(store.cut(edge), isTrue);
    expect(store.lookup(edge)?.kind, WallKind.cutFence);
    expect(store.separatesTiles((2, 2), (3, 2)), isTrue);
    expect(store.blocksWalk((2, 2), (3, 2)), isFalse);
    expect(store.uncut(edge), isTrue);
    expect(store.lookup(edge)?.kind, WallKind.fence);
    expect(store.blocksWalk((2, 2), (3, 2)), isTrue);
  });

  test('add, hit, and toggle work on negative-X and negative-Y edges', () {
    final store = WallStore();
    final west = WallEdge(-4, 1, -3, 1);
    expect(store.add(west), isTrue);
    final westA = store.vertexWorld(-4, 1);
    final westB = store.vertexWorld(-3, 1);
    final westMid = Vector3((westA.x + westB.x) * 0.5, 0, westA.z);
    expect(store.hitEdgeAtMidpoint(westMid), west);

    final south = WallEdge(2, -5, 2, -4);
    final southA = store.vertexWorld(2, -5);
    final southB = store.vertexWorld(2, -4);
    final southMid = Vector3(southA.x, 0, (southA.z + southB.z) * 0.5);
    expect(store.hitEdgeAtMidpoint(southMid), south);
    expect(store.toggleAtMidpoint(southMid), isTrue);
    expect(store.contains(south), isTrue);
    expect(store.toggleAtMidpoint(southMid), isTrue);
    expect(store.contains(south), isFalse);
  });

  test('adding a wall across a path severs the connection and stores no wall', () {
    final paths = PathStore()
      ..placeAndJoin(2, 2)
      ..placeAndJoin(3, 2);
    expect(paths.hasEdge(2, 2, 3, 2), isTrue);
    final walls = WallStore();
    final edge = WallEdge(3, 2, 3, 3);
    expect(walls.add(edge, insteadOfAdd: paths.severAcross), isTrue);
    expect(walls.contains(edge), isFalse);
    expect(paths.hasEdge(2, 2, 3, 2), isFalse);
    expect(paths.contains(2, 2), isTrue);
    expect(paths.contains(3, 2), isTrue);
  });
}
