import 'package:flatmates/gameplay/paths/path_mesh.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('path outline is a flat ground-plane quad', () {
    final geom = pathOutlineGeometry(
      min: Vector3(2, 0, 4),
      max: Vector3(6, 0, 8),
      id: 'path_0_0_0',
    );
    expect(geom.vertices, hasLength(4));
    expect(geom.faces, hasLength(1));
    expect(geom.vertices.every((v) => v.y == 0), isTrue);
    expect(geom.vertices.map((v) => v.y).toSet(), {0.0});

    final face = geom.faces.single;
    final a = geom.vertices[face[1]] - geom.vertices[face[0]];
    final b = geom.vertices[face[2]] - geom.vertices[face[0]];
    final normal = a.cross(b);
    expect(normal.y, greaterThan(0));
  });
}
