import 'package:flatmates/gameplay/paint/plane_grain_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const paper = Color(0xFFBAFFC9);

  test('zero strength leaves the paper color unchanged', () {
    final grain = PlaneGrainModel(strength: 0);
    expect(
      grain.apply(paper, tx: 3, ty: 4, u: 2, v: 1, faceIndex: 0),
      paper,
    );
  });

  test('same subtile is deterministic', () {
    final a = PlaneGrainModel(seed: 9, strength: 0.3);
    final b = PlaneGrainModel(seed: 9, strength: 0.3);
    expect(
      a.apply(paper, tx: 1, ty: 2, u: 3, v: 4, faceIndex: 1),
      b.apply(paper, tx: 1, ty: 2, u: 3, v: 4, faceIndex: 1),
    );
  });

  test('distant subtles pick different ink amounts', () {
    final grain = PlaneGrainModel(seed: 3, strength: 0.4, frequency: 0.5);
    final n0 = grain.sample(tx: 0, ty: 0, u: 0, v: 0, faceIndex: 0);
    final n1 = grain.sample(tx: 5, ty: 7, u: 3, v: 6, faceIndex: 2);
    expect(n0, isNot(closeTo(n1, 0.02)));
  });

  test('positive sample lightens, negative sample darkens', () {
    final grain = PlaneGrainModel(strength: 0.5);
    const mid = Color(0xFF808080);
    Color? light;
    Color? dark;
    for (var u = 0; u < 24 && (light == null || dark == null); u++) {
      final n = grain.sample(tx: 0, ty: 0, u: u, v: 0, faceIndex: 0);
      final c = grain.apply(mid, tx: 0, ty: 0, u: u, v: 0, faceIndex: 0);
      if (n > 0.08) light = c;
      if (n < -0.08) dark = c;
    }
    expect(light, isNotNull);
    expect(dark, isNotNull);
    expect(light!.computeLuminance(), greaterThan(mid.computeLuminance()));
    expect(dark!.computeLuminance(), lessThan(mid.computeLuminance()));
  });
}
