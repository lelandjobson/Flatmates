import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_mesh.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fence boxes are short and sit on the ground', () {
    final store = WallStore();
    final edge = WallEdge(1, 2, 2, 2);
    final (min, max) = wallWorldAabb(store, edge);
    expect(min.y, 0);
    expect(max.y, kFenceHeight);
    expect(max.y, lessThan(2));
    expect(max.x - min.x, closeTo(store.grid.tileSize, 0.01));
    expect(max.z - min.z, closeTo(kFenceThickness, 0.01));
  });

  test('vertical fence is thin in X', () {
    final store = WallStore();
    final (min, max) = wallWorldAabb(store, WallEdge(4, 1, 4, 2));
    expect(max.x - min.x, closeTo(kFenceThickness, 0.01));
    expect(max.z - min.z, closeTo(store.grid.tileSize, 0.01));
  });

  test('mesh id roundtrips', () {
    final edge = WallEdge(3, 5, 3, 6);
    expect(wallEdgeFromMeshId(wallMeshId(edge)), edge);
  });
}
