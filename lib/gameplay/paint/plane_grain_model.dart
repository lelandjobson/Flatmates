import 'package:flutter/material.dart';

import '../../rendering/iso/perlin_noise.dart';

/// Fast painterly grain: one Perlin sample per subtile, then a little
/// black or white mixed into the already-shaded paper color.
class PlaneGrainModel {
  PlaneGrainModel({
    this.seed = 17,
    this.frequency = 0.42,
    this.strength = 0.16,
    this.octaves = 2,
    this.bias = 0.0,
  }) : _noise = PerlinNoise(seed: seed);

  final int seed;

  /// Spatial scale in subtile units. Higher = finer dabs.
  final double frequency;

  /// How far a pixel moves toward black or white (0 = off).
  final double strength;

  /// FBM layers. 1 is cheapest; 2–3 looks more paper-like.
  final int octaves;

  /// Shift the field toward white (+) or black (−).
  final double bias;

  final PerlinNoise _noise;

  /// Signed grain in [-1, 1] for this subtile.
  double sample({
    required int tx,
    required int ty,
    required int u,
    required int v,
    required int faceIndex,
  }) {
    final gx = tx * 16.0 + u + faceIndex * 19.1;
    final gy = ty * 16.0 + v + faceIndex * 11.3;
    final freq = frequency.clamp(0.02, 4.0);
    final n = octaves <= 1
        ? _noise.noise2(gx * freq, gy * freq)
        : _noise.fbm2(
            gx * freq,
            gy * freq,
            octaves: octaves.clamp(1, 4),
          );
    return (n + bias.clamp(-1.0, 1.0)).clamp(-1.0, 1.0);
  }

  Color apply(
    Color color, {
    required int tx,
    required int ty,
    required int u,
    required int v,
    required int faceIndex,
  }) {
    final amount = strength.clamp(0.0, 1.0);
    if (amount <= 1e-6) return color;
    final n = sample(
      tx: tx,
      ty: ty,
      u: u,
      v: v,
      faceIndex: faceIndex,
    );
    final ink = n >= 0 ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
    return Color.lerp(color, ink, n.abs() * amount)!.withValues(alpha: color.a);
  }

  PlaneGrainModel copyWith({
    int? seed,
    double? frequency,
    double? strength,
    int? octaves,
    double? bias,
  }) {
    return PlaneGrainModel(
      seed: seed ?? this.seed,
      frequency: frequency ?? this.frequency,
      strength: strength ?? this.strength,
      octaves: octaves ?? this.octaves,
      bias: bias ?? this.bias,
    );
  }
}
