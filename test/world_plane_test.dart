import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('ground UV round-trips', () {
    final plane = WorldPlane.ground(
      origin: Vector3(3, 0, -2),
      subtileSize: 1,
    );
    final world = plane.point(4, -1);
    final (u, v) = plane.toUv(world);
    expect(u, closeTo(4, 1e-9));
    expect(v, closeTo(-1, 1e-9));
    expect(plane.isGround, isTrue);
  });

  test('vertical face has +Y up', () {
    final plane = WorldPlane(
      origin: Vector3(4, 3, 0),
      normal: Vector3(1, 0, 0),
      subtileSize: 1,
    );
    expect(plane.up.y, closeTo(1, 1e-9));
    expect(plane.normal.x, closeTo(1, 1e-9));
  });

  test('ground lattice is world-aligned regardless of click origin', () {
    final a = WorldPlane.ground(origin: Vector3(3.7, 0, -1.2), subtileSize: 1);
    final b = WorldPlane.ground(origin: Vector3(-8.1, 0, 4.4), subtileSize: 1);
    expect(a.latticePoint(3, -2).x, closeTo(3, 1e-9));
    expect(a.latticePoint(3, -2).z, closeTo(-2, 1e-9));
    expect(b.latticePoint(3, -2).x, closeTo(a.latticePoint(3, -2).x, 1e-9));
    expect(b.latticePoint(3, -2).z, closeTo(a.latticePoint(3, -2).z, 1e-9));
  });
}
