import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('rejects non-unit and out-of-bounds edges', () {
    final store = WallStore();
    expect(store.add(WallEdge(0, 0, 2, 0)), isFalse);
    expect(store.add(WallEdge(0, 0, 1, 1)), isFalse);
    expect(store.add(WallEdge(-1, 0, 0, 0)), isFalse);
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
}
