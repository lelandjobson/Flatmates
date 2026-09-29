import 'package:flutter/material.dart';

/// Craft-paint swatches from the numbered chart.
///
/// [color] is the opaque guide. [fill] is the same swatch at 60% opacity,
/// which is what tool buttons paint.
enum CraftPalette {
  midnightBlue(0xFF004167),
  cerulean(0xFF0F8EAE),
  kentuckyBlue(0xFF0671B9),
  cyan(0xFF25A7E1),
  blue(0xFF115994),
  seaFoam(0xFF62BABC),
  babyBoy(0xFF94CAE6),
  turquoise(0xFF0FB6BE),
  salmon(0xFFF7796B),
  coral(0xFFF05952),
  hotPink(0xFFD53163),
  watermelon(0xFFEF597C),
  babyGirl(0xFFF88EA5),
  brick(0xFF722418),
  raspberry(0xFF942D4A),
  fuschia(0xFFB52062),
  scarlet(0xFFCF1C43),
  red(0xFFCE2021),
  ginger(0xFFF05D31),
  peach(0xFFF89A5A),
  orange(0xFFF78222),
  mango(0xFFFFB63B),
  butter(0xFFFED74B),
  lemon(0xFFF7DE29),
  chartreuse(0xFFBDD131),
  grass(0xFF5AA64B),
  lime(0xFF8BC242),
  emerald(0xFF097543),
  seaGreen(0xFF4AA673),
  pistachio(0xFF8CB2A5),
  springGreen(0xFFBED27B),
  icebergLettuce(0xFFCFE3A6),
  olive(0xFF9C9E39),
  forestGreen(0xFF516D32),
  beige(0xFFF0E7C6),
  goldenTan(0xFFC5A64B),
  carmel(0xFFBD8629),
  mulch(0xFF945E22),
  chocolate(0xFF6B4919),
  coffeeBean(0xFF523D10),
  granite(0xFF52697B),
  coldStone(0xFF6C6D72),
  stone(0xFF9D968C),
  warmGrey(0xFF72695A),
  tan(0xFFBEB28C),
  black(0xFF211C22),
  black85(0xFF4A4D52),
  black70(0xFF6C6D72),
  black55(0xFF8D8E93),
  black40(0xFFA5AAAD);

  const CraftPalette(this.argb);

  final int argb;

  Color get color => Color(argb);

  Color get fill => color.withValues(alpha: 0.6);
}
