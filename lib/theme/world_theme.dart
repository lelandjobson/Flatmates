import 'package:flutter/material.dart';

import '../crafting/placed_paper.dart';
import '../gameplay/paint/plane_grain_model.dart';
import '../gameplay/paint/plane_shade_model.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_palette.dart';

/// World / craft color theme. UI chrome stays on [FmThemeData].
@immutable
class WorldTheme {
  const WorldTheme({
    required this.id,
    required this.label,
    required this.gradients,
    required this.papers,
    this.path = const Color(0xFFF4EFE6),
    this.wall = const Color(0xFFF4EFE6),
    this.volume = const Color(0xFFEEE9E0),
    this.volumeDraft = const Color(0xFFFFD54F),
    this.background = const Color(0xFFD8E8F0),
    this.shade = kPaperShade,
    this.colorSigma = 0.06,
    this.grainStrength = 0.066,
    this.grainFrequency = 0.126,
    this.grainOctaves = 2,
    this.grainSeed = 17,
    this.grainBias = 0.0,
    this.defaultOpacity = 1.0,
  });

  final String id;
  final String label;
  final Map<LandscapeMaterial, MaterialGradient> gradients;
  final Map<PaperColor, Color> papers;
  final Color path;
  final Color wall;
  final Color volume;
  final Color volumeDraft;
  final Color background;
  final PlaneShadeModel shade;
  final double colorSigma;
  final double grainStrength;
  final double grainFrequency;
  final int grainOctaves;
  final int grainSeed;
  final double grainBias;
  final double defaultOpacity;

  Color paper(PaperColor id) => papers[id] ?? id.color;

  MaterialGradient material(LandscapeMaterial id) =>
      gradients[id] ?? LandscapeGenParams.kDefaultGradients[id]!;

  PlaneGrainModel get grain => PlaneGrainModel(
        seed: grainSeed,
        frequency: grainFrequency,
        strength: grainStrength,
        octaves: grainOctaves,
        bias: grainBias,
      );

  LandscapePalette get asPalette => LandscapePalette(
        id: id,
        label: label,
        gradients: gradients,
        defaultOpacity: defaultOpacity,
      );

  Map<LandscapeMaterial, MaterialGradient> gradientsAt(double opacity) {
    return asPalette.gradientsAt(opacity);
  }

  List<Color> previewColors({double opacity = 1.0}) {
    return asPalette.previewColors(opacity: opacity);
  }

  static const PlaneShadeModel kPaperShade = PlaneShadeModel(
    lightX: -0.55,
    lightY: -1.0,
    lightZ: -0.35,
    minShade: 0.82,
    maxShade: 1.0,
    litTint: Color(0xFFFFE6B8),
    shadeTint: Color(0xFFA8B4C4),
    tintStrength: 0.10,
  );

  static const Map<PaperColor, Color> kPaperDioramaPapers = {
    PaperColor.pink: Color(0xFFF0B4C0),
    PaperColor.yellow: Color(0xFFF5E6C8),
    PaperColor.green: Color(0xFFB8E0C8),
  };

  static const Map<PaperColor, Color> kFallbackPapers = {
    PaperColor.pink: Color(0xFFFFB3BA),
    PaperColor.yellow: Color(0xFFFFF3B0),
    PaperColor.green: Color(0xFFBAFFC9),
  };

  /// Matte cardstock diorama — default world look.
  static const WorldTheme paperDiorama = WorldTheme(
    id: 'paper_diorama',
    label: 'Paper diorama',
    gradients: LandscapeGenParams.kDefaultGradients,
    papers: kPaperDioramaPapers,
  );

  static final WorldTheme waterLilies = WorldTheme._fromPalette(
    LandscapePalette.waterLilies,
    colorSigma: 0.22,
    grainStrength: 0.16,
    grainFrequency: 0.42,
    grainOctaves: 2,
    shade: const PlaneShadeModel(),
    path: const Color(0xFFBCAAA4),
    volume: const Color(0xFFF5F5F5),
    background: const Color(0xFF101418),
  );

  static final WorldTheme earthy = WorldTheme._fromPalette(
    LandscapePalette.earthy,
    colorSigma: 0.22,
    grainStrength: 0.14,
    grainFrequency: 0.36,
    grainOctaves: 2,
    shade: const PlaneShadeModel(),
    path: const Color(0xFFBCAAA4),
    volume: const Color(0xFFF5F5F5),
    background: const Color(0xFF101418),
  );

  static final WorldTheme craftingPaper = WorldTheme._fromPalette(
    LandscapePalette.craftingPaper,
    colorSigma: 0.08,
    grainStrength: 0.04,
    grainFrequency: 0.20,
    grainOctaves: 1,
    path: const Color(0xFFE8C9A8),
    volume: const Color(0xFFF4EFE6),
    background: const Color(0xFFD8E8F0),
  );

  static final WorldTheme construction = WorldTheme._fromPalette(
    LandscapePalette.construction,
    colorSigma: 0.10,
    grainStrength: 0.05,
    grainFrequency: 0.22,
    grainOctaves: 1,
  );

  static final WorldTheme constructionFaded = WorldTheme._fromPalette(
    LandscapePalette.constructionFaded,
    colorSigma: 0.08,
    grainStrength: 0.04,
    grainFrequency: 0.18,
    grainOctaves: 1,
    defaultOpacity: LandscapePalette.constructionFaded.defaultOpacity,
  );

  static final WorldTheme watercolorGarden = WorldTheme._fromPalette(
    LandscapePalette.watercolorGarden,
    colorSigma: 0.22,
    grainStrength: 0.16,
    grainFrequency: 0.42,
    grainOctaves: 2,
    shade: const PlaneShadeModel(),
    path: const Color(0xFFBCAAA4),
    volume: const Color(0xFFF5F5F5),
    background: const Color(0xFF101418),
    defaultOpacity: LandscapePalette.watercolorGarden.defaultOpacity,
  );

  static final WorldTheme watercolorCool = WorldTheme._fromPalette(
    LandscapePalette.watercolorCool,
    colorSigma: 0.22,
    grainStrength: 0.16,
    grainFrequency: 0.42,
    grainOctaves: 2,
    shade: const PlaneShadeModel(),
    path: const Color(0xFFBCAAA4),
    volume: const Color(0xFFF5F5F5),
    background: const Color(0xFF101418),
    defaultOpacity: LandscapePalette.watercolorCool.defaultOpacity,
  );

  static final WorldTheme watercolorWarm = WorldTheme._fromPalette(
    LandscapePalette.watercolorWarm,
    colorSigma: 0.22,
    grainStrength: 0.16,
    grainFrequency: 0.42,
    grainOctaves: 2,
    shade: const PlaneShadeModel(),
    path: const Color(0xFFBCAAA4),
    volume: const Color(0xFFF5F5F5),
    background: const Color(0xFF101418),
    defaultOpacity: LandscapePalette.watercolorWarm.defaultOpacity,
  );

  static final WorldTheme pastelSoft = WorldTheme._fromPalette(
    LandscapePalette.pastelSoft,
    colorSigma: 0.08,
    grainStrength: 0.04,
    grainFrequency: 0.20,
    grainOctaves: 1,
    defaultOpacity: LandscapePalette.pastelSoft.defaultOpacity,
  );

  static final WorldTheme pastelChalk = WorldTheme._fromPalette(
    LandscapePalette.pastelChalk,
    colorSigma: 0.10,
    grainStrength: 0.06,
    grainFrequency: 0.22,
    grainOctaves: 1,
    defaultOpacity: LandscapePalette.pastelChalk.defaultOpacity,
  );

  static final WorldTheme pastelOil = WorldTheme._fromPalette(
    LandscapePalette.pastelOil,
    colorSigma: 0.12,
    grainStrength: 0.08,
    grainFrequency: 0.28,
    grainOctaves: 2,
    defaultOpacity: LandscapePalette.pastelOil.defaultOpacity,
  );

  static final List<WorldTheme> all = [
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

  static WorldTheme byId(String id) {
    return all.firstWhere((t) => t.id == id, orElse: () => paperDiorama);
  }

  factory WorldTheme._fromPalette(
    LandscapePalette palette, {
    required double colorSigma,
    required double grainStrength,
    required double grainFrequency,
    required int grainOctaves,
    PlaneShadeModel shade = kPaperShade,
    Map<PaperColor, Color> papers = kFallbackPapers,
    Color path = const Color(0xFFF4EFE6),
    Color wall = const Color(0xFFF4EFE6),
    Color volume = const Color(0xFFEEE9E0),
    Color volumeDraft = const Color(0xFFFFD54F),
    Color background = const Color(0xFFD8E8F0),
    double? defaultOpacity,
  }) {
    return WorldTheme(
      id: palette.id,
      label: palette.label,
      gradients: palette.gradients,
      papers: papers,
      path: path,
      wall: wall,
      volume: volume,
      volumeDraft: volumeDraft,
      background: background,
      shade: shade,
      colorSigma: colorSigma,
      grainStrength: grainStrength,
      grainFrequency: grainFrequency,
      grainOctaves: grainOctaves,
      defaultOpacity: defaultOpacity ?? palette.defaultOpacity,
    );
  }

  @override
  bool operator ==(Object other) => other is WorldTheme && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

extension PaperColorResolve on PaperColor {
  Color resolve([WorldTheme? theme]) =>
      (theme ?? WorldTheme.paperDiorama).paper(this);
}
