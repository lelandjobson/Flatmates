import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/landscape/landscape_material.dart';
import 'package:flatmates/theme/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('catalog indexes every material and paper slot', () {
    expect(WorldTheme.all, isNotEmpty);
    final ids = WorldTheme.all.map((t) => t.id).toSet();
    expect(ids, hasLength(WorldTheme.all.length));
    for (final theme in WorldTheme.all) {
      expect(
        theme.gradients.keys.toSet(),
        LandscapeMaterial.values.toSet(),
      );
      for (final paper in PaperColor.values) {
        expect(theme.paper(paper), isNot(equals(const Color(0x00000000))));
      }
      expect(theme.colorSigma, inInclusiveRange(0.01, 1.0));
      expect(theme.grain.strength, inInclusiveRange(0.0, 1.0));
    }
  });

  test('paper diorama is the default look', () {
    final theme = WorldTheme.paperDiorama;
    expect(WorldTheme.byId('missing'), theme);
    expect(theme.colorSigma, closeTo(0.06, 0.001));
    expect(theme.grain.strength, closeTo(0.066, 0.001));
    expect(theme.grain.frequency, closeTo(0.126, 0.001));
    expect(theme.grain.octaves, 2);
    expect(theme.shade.minShade, closeTo(0.82, 0.001));
    expect(theme.shade.tintStrength, closeTo(0.10, 0.001));
    expect(theme.paper(PaperColor.pink), const Color(0xFFF0B4C0));
    expect(theme.paper(PaperColor.yellow), const Color(0xFFF5E6C8));
    expect(theme.paper(PaperColor.green), const Color(0xFFB8E0C8));
    expect(theme.path, const Color(0xFFE8C9A8));
    expect(theme.background, const Color(0xFFD8E8F0));
    for (final material in LandscapeMaterial.values) {
      final a = theme.material(material);
      final b = LandscapeGenParams.kDefaultGradients[material]!;
      expect(a.start.toColor(), b.start.toColor());
      expect(a.end.toColor(), b.end.toColor());
    }
  });

  test('PaperColor.resolve uses the active theme', () {
    expect(
      PaperColor.pink.resolve(),
      WorldTheme.paperDiorama.paper(PaperColor.pink),
    );
    expect(
      PaperColor.pink.resolve(WorldTheme.waterLilies),
      isNot(WorldTheme.paperDiorama.paper(PaperColor.pink)),
    );
  });
}
