import 'package:flatmates/ui/craft_palette.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('named swatches keep the chart color and paint at 60%', () {
    expect(CraftPalette.midnightBlue.color.toARGB32(), 0xFF004167);
    expect(CraftPalette.scarlet.color.toARGB32(), 0xFFCF1C43);
    expect(CraftPalette.chartreuse.color.toARGB32(), 0xFFBDD131);
    expect(CraftPalette.black.color.toARGB32(), 0xFF211C22);
    for (final swatch in CraftPalette.values) {
      expect(swatch.color.a, 1);
      expect(swatch.fill.a, closeTo(0.6, 1e-6));
      expect(swatch.fill.r, closeTo(swatch.color.r, 1e-6));
      expect(swatch.fill.g, closeTo(swatch.color.g, 1e-6));
      expect(swatch.fill.b, closeTo(swatch.color.b, 1e-6));
    }
  });
}
