import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/landscape/color_texture_catalog.dart';
import 'package:flatmates/theme/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('white maps to the paper asset; paint colors do not', () {
    expect(
      ColorTextureCatalog.assetFor(ColorTextureCatalog.white),
      ColorTextureCatalog.whiteAsset,
    );
    expect(ColorTextureCatalog.assetFor(const Color(0xFFFF0000)), isNull);
    for (final paper in PaperColor.values) {
      expect(
        ColorTextureCatalog.assetFor(WorldTheme.paperDiorama.paper(paper)),
        isNull,
      );
    }
  });

  testWidgets('loads the bundled white paper texture', (tester) async {
    final image = await tester.runAsync(
      () => ColorTextureCatalog.load(ColorTextureCatalog.white),
    );
    expect(image, isNotNull);
    expect(image!.width, greaterThan(0));
    expect(image.height, greaterThan(0));
    image.dispose();
    expect(
      await tester.runAsync(
        () => ColorTextureCatalog.load(const Color(0xFFFF0000)),
      ),
      isNull,
    );
  });
}
