import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/landscape/landscape_material.dart';
import 'package:flatmates/landscape/landscape_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog has named palettes covering every material', () {
    expect(LandscapePalette.all, hasLength(12));
    final ids = LandscapePalette.all.map((p) => p.id).toSet();
    expect(ids, hasLength(12));
    for (final palette in LandscapePalette.all) {
      expect(
        palette.gradients.keys.toSet(),
        LandscapeMaterial.values.toSet(),
      );
      expect(palette.label, isNotEmpty);
      expect(palette.defaultOpacity, inInclusiveRange(0.15, 1.0));
    }
  });

  test('paper diorama matches the default landscape gradients', () {
    for (final material in LandscapeMaterial.values) {
      final a = LandscapePalette.paperDiorama.gradients[material]!;
      final b = LandscapeGenParams.kDefaultGradients[material]!;
      expect(a.start.toColor(), b.start.toColor());
      expect(a.end.toColor(), b.end.toColor());
    }
  });

  test('crafting paper stays in the paintbrush pastel family', () {
    final pink = PaperColor.pink.color;
    final yellow = PaperColor.yellow.color;
    final green = PaperColor.green.color;
    final flowers = LandscapePalette.craftingPaper.gradients[LandscapeMaterial.flowers]!
        .sample(0.55);
    final dirt = LandscapePalette.craftingPaper.gradients[LandscapeMaterial.dirt]!
        .sample(0.55);
    final grass = LandscapePalette.craftingPaper.gradients[LandscapeMaterial.grass]!
        .sample(0.55);

    expect(_hueDistance(flowers, pink), lessThan(25));
    expect(_hueDistance(dirt, yellow), lessThan(25));
    expect(_hueDistance(grass, green), lessThan(25));
  });

  test('gradientsAt scales endpoint alpha', () {
    final scaled = LandscapePalette.construction.gradientsAt(0.4);
    for (final material in LandscapeMaterial.values) {
      final g = scaled[material]!;
      expect(g.start.alpha, closeTo(0.4, 0.001));
      expect(g.end.alpha, closeTo(0.4, 0.001));
    }
  });
}

double _hueDistance(Color a, Color b) {
  final ha = HSLColor.fromColor(a).hue;
  final hb = HSLColor.fromColor(b).hue;
  final d = (ha - hb).abs();
  return d > 180 ? 360 - d : d;
}
