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
}

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
}

/// Tunable generation parameters for the landscape debug experiment.
@immutable
class LandscapeGenParams {
  const LandscapeGenParams({
    this.seed = 42,
    this.tilesSide = 16,
    this.pixelsPerTile = 8,
    this.sharpness = 2,
    this.colorSigma = 0.22,
    this.noiseFrequency = 0.08,
    this.weights = const {
      LandscapeMaterial.rock: 22,
      LandscapeMaterial.grass: 28,
      LandscapeMaterial.dirt: 22,
      LandscapeMaterial.water: 18,
      LandscapeMaterial.flowers: 5,
      LandscapeMaterial.fruits: 3,
      LandscapeMaterial.vegetables: 2,
    },
    this.gradients = kDefaultGradients,
  });

  final int seed;
  final int tilesSide;
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

  static const Map<LandscapeMaterial, MaterialGradient> kDefaultGradients = {
    LandscapeMaterial.rock: MaterialGradient(
      start: HSLColor.fromAHSL(1, 0, 0.02, 0.28),
      end: HSLColor.fromAHSL(1, 0, 0.04, 0.72),
    ),
    LandscapeMaterial.grass: MaterialGradient(
      start: HSLColor.fromAHSL(1, 110, 0.45, 0.22),
      end: HSLColor.fromAHSL(1, 125, 0.55, 0.55),
    ),
    LandscapeMaterial.dirt: MaterialGradient(
      start: HSLColor.fromAHSL(1, 28, 0.40, 0.18),
      end: HSLColor.fromAHSL(1, 35, 0.45, 0.48),
    ),
    LandscapeMaterial.water: MaterialGradient(
      start: HSLColor.fromAHSL(1, 205, 0.55, 0.25),
      end: HSLColor.fromAHSL(1, 195, 0.65, 0.62),
    ),
    LandscapeMaterial.flowers: MaterialGradient(
      start: HSLColor.fromAHSL(1, 330, 0.55, 0.45),
      end: HSLColor.fromAHSL(1, 340, 0.70, 0.75),
    ),
    LandscapeMaterial.fruits: MaterialGradient(
      start: HSLColor.fromAHSL(1, 5, 0.65, 0.35),
      end: HSLColor.fromAHSL(1, 15, 0.75, 0.58),
    ),
    LandscapeMaterial.vegetables: MaterialGradient(
      start: HSLColor.fromAHSL(1, 280, 0.40, 0.28),
      end: HSLColor.fromAHSL(1, 295, 0.55, 0.55),
    ),
  };
}
