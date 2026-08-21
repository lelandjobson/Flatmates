import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/landscape/landscape_ca.dart';
import 'package:flatmates/landscape/landscape_generator.dart';
import 'package:flatmates/landscape/landscape_grid.dart';
import 'package:flatmates/landscape/landscape_material.dart';
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
      PaperColor.pink.color,
    );
    expect(g.erase(2, 3), isTrue);
    expect(g.isEmpty(2, 3), isTrue);
    expect(
      g.colorAt(2, 3, const LandscapeGenParams()),
      kLandscapeEmptyColor,
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
    expect(g.colorAt(1, 1, const LandscapeGenParams()), PaperColor.pink.color);
    expect(g.colorAt(3, 3, const LandscapeGenParams()), PaperColor.pink.color);
    expect(g.colorAt(2, 2, const LandscapeGenParams()), PaperColor.yellow.color);
    expect(g.fill(2, 2, PaperColor.green), isTrue);
    expect(g.colorAt(2, 2, const LandscapeGenParams()), PaperColor.green.color);
    expect(g.colorAt(1, 1, const LandscapeGenParams()), PaperColor.pink.color);
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
      kLandscapeEmptyColor,
    );
    expect(LandscapeCA(gen).step(g), greaterThan(0));
    expect(g.isVoid(4, 4), isTrue);
    expect(g.isEmpty(5, 4), isFalse);
    expect(g.uncover(4, 4, gen), isTrue);
    expect(g.isVoid(4, 4), isFalse);
    expect(g.materialAt(4, 4), isNotNull);
  });
}
