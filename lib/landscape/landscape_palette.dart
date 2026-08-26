import 'package:flutter/material.dart';

import '../crafting/placed_paper.dart';
import 'landscape_material.dart';

/// Named map-material colorways for the 3D bench (and later GameView).
@immutable
class LandscapePalette {
  const LandscapePalette({
    required this.id,
    required this.label,
    required this.gradients,
    this.defaultOpacity = 1.0,
  });

  final String id;
  final String label;
  final Map<LandscapeMaterial, MaterialGradient> gradients;

  /// Suggested opacity when this palette is first selected.
  final double defaultOpacity;

  Map<LandscapeMaterial, MaterialGradient> gradientsAt(double opacity) {
    if (opacity >= 1) return gradients;
    return {
      for (final e in gradients.entries) e.key: e.value.withOpacity(opacity),
    };
  }

  /// Mid-stop swatch per material, in [LandscapeMaterial] order.
  List<Color> previewColors({double opacity = 1.0}) {
    return [
      for (final m in LandscapeMaterial.values)
        gradients[m]!.withOpacity(opacity).sample(0.55),
    ];
  }

  static final LandscapePalette paperDiorama = LandscapePalette(
    id: 'paper_diorama',
    label: 'Paper diorama',
    gradients: LandscapeGenParams.kDefaultGradients,
  );

  static final LandscapePalette waterLilies = LandscapePalette(
    id: 'water_lilies',
    label: 'Water Lilies',
    gradients: LandscapeGenParams.kWaterLiliesGradients,
  );

  static final LandscapePalette earthy = LandscapePalette(
    id: 'earthy',
    label: 'Earthy',
    gradients: {
      LandscapeMaterial.rock: _g(0, 0.02, 0.28, 0, 0.04, 0.72),
      LandscapeMaterial.grass: _g(110, 0.45, 0.22, 125, 0.55, 0.55),
      LandscapeMaterial.dirt: _g(28, 0.40, 0.18, 35, 0.45, 0.48),
      LandscapeMaterial.water: _g(205, 0.55, 0.25, 195, 0.65, 0.62),
      LandscapeMaterial.flowers: _g(330, 0.55, 0.45, 340, 0.70, 0.75),
      LandscapeMaterial.fruits: _g(5, 0.65, 0.35, 15, 0.75, 0.58),
      LandscapeMaterial.vegetables: _g(280, 0.40, 0.28, 295, 0.55, 0.55),
    },
  );

  /// Same pastel family as [PaperColor] / the crafting paintbrush.
  static final LandscapePalette craftingPaper = LandscapePalette(
    id: 'crafting_paper',
    label: 'Crafting paper',
    gradients: _craftingPaperGradients(),
  );

  static final LandscapePalette construction = LandscapePalette(
    id: 'construction',
    label: 'Construction paper',
    defaultOpacity: 1.0,
    gradients: {
      LandscapeMaterial.rock: _g(220, 0.08, 0.34, 210, 0.06, 0.58),
      LandscapeMaterial.grass: _g(128, 0.64, 0.30, 135, 0.58, 0.50),
      LandscapeMaterial.dirt: _g(26, 0.50, 0.26, 32, 0.46, 0.48),
      LandscapeMaterial.water: _g(206, 0.72, 0.36, 198, 0.68, 0.58),
      LandscapeMaterial.flowers: _g(328, 0.74, 0.46, 338, 0.70, 0.68),
      LandscapeMaterial.fruits: _g(6, 0.80, 0.40, 14, 0.74, 0.60),
      LandscapeMaterial.vegetables: _g(274, 0.50, 0.36, 286, 0.46, 0.56),
    },
  );

  static final LandscapePalette constructionFaded = LandscapePalette(
    id: 'construction_faded',
    label: 'Faded construction',
    defaultOpacity: 0.92,
    gradients: {
      LandscapeMaterial.rock: _g(220, 0.05, 0.52, 210, 0.04, 0.74),
      LandscapeMaterial.grass: _g(128, 0.36, 0.48, 135, 0.32, 0.68),
      LandscapeMaterial.dirt: _g(28, 0.28, 0.46, 34, 0.26, 0.66),
      LandscapeMaterial.water: _g(204, 0.38, 0.54, 196, 0.34, 0.74),
      LandscapeMaterial.flowers: _g(330, 0.38, 0.62, 340, 0.34, 0.80),
      LandscapeMaterial.fruits: _g(8, 0.42, 0.56, 16, 0.38, 0.74),
      LandscapeMaterial.vegetables: _g(276, 0.26, 0.52, 288, 0.22, 0.70),
    },
  );

  static final LandscapePalette watercolorGarden = LandscapePalette(
    id: 'watercolor_garden',
    label: 'Watercolor garden',
    defaultOpacity: 0.72,
    gradients: {
      LandscapeMaterial.rock: _g(32, 0.10, 0.50, 28, 0.08, 0.74),
      LandscapeMaterial.grass: _g(108, 0.40, 0.40, 122, 0.36, 0.66),
      LandscapeMaterial.dirt: _g(30, 0.34, 0.40, 36, 0.28, 0.64),
      LandscapeMaterial.water: _g(198, 0.44, 0.48, 188, 0.38, 0.74),
      LandscapeMaterial.flowers: _g(342, 0.42, 0.56, 350, 0.36, 0.80),
      LandscapeMaterial.fruits: _g(8, 0.46, 0.48, 16, 0.40, 0.72),
      LandscapeMaterial.vegetables: _g(268, 0.28, 0.46, 280, 0.24, 0.70),
    },
  );

  static final LandscapePalette watercolorCool = LandscapePalette(
    id: 'watercolor_cool',
    label: 'Watercolor cool',
    defaultOpacity: 0.70,
    gradients: {
      LandscapeMaterial.rock: _g(220, 0.08, 0.54, 216, 0.05, 0.76),
      LandscapeMaterial.grass: _g(158, 0.30, 0.44, 168, 0.26, 0.68),
      LandscapeMaterial.dirt: _g(22, 0.14, 0.44, 28, 0.10, 0.66),
      LandscapeMaterial.water: _g(214, 0.50, 0.46, 206, 0.42, 0.76),
      LandscapeMaterial.flowers: _g(278, 0.30, 0.60, 290, 0.24, 0.82),
      LandscapeMaterial.fruits: _g(348, 0.34, 0.54, 356, 0.28, 0.76),
      LandscapeMaterial.vegetables: _g(248, 0.32, 0.42, 258, 0.26, 0.66),
    },
  );

  static final LandscapePalette watercolorWarm = LandscapePalette(
    id: 'watercolor_warm',
    label: 'Watercolor warm',
    defaultOpacity: 0.74,
    gradients: {
      LandscapeMaterial.rock: _g(38, 0.20, 0.54, 34, 0.14, 0.78),
      LandscapeMaterial.grass: _g(84, 0.34, 0.40, 92, 0.28, 0.62),
      LandscapeMaterial.dirt: _g(18, 0.44, 0.36, 26, 0.36, 0.60),
      LandscapeMaterial.water: _g(184, 0.30, 0.50, 176, 0.24, 0.72),
      LandscapeMaterial.flowers: _g(12, 0.46, 0.60, 20, 0.38, 0.84),
      LandscapeMaterial.fruits: _g(6, 0.54, 0.46, 14, 0.46, 0.70),
      LandscapeMaterial.vegetables: _g(312, 0.24, 0.40, 322, 0.18, 0.62),
    },
  );

  static final LandscapePalette pastelSoft = LandscapePalette(
    id: 'pastel_soft',
    label: 'Soft pastel',
    defaultOpacity: 0.86,
    gradients: {
      LandscapeMaterial.rock: _g(40, 0.08, 0.72, 36, 0.05, 0.90),
      LandscapeMaterial.grass: _g(132, 0.30, 0.70, 140, 0.26, 0.88),
      LandscapeMaterial.dirt: _g(36, 0.30, 0.68, 42, 0.24, 0.86),
      LandscapeMaterial.water: _g(200, 0.34, 0.72, 192, 0.28, 0.90),
      LandscapeMaterial.flowers: _g(340, 0.36, 0.76, 348, 0.30, 0.92),
      LandscapeMaterial.fruits: _g(20, 0.40, 0.70, 28, 0.34, 0.88),
      LandscapeMaterial.vegetables: _g(276, 0.24, 0.68, 286, 0.18, 0.86),
    },
  );

  static final LandscapePalette pastelChalk = LandscapePalette(
    id: 'pastel_chalk',
    label: 'Chalk pastel',
    defaultOpacity: 0.90,
    gradients: {
      LandscapeMaterial.rock: _g(42, 0.10, 0.58, 36, 0.06, 0.78),
      LandscapeMaterial.grass: _g(124, 0.40, 0.50, 132, 0.34, 0.72),
      LandscapeMaterial.dirt: _g(30, 0.34, 0.48, 36, 0.28, 0.70),
      LandscapeMaterial.water: _g(204, 0.42, 0.54, 196, 0.36, 0.76),
      LandscapeMaterial.flowers: _g(334, 0.44, 0.58, 344, 0.36, 0.78),
      LandscapeMaterial.fruits: _g(12, 0.50, 0.54, 20, 0.42, 0.74),
      LandscapeMaterial.vegetables: _g(284, 0.30, 0.50, 294, 0.24, 0.70),
    },
  );

  static final LandscapePalette pastelOil = LandscapePalette(
    id: 'pastel_oil',
    label: 'Oil pastel',
    defaultOpacity: 0.94,
    gradients: {
      LandscapeMaterial.rock: _g(36, 0.12, 0.48, 30, 0.08, 0.70),
      LandscapeMaterial.grass: _g(116, 0.44, 0.38, 126, 0.38, 0.62),
      LandscapeMaterial.dirt: _g(30, 0.50, 0.36, 38, 0.42, 0.58),
      LandscapeMaterial.water: _g(192, 0.44, 0.42, 184, 0.36, 0.66),
      LandscapeMaterial.flowers: _g(348, 0.52, 0.48, 356, 0.44, 0.70),
      LandscapeMaterial.fruits: _g(16, 0.60, 0.46, 24, 0.50, 0.68),
      LandscapeMaterial.vegetables: _g(292, 0.38, 0.38, 302, 0.30, 0.58),
    },
  );

  static final List<LandscapePalette> all = [
    paperDiorama,
    waterLilies,
    earthy,
    craftingPaper,
    construction,
    constructionFaded,
    watercolorGarden,
    watercolorCool,
    watercolorWarm,
    pastelSoft,
    pastelChalk,
    pastelOil,
  ];

  static LandscapePalette byId(String id) {
    return all.firstWhere((p) => p.id == id, orElse: () => paperDiorama);
  }

  @override
  bool operator ==(Object other) =>
      other is LandscapePalette && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

MaterialGradient _g(
  double h0,
  double s0,
  double l0,
  double h1,
  double s1,
  double l1,
) {
  return MaterialGradient(
    start: HSLColor.fromAHSL(1, h0, s0, l0),
    end: HSLColor.fromAHSL(1, h1, s1, l1),
  );
}

Map<LandscapeMaterial, MaterialGradient> _craftingPaperGradients() {
  final pink = HSLColor.fromColor(PaperColor.pink.color);
  final yellow = HSLColor.fromColor(PaperColor.yellow.color);
  final green = HSLColor.fromColor(PaperColor.green.color);
  final peach = HSLColor.fromColor(
    Color.lerp(PaperColor.pink.color, PaperColor.yellow.color, 0.42)!,
  );
  final pulp = HSLColor.fromColor(
    Color.lerp(
      Color.lerp(PaperColor.pink.color, PaperColor.yellow.color, 0.55)!,
      PaperColor.green.color,
      0.18,
    )!,
  );
  return {
    LandscapeMaterial.rock: _around(pulp, dS: -0.55, dL: 0.10),
    LandscapeMaterial.grass: _around(green, dS: -0.18, dL: 0.10),
    LandscapeMaterial.dirt: _around(yellow, hueShift: -6, dS: -0.22, dL: 0.12),
    LandscapeMaterial.water: _around(
      green,
      hueShift: 42,
      dS: -0.28,
      dL: 0.08,
    ),
    LandscapeMaterial.flowers: _around(pink, dS: -0.12, dL: 0.08),
    LandscapeMaterial.fruits: _around(peach, dS: -0.10, dL: 0.10),
    LandscapeMaterial.vegetables: _around(
      green,
      hueShift: 12,
      dS: -0.25,
      dL: -0.06,
    ),
  };
}

MaterialGradient _around(
  HSLColor color, {
  double dL = 0.12,
  double dS = 0.0,
  double hueShift = 0,
}) {
  final h = (color.hue + hueShift) % 360;
  return MaterialGradient(
    start: HSLColor.fromAHSL(
      1,
      h,
      (color.saturation + dS).clamp(0.0, 1.0),
      (color.lightness - dL.abs()).clamp(0.0, 1.0),
    ),
    end: HSLColor.fromAHSL(
      1,
      h,
      (color.saturation + dS * 0.4).clamp(0.0, 1.0),
      (color.lightness + dL.abs()).clamp(0.0, 1.0),
    ),
  );
}
