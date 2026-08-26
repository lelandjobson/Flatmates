import 'package:flutter/material.dart';

/// Landscape material kinds for procedural tile sprites.
enum LandscapeMaterial {
  rock,
  grass,
  dirt,
  water,
  flowers,
  fruits,
  vegetables,
}

extension LandscapeMaterialX on LandscapeMaterial {
  String get label => switch (this) {
        LandscapeMaterial.rock => 'Rock',
        LandscapeMaterial.grass => 'Grass',
        LandscapeMaterial.dirt => 'Dirt',
        LandscapeMaterial.water => 'Water',
        LandscapeMaterial.flowers => 'Flowers',
        LandscapeMaterial.fruits => 'Fruits',
        LandscapeMaterial.vegetables => 'Vegetables',
      };

  bool get isTerrain => kLandscapeTerrainFlow.contains(this);
  bool get isForage => kLandscapeForage.contains(this);
}

/// Wet → dry ground continuum. One noise field flows through this order.
const kLandscapeTerrainFlow = <LandscapeMaterial>[
  LandscapeMaterial.water,
  LandscapeMaterial.dirt,
  LandscapeMaterial.grass,
  LandscapeMaterial.rock,
];

/// Patch overlays stamped from a second noise field.
const kLandscapeForage = <LandscapeMaterial>[
  LandscapeMaterial.flowers,
  LandscapeMaterial.fruits,
  LandscapeMaterial.vegetables,
];

/// Start/end HSL endpoints defining a material color gradient.
@immutable
class MaterialGradient {
  const MaterialGradient({required this.start, required this.end});

  final HSLColor start;
  final HSLColor end;

  Color sample(double t) {
    final clamped = t.clamp(0.0, 1.0);
    return HSLColor.lerp(start, end, clamped)!.toColor();
  }

  MaterialGradient copyWith({HSLColor? start, HSLColor? end}) {
    return MaterialGradient(start: start ?? this.start, end: end ?? this.end);
  }

  /// Replace both endpoints' alpha. Hue / saturation / lightness stay put.
  MaterialGradient withOpacity(double alpha) {
    final a = alpha.clamp(0.0, 1.0);
    return MaterialGradient(start: start.withAlpha(a), end: end.withAlpha(a));
  }
}

/// Tunable generation parameters for the landscape debug experiment.
@immutable
class LandscapeGenParams {
  const LandscapeGenParams({
    this.seed = 42,
    this.tilesSide = 45,
    this.pixelsPerTile = 8,
    this.sharpness = 2,
    this.colorSigma = 0.06,
    this.noiseFrequency = 0.010,
    this.weights = const {
      LandscapeMaterial.rock: 22,
      LandscapeMaterial.grass: 25.4,
      LandscapeMaterial.dirt: 5.2,
      LandscapeMaterial.water: 18.0,
      LandscapeMaterial.flowers: 5,
      LandscapeMaterial.fruits: 3,
      LandscapeMaterial.vegetables: 2,
    },
    this.gradients = kDefaultGradients,
  });

  final int seed;
  final int tilesSide;

  /// Subtiles (material cells) along one tile edge. Also the atlas texel
  /// count per tile before sharpness upscale.
  int get subtilesPerTile => pixelsPerTile;

  final int pixelsPerTile;
  final int sharpness;
  final double colorSigma;
  final double noiseFrequency;
  final Map<LandscapeMaterial, double> weights;
  final Map<LandscapeMaterial, MaterialGradient> gradients;

  static const int maxTilesSide = 48;
  static const int maxPixelsPerTile = 32;
  static const int maxSharpness = 8;
  static const int maxAtlasEdge = 2048;
  static const int softWarnPixels = 4 * 1024 * 1024;

  /// World extent in material pixels along one axis.
  int get worldPixelsSide => tilesSide * pixelsPerTile;

  /// Final atlas edge length after sharpness upscale.
  int get atlasEdge => worldPixelsSide * sharpness;

  int get atlasPixelCount => atlasEdge * atlasEdge;

  bool get exceedsSoftWarn => atlasPixelCount > softWarnPixels;

  /// Clamp atlas so edge ≤ [maxAtlasEdge] by reducing sharpness first.
  LandscapeGenParams clamped() {
    var n = tilesSide.clamp(1, maxTilesSide);
    var s = pixelsPerTile.clamp(1, maxPixelsPerTile);
    var r = sharpness.clamp(1, maxSharpness);
    while (n * s * r > maxAtlasEdge && r > 1) {
      r--;
    }
    while (n * s * r > maxAtlasEdge && s > 1) {
      s--;
    }
    while (n * s * r > maxAtlasEdge && n > 1) {
      n--;
    }
    return copyWith(tilesSide: n, pixelsPerTile: s, sharpness: r);
  }

  List<double> normalizedWeights() {
    final ordered = LandscapeMaterial.values;
    final raw = ordered.map((m) => (weights[m] ?? 0).clamp(0.0, 1000.0));
    final sum = raw.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) {
      return List<double>.filled(ordered.length, 1 / ordered.length);
    }
    return raw.map((w) => w / sum).toList(growable: false);
  }

  LandscapeGenParams copyWith({
    int? seed,
    int? tilesSide,
    int? pixelsPerTile,
    int? sharpness,
    double? colorSigma,
    double? noiseFrequency,
    Map<LandscapeMaterial, double>? weights,
    Map<LandscapeMaterial, MaterialGradient>? gradients,
  }) {
    return LandscapeGenParams(
      seed: seed ?? this.seed,
      tilesSide: tilesSide ?? this.tilesSide,
      pixelsPerTile: pixelsPerTile ?? this.pixelsPerTile,
      sharpness: sharpness ?? this.sharpness,
      colorSigma: colorSigma ?? this.colorSigma,
      noiseFrequency: noiseFrequency ?? this.noiseFrequency,
      weights: weights ?? this.weights,
      gradients: gradients ?? this.gradients,
    );
  }

  /// Matte cardstock diorama (default). Narrow HSL ranges, high lightness.
  static const Map<LandscapeMaterial, MaterialGradient> kDefaultGradients = {
    LandscapeMaterial.rock: MaterialGradient(
      start: HSLColor.fromAHSL(1, 220, 0.06, 0.58),
      end: HSLColor.fromAHSL(1, 210, 0.04, 0.78),
    ),
    LandscapeMaterial.grass: MaterialGradient(
      start: HSLColor.fromAHSL(1, 140, 0.28, 0.62),
      end: HSLColor.fromAHSL(1, 128, 0.32, 0.78),
    ),
    LandscapeMaterial.dirt: MaterialGradient(
      start: HSLColor.fromAHSL(1, 22, 0.32, 0.52),
      end: HSLColor.fromAHSL(1, 28, 0.28, 0.70),
    ),
    LandscapeMaterial.water: MaterialGradient(
      start: HSLColor.fromAHSL(1, 196, 0.28, 0.58),
      end: HSLColor.fromAHSL(1, 200, 0.22, 0.76),
    ),
    LandscapeMaterial.flowers: MaterialGradient(
      start: HSLColor.fromAHSL(1, 348, 0.32, 0.62),
      end: HSLColor.fromAHSL(1, 354, 0.28, 0.80),
    ),
    LandscapeMaterial.fruits: MaterialGradient(
      start: HSLColor.fromAHSL(1, 24, 0.42, 0.64),
      end: HSLColor.fromAHSL(1, 32, 0.36, 0.80),
    ),
    LandscapeMaterial.vegetables: MaterialGradient(
      start: HSLColor.fromAHSL(1, 132, 0.30, 0.52),
      end: HSLColor.fromAHSL(1, 140, 0.26, 0.70),
    ),
  };

  /// Sampled from Monet's *Water Lilies*.
  static const Map<LandscapeMaterial, MaterialGradient> kWaterLiliesGradients = {
    LandscapeMaterial.rock: MaterialGradient(
      start: HSLColor.fromAHSL(1, 268, 0.16, 0.30),
      end: HSLColor.fromAHSL(1, 215, 0.08, 0.56),
    ),
    LandscapeMaterial.grass: MaterialGradient(
      start: HSLColor.fromAHSL(1, 128, 0.32, 0.26),
      end: HSLColor.fromAHSL(1, 98, 0.24, 0.56),
    ),
    LandscapeMaterial.dirt: MaterialGradient(
      start: HSLColor.fromAHSL(1, 172, 0.28, 0.20),
      end: HSLColor.fromAHSL(1, 95, 0.14, 0.36),
    ),
    LandscapeMaterial.water: MaterialGradient(
      start: HSLColor.fromAHSL(1, 201, 0.42, 0.30),
      end: HSLColor.fromAHSL(1, 214, 0.18, 0.58),
    ),
    LandscapeMaterial.flowers: MaterialGradient(
      start: HSLColor.fromAHSL(1, 339, 0.36, 0.36),
      end: HSLColor.fromAHSL(1, 8, 0.40, 0.70),
    ),
    LandscapeMaterial.fruits: MaterialGradient(
      start: HSLColor.fromAHSL(1, 50, 0.30, 0.52),
      end: HSLColor.fromAHSL(1, 68, 0.32, 0.74),
    ),
    LandscapeMaterial.vegetables: MaterialGradient(
      start: HSLColor.fromAHSL(1, 90, 0.42, 0.28),
      end: HSLColor.fromAHSL(1, 105, 0.28, 0.50),
    ),
  };
}
