import 'package:flatmates/gameplay/paint/ground_shadow_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  final min = Vector3(0, 0, 0);
  final max = Vector3(4, 3, 2);

  test('footprint is the AABB on Y = 0', () {
    final poly = footprintPolygon(min, max);
    expect(poly, hasLength(4));
    expect(poly.every((p) => p.y == 0), isTrue);
    expect(poly.map((p) => p.x).reduce((a, b) => a < b ? a : b), 0);
    expect(poly.map((p) => p.x).reduce((a, b) => a > b ? a : b), 4);
    expect(poly.map((p) => p.z).reduce((a, b) => a < b ? a : b), 0);
    expect(poly.map((p) => p.z).reduce((a, b) => a > b ? a : b), 2);
  });

  test('straight-down light keeps the footprint', () {
    final poly = castPolygon(
      min,
      max,
      lightTravel: Vector3(0, -1, 0),
    );
    expect(poly.every((p) => p.y == 0), isTrue);
    final xs = poly.map((p) => p.x).toList()..sort();
    final zs = poly.map((p) => p.z).toList()..sort();
    expect(xs.first, closeTo(0, 1e-6));
    expect(xs.last, closeTo(4, 1e-6));
    expect(zs.first, closeTo(0, 1e-6));
    expect(zs.last, closeTo(2, 1e-6));
  });

  test('cast stretches away from a diagonal light', () {
    final poly = castPolygon(
      min,
      max,
      lightTravel: Vector3(-1, -1, 0),
      maxStretch: 20,
    );
    expect(poly.every((p) => p.y == 0), isTrue);
    final minX = poly.map((p) => p.x).reduce((a, b) => a < b ? a : b);
    expect(minX, lessThan(-0.5));
  });

  test('projectOntoGround clamps grazing stretch', () {
    final far = projectOntoGround(
      Vector3(0, 10, 0),
      Vector3(-1, -0.01, 0),
      maxStretch: 4,
    );
    expect(far.y, 0);
    expect((far.x).abs(), lessThanOrEqualTo(4.01));
  });

  test('off mode yields no polygon', () {
    expect(
      const GroundShadowModel(mode: GroundShadowMode.off)
          .polygon(min, max),
      isEmpty,
    );
  });
}
