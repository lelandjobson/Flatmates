import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/landscape/landscape_ca.dart';
import 'package:flatmates/landscape/landscape_generator.dart';
import 'package:flatmates/landscape/landscape_grid.dart';
import 'package:flatmates/landscape/landscape_material.dart';
import 'package:flutter_test/flutter_test.dart';

LandscapeGenerator gen() => LandscapeGenerator(
      const LandscapeGenParams(tilesSide: 4, pixelsPerTile: 4, sharpness: 1),
    );

LandscapeGrid blank({
  LandscapeMaterial fill = LandscapeMaterial.grass,
}) {
  final g = LandscapeGrid.fromGenerator(gen());
  for (var y = 0; y < g.side; y++) {
    for (var x = 0; x < g.side; x++) {
      g.setMaterial(x, y, fill, 0.5);
    }
  }
  return g;
}

void main() {
  test('CA only writes empty cells and leaves existing landscape alone', () {
    final g = blank();
    g.paint(2, 2, PaperColor.pink);
    g.erase(3, 2);
    expect(LandscapeCA(gen()).step(g), 1);
    expect(g.materialAt(3, 2), LandscapeMaterial.grass);
    expect(g.paintIds[g.index(2, 2)], PaperColor.pink.index);
    expect(g.materialAt(2, 2), LandscapeMaterial.grass);
    expect(g.paintIds[g.index(1, 2)], LandscapeGrid.kNoPaint);
  });

  test('void coverage is never filled and never sampled', () {
    final g = blank(fill: LandscapeMaterial.dirt);
    g.cover(4, 4);
    g.erase(5, 4);
    g.setMaterial(6, 4, LandscapeMaterial.water, 0.5);
    // Hole sits between void and a single water; dirt is also adjacent.
    expect(LandscapeCA(gen()).step(g), 1);
    expect(g.isVoid(4, 4), isTrue);
    expect(g.materialAt(4, 4), isNull);
    expect(g.materialAt(5, 4), isNotNull);
    expect(g.isEmpty(5, 4), isFalse);
  });

  test('paint on a neighbor does not spread; hole fills from material', () {
    final g = blank(fill: LandscapeMaterial.rock);
    g.paint(2, 2, PaperColor.pink);
    g.erase(3, 2);
    LandscapeCA(gen()).step(g);
    expect(g.paintIds[g.index(3, 2)], LandscapeGrid.kNoPaint);
    expect(g.materialAt(3, 2), LandscapeMaterial.rock);
  });

  test('open-ground CA ignores materials inside a walled region', () {
    final g = blank(fill: LandscapeMaterial.grass);
    // Tile (1,1) → pixels [4,8) x [4,8).
    for (var y = 4; y < 8; y++) {
      for (var x = 4; x < 8; x++) {
        g.setMaterial(x, y, LandscapeMaterial.rock, 0.5);
      }
    }
    g.erase(3, 5);
    final filled = LandscapeCA(gen()).step(
      g,
      inDomain: (x, y) => x < 4 || x >= 8 || y < 4 || y >= 8,
    );
    expect(filled, 1);
    expect(g.materialAt(3, 5), LandscapeMaterial.grass);
    expect(g.materialAt(3, 5), isNot(LandscapeMaterial.rock));
  });

  test('region paint CA grows into erased cells and ignores outside paint', () {
    final g = blank(fill: LandscapeMaterial.dirt);
    g.paint(3, 5, PaperColor.yellow);
    g.erase(4, 5);
    g.erase(5, 5);
    g.paint(5, 5, PaperColor.pink);
    final filled = RegionPaintCA().step(
      g,
      inDomain: (x, y) => x >= 4 && x < 8 && y >= 4 && y < 8,
    );
    expect(filled, 1);
    expect(g.isEmpty(4, 5), isTrue);
    expect(g.paintIds[g.index(4, 5)], PaperColor.pink.index);
    expect(g.materialAt(4, 5), isNull);
  });

  test('morning runner refills open ground and grows paint only inside rooms', () {
    final g = blank(fill: LandscapeMaterial.grass);
    for (var y = 4; y < 8; y++) {
      for (var x = 4; x < 8; x++) {
        g.setMaterial(x, y, LandscapeMaterial.rock, 0.5);
      }
    }
    g.erase(3, 5);
    g.erase(5, 5);
    g.paint(6, 5, PaperColor.green);
    final filled = MorningLandscapeCA.run(
      grid: g,
      generator: gen(),
      regions: [WallRegion({(1, 1)})],
      subtilesPerTile: 4,
    );
    expect(filled, greaterThan(0));
    expect(g.materialAt(3, 5), LandscapeMaterial.grass);
    expect(g.isEmpty(5, 5), isTrue);
    expect(g.materialAt(5, 5), isNull);
    expect(g.paintIds[g.index(5, 5)], PaperColor.green.index);
    expect(g.materialAt(6, 5), LandscapeMaterial.rock);
  });

  test('morning runner does not regenerate landscape inside a region hole', () {
    final g = blank(fill: LandscapeMaterial.grass);
    for (var y = 4; y < 8; y++) {
      for (var x = 4; x < 8; x++) {
        g.erase(x, y);
      }
    }
    MorningLandscapeCA.run(
      grid: g,
      generator: gen(),
      regions: [WallRegion({(1, 1)})],
      subtilesPerTile: 4,
    );
    expect(g.isEmpty(5, 5), isTrue);
    expect(g.materialAt(5, 5), isNull);
    expect(g.paintIds[g.index(5, 5)], LandscapeGrid.kNoPaint);
  });

  test('five generations refill a hole from the rim inward', () {
    final g = blank(fill: LandscapeMaterial.grass);
    for (var y = 2; y <= 13; y++) {
      for (var x = 2; x <= 13; x++) {
        g.erase(x, y);
      }
    }
    expect(
      LandscapeCA(gen()).stepGenerations(
        g,
        MorningLandscapeCA.generationsPerDay,
      ),
      greaterThan(0),
    );
    expect(g.isEmpty(2, 2), isFalse);
    expect(g.materialAt(2, 2), LandscapeMaterial.grass);
    expect(g.isEmpty(8, 8), isTrue);
  });

  test('landscapePixelsForTiles expands each tile into subtiles', () {
    expect(
      landscapePixelsForTiles({(1, 2)}, 2),
      {(2, 4), (3, 4), (2, 5), (3, 5)},
    );
  });
}
