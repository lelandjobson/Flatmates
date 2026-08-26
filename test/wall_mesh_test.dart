import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_mesh.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('fence plane is short, sits on the ground, and has no thickness', () {
    final store = WallStore();
    final edge = WallEdge(1, 2, 2, 2);
    final (min, max) = wallWorldAabb(store, edge);
    expect(min.y, 0);
    expect(max.y, kFenceHeight);
    expect(max.y, lessThan(2));
    expect(max.x - min.x, closeTo(store.grid.tileSize, 0.01));
    expect(max.z - min.z, 0);
  });

  test('vertical fence is a plane in X', () {
    final store = WallStore();
    final (min, max) = wallWorldAabb(store, WallEdge(4, 1, 4, 2));
    expect(max.x - min.x, 0);
    expect(max.z - min.z, closeTo(store.grid.tileSize, 0.01));
  });

  test('wall face is a single double-sided quad', () {
    final geom = wallFaceGeometry(
      a: Vector3(0, 0, 0),
      b: Vector3(8, 0, 0),
      id: 'wall_0_0_1_0',
    );
    expect(geom.vertices, hasLength(4));
    expect(geom.faces, hasLength(1));
    expect(geom.vertices.where((v) => v.y == 0), hasLength(2));
    expect(geom.vertices.where((v) => v.y == kFenceHeight), hasLength(2));
  });

  test('corner walls share a vertex and do not overlap in XZ', () {
    final store = WallStore()
      ..add(WallEdge(2, 2, 3, 2))
      ..add(WallEdge(3, 2, 3, 3));
    final scene = Scene();
    syncWallMeshes(scene, store);
    expect(scene.meshes, hasLength(2));
    for (final mesh in scene.meshes) {
      expect(mesh.material.doubleSided, isTrue);
      expect(mesh.geometry.faces, hasLength(1));
    }
    final horiz = wallWorldAabb(store, WallEdge(2, 2, 3, 2));
    final vert = wallWorldAabb(store, WallEdge(3, 2, 3, 3));
    expect(horiz.$2.x, vert.$1.x);
    expect(horiz.$1.z, vert.$1.z);
    expect(horiz.$2.z, vert.$1.z);
  });

  test('mesh id roundtrips', () {
    final edge = WallEdge(3, 5, 3, 6);
    expect(wallEdgeFromMeshId(wallMeshId(edge)), edge);
  });
}
