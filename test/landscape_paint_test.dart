import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/landscape/landscape_ca.dart';
import 'package:flatmates/landscape/landscape_generator.dart';
import 'package:flatmates/landscape/landscape_grid.dart';
import 'package:flatmates/landscape/landscape_material.dart';
import 'package:flatmates/theme/world_theme.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  LandscapeGrid grid() =>
      LandscapeGrid.fromGenerator(LandscapeGenerator(const LandscapeGenParams()));

  test('paint overlays paper color until erase', () {
    final g = grid();
    expect(g.paint(2, 3, PaperColor.pink), isTrue);
    expect(g.paint(2, 3, PaperColor.pink), isFalse);
    expect(
      g.colorAt(2, 3, const LandscapeGenParams()),
      WorldTheme.paperDiorama.paper(PaperColor.pink),
    );
    expect(g.erase(2, 3), isTrue);
    expect(g.isEmpty(2, 3), isTrue);
    expect(
      g.colorAt(2, 3, const LandscapeGenParams()),
      WorldTheme.paperDiorama.background,
    );
  });

  test('fill floods empty holes and stops at drawn pixels', () {
    final g = grid();
    for (var y = 1; y <= 3; y++) {
      for (var x = 1; x <= 3; x++) {
        g.erase(x, y);
      }
    }
    g.paint(2, 2, PaperColor.yellow);
    expect(g.fill(1, 1, PaperColor.pink), isTrue);
    expect(
      g.colorAt(1, 1, const LandscapeGenParams()),
      WorldTheme.paperDiorama.paper(PaperColor.pink),
    );
    expect(
      g.colorAt(3, 3, const LandscapeGenParams()),
      WorldTheme.paperDiorama.paper(PaperColor.pink),
    );
    expect(
      g.colorAt(2, 2, const LandscapeGenParams()),
      WorldTheme.paperDiorama.paper(PaperColor.yellow),
    );
    expect(g.fill(2, 2, PaperColor.green), isTrue);
    expect(
      g.colorAt(2, 2, const LandscapeGenParams()),
      WorldTheme.paperDiorama.paper(PaperColor.green),
    );
    expect(
      g.colorAt(1, 1, const LandscapeGenParams()),
      WorldTheme.paperDiorama.paper(PaperColor.pink),
    );
  });

  test('void is not empty and CA will not refill it', () {
    final gen = LandscapeGenerator(const LandscapeGenParams());
    final g = LandscapeGrid.fromGenerator(gen);
    expect(g.cover(4, 4), isTrue);
    expect(g.erase(5, 4), isTrue);
    expect(g.isVoid(4, 4), isTrue);
    expect(g.isEmpty(4, 4), isFalse);
    expect(g.paint(4, 4, PaperColor.pink), isFalse);
    expect(g.erase(4, 4), isFalse);
    expect(
      g.colorAt(4, 4, const LandscapeGenParams()),
      WorldTheme.paperDiorama.background,
    );
    expect(LandscapeCA(gen).step(g), greaterThan(0));
    expect(g.isVoid(4, 4), isTrue);
    expect(g.isEmpty(5, 4), isFalse);
    expect(g.uncover(4, 4, gen), isTrue);
    expect(g.isVoid(4, 4), isFalse);
    expect(g.materialAt(4, 4), isNotNull);
  });

  test('region fill floods connected like-material and stops at another', () {
    final g = grid();
    for (var y = 0; y < 5; y++) {
      for (var x = 0; x < 5; x++) {
        g.setMaterial(
          x,
          y,
          x == 2 ? LandscapeMaterial.grass : LandscapeMaterial.rock,
          0.5,
        );
      }
    }
    expect(
      g.fillConnectedMaterial(
        0,
        2,
        PaperColor.pink,
        allow: (x, y) => x >= 0 && x < 5 && y >= 0 && y < 5,
      ),
      isTrue,
    );
    expect(g.paintIds[g.index(0, 0)], PaperColor.pink.index);
    expect(g.paintIds[g.index(1, 4)], PaperColor.pink.index);
    expect(g.paintIds[g.index(2, 2)], LandscapeGrid.kNoPaint);
    expect(g.paintIds[g.index(3, 2)], LandscapeGrid.kNoPaint);
    expect(g.materialAt(2, 2), LandscapeMaterial.grass);
    expect(g.materialAt(3, 2), LandscapeMaterial.rock);
  });

  test('region fill does not cross a material divider or leave the region', () {
    final g = grid();
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 6; x++) {
        g.setMaterial(
          x,
          y,
          x == 2 ? LandscapeMaterial.grass : LandscapeMaterial.rock,
          0.5,
        );
      }
    }
    expect(
      g.fillConnectedMaterial(
        0,
        1,
        PaperColor.yellow,
        allow: (x, y) => x < 5,
      ),
      isTrue,
    );
    expect(g.paintIds[g.index(1, 1)], PaperColor.yellow.index);
    expect(g.paintIds[g.index(2, 1)], LandscapeGrid.kNoPaint);
    expect(g.paintIds[g.index(3, 1)], LandscapeGrid.kNoPaint);
    expect(g.paintIds[g.index(5, 1)], LandscapeGrid.kNoPaint);
  });

  test('region fill skips void and leaves the other rock pocket', () {
    final g = grid();
    for (var y = 0; y < 3; y++) {
      for (var x = 0; x < 5; x++) {
        g.setMaterial(x, y, LandscapeMaterial.rock, 0.5);
      }
      g.cover(2, y);
    }
    expect(g.fillConnectedMaterial(0, 1, PaperColor.green), isTrue);
    expect(g.paintIds[g.index(0, 1)], PaperColor.green.index);
    expect(g.paintIds[g.index(1, 1)], PaperColor.green.index);
    expect(g.isVoid(2, 1), isTrue);
    expect(g.paintIds[g.index(2, 1)], LandscapeGrid.kNoPaint);
    expect(g.paintIds[g.index(3, 1)], LandscapeGrid.kNoPaint);
    expect(g.paintIds[g.index(4, 1)], LandscapeGrid.kNoPaint);
  });
}
