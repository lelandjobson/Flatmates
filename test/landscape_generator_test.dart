import 'package:flatmates/landscape/landscape_generator.dart';
import 'package:flatmates/landscape/landscape_material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<LandscapeMaterial, int> countsOf(LandscapeGenParams params) {
    final gen = LandscapeGenerator(params);
    final side = params.clamped().worldPixelsSide;
    final counts = {for (final m in LandscapeMaterial.values) m: 0};
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final m = gen.materialAt(x, y);
      counts[m] = counts[m]! + 1;
      }
    }
    return counts;
  }

  test('equal terrain weights give every ground material a real share', () {
    const params = LandscapeGenParams(
      tilesSide: 16,
      pixelsPerTile: 8,
      noiseFrequency: 0.08,
      weights: {
        LandscapeMaterial.rock: 10,
        LandscapeMaterial.grass: 10,
        LandscapeMaterial.dirt: 10,
        LandscapeMaterial.water: 10,
        LandscapeMaterial.flowers: 0,
        LandscapeMaterial.fruits: 0,
        LandscapeMaterial.vegetables: 0,
      },
    );
    final counts = countsOf(params);
    final total = params.worldPixelsSide * params.worldPixelsSide;
    for (final m in kLandscapeTerrainFlow) {
      expect(
        counts[m]!,
        greaterThan((total * 0.12).round()),
        reason: '$m should cover a slice of an equal-weight terrain field',
      );
    }
    expect(counts[LandscapeMaterial.flowers]!, 0);
    expect(counts[LandscapeMaterial.fruits]!, 0);
    expect(counts[LandscapeMaterial.vegetables]!, 0);
  });

  test('default weights include rock and water, not only grass and dirt', () {
    const params = LandscapeGenParams(
      tilesSide: 16,
      pixelsPerTile: 8,
      noiseFrequency: 0.08,
    );
    final counts = countsOf(params);
    expect(counts[LandscapeMaterial.rock]!, greaterThan(0));
    expect(counts[LandscapeMaterial.water]!, greaterThan(0));
    expect(counts[LandscapeMaterial.grass]!, greaterThan(0));
    expect(counts[LandscapeMaterial.dirt]!, greaterThan(0));
  });

  test('forage weight stamps a second field without wiping terrain', () {
    const params = LandscapeGenParams(
      tilesSide: 16,
      pixelsPerTile: 8,
      noiseFrequency: 0.08,
      weights: {
        LandscapeMaterial.rock: 10,
        LandscapeMaterial.grass: 10,
        LandscapeMaterial.dirt: 10,
        LandscapeMaterial.water: 10,
        LandscapeMaterial.flowers: 20,
        LandscapeMaterial.fruits: 0,
        LandscapeMaterial.vegetables: 0,
      },
    );
    final counts = countsOf(params);
    final total = params.worldPixelsSide * params.worldPixelsSide;
    expect(counts[LandscapeMaterial.flowers]!, greaterThan((total * 0.08).round()));
    expect(counts[LandscapeMaterial.fruits]!, 0);
    expect(counts[LandscapeMaterial.grass]!, greaterThan(0));
    expect(counts[LandscapeMaterial.water]!, greaterThan(0));
  });

  test('same seed and cell is deterministic', () {
    const params = LandscapeGenParams(seed: 7);
    final a = LandscapeGenerator(params);
    final b = LandscapeGenerator(params);
    expect(a.materialAt(11, 19), b.materialAt(11, 19));
  });
}
