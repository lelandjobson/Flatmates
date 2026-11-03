import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/protoplane/wall_reveal.dart';

void main() {
  double opacity(Vector3 eye, {Vector3? target, Vector3? wall}) =>
      wallRevealOpacity(
        camera: eye,
        target: target ?? Vector3.zero(),
        roomCenter: Vector3.zero(),
        wallCenter: wall ?? Vector3(0, .5, 1),
      );
  test('near front walls reveal interiors; distant and rear walls remain', () {
    expect(opacity(Vector3(0, 2, 2)), closeTo(.08, 1e-6));
    expect(opacity(Vector3(0, 8, 8)), 1);
    expect(opacity(Vector3(0, 2, -2)), 1);
    expect(opacity(Vector3(0, 2, 2), wall: Vector3(0, .5, -1)), 1);
  });
  test('zoom and pan fade smoothly and other levels stay intact', () {
    final near = opacity(Vector3(0, 3, 3)),
        middle = opacity(Vector3(0, 4, 4)),
        far = opacity(Vector3(0, 6, 6));
    expect(near, lessThan(middle));
    expect(middle, lessThan(far));
    expect(opacity(Vector3(4, 2, 2), target: Vector3(4, 0, 0)), 1);
    expect(opacity(Vector3(0, 4, 2), target: Vector3(0, 2, 0)), 1);
  });
}
