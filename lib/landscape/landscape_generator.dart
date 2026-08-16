import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../rendering/iso/perlin_noise.dart';
import 'landscape_material.dart';

/// Seeds a world-pixel landscape and bakes it to a sharp [ui.Image] atlas.
class LandscapeGenerator {
  LandscapeGenerator(this.params)
      : _noise = PerlinNoise(seed: params.seed),
        _cdf = _buildCdf(params.normalizedWeights());

  final LandscapeGenParams params;
  final PerlinNoise _noise;
  final List<double> _cdf;

  static List<double> _buildCdf(List<double> weights) {
    final cdf = List<double>.filled(weights.length, 0);
    var acc = 0.0;
    for (var i = 0; i < weights.length; i++) {
      acc += weights[i];
      cdf[i] = acc;
    }
    if (cdf.isNotEmpty) cdf[cdf.length - 1] = 1.0;
    return cdf;
  }

  LandscapeMaterial materialAt(int wx, int wy) {
    final freq = params.noiseFrequency;
    final warpX = _noise.noise2(wx * freq * 0.5, wy * freq * 0.5) * 4.0;
    final warpY =
        _noise.noise2(wx * freq * 0.5 + 17.3, wy * freq * 0.5 - 9.1) * 4.0;
    final n = _noise.fbm2(
      (wx + warpX) * freq,
      (wy + warpY) * freq,
      octaves: 4,
    );
    final t = ((n + 1) * 0.5).clamp(0.0, 1.0);
    return _materialFromUnit(t);
  }

  LandscapeMaterial _materialFromUnit(double t) {
    for (var i = 0; i < _cdf.length; i++) {
      if (t <= _cdf[i]) return LandscapeMaterial.values[i];
    }
    return LandscapeMaterial.values.last;
  }

  Color colorAt(int wx, int wy) {
    final material = materialAt(wx, wy);
    final gradient = params.gradients[material]!;
    final t = _gaussianUnit(wx, wy, material.index);
    return gradient.sample(t);
  }

  /// Deterministic Gaussian sample in [0, 1], mean 0.5.
  double _gaussianUnit(int wx, int wy, int materialIndex) {
    final u1 = _hash01(params.seed, wx, wy, materialIndex, 1);
    final u2 = _hash01(params.seed, wx, wy, materialIndex, 2);
    final r = math.sqrt(-2.0 * math.log(u1.clamp(1e-12, 1.0)));
    final theta = 2.0 * math.pi * u2;
    final z = r * math.cos(theta);
    final sigma = params.colorSigma.clamp(0.01, 1.0);
    return (0.5 + z * sigma).clamp(0.0, 1.0);
  }

  /// High-quality 64-bit mix → unit float. Safe for large |wx|,|wy|.
  static double _hash01(int seed, int x, int y, int a, int b) {
    var h = seed ^ 0x9E3779B97F4A7C15;
    h = _mix64(h ^ x);
    h = _mix64(h ^ y);
    h = _mix64(h ^ a);
    h = _mix64(h ^ b);
    // Unsigned top 53 bits → [0, 1)
    return (h >>> 11) * (1.0 / 9007199254740992.0);
  }

  static int _mix64(int z) {
    z &= 0xFFFFFFFFFFFFFFFF;
    z = (z ^ (z >>> 30)) * 0xBF58476D1CE4E5B9;
    z &= 0xFFFFFFFFFFFFFFFF;
    z = (z ^ (z >>> 27)) * 0x94D049BB133111EB;
    z &= 0xFFFFFFFFFFFFFFFF;
    return z ^ (z >>> 31);
  }

  /// Bake the full grid to an RGBA atlas, optionally nearest-upscaled.
  Future<ui.Image> bakeAtlas() async {
    final p = params.clamped();
    final side = p.worldPixelsSide;
    final sharp = p.sharpness;
    // Reuse this generator when params already match the clamped set.
    final gen = identical(p, params) ||
            (p.seed == params.seed &&
                p.tilesSide == params.tilesSide &&
                p.pixelsPerTile == params.pixelsPerTile &&
                p.sharpness == params.sharpness &&
                p.colorSigma == params.colorSigma &&
                p.noiseFrequency == params.noiseFrequency)
        ? this
        : LandscapeGenerator(p);
    final base = Uint32List(side * side);

    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        base[y * side + x] = _packRgba(gen.colorAt(x, y));
      }
    }

    late final Uint32List pixels;
    late final int edge;
    if (sharp <= 1) {
      pixels = base;
      edge = side;
    } else {
      edge = side * sharp;
      pixels = Uint32List(edge * edge);
      for (var y = 0; y < edge; y++) {
        final sy = y ~/ sharp;
        for (var x = 0; x < edge; x++) {
          final sx = x ~/ sharp;
          pixels[y * edge + x] = base[sy * side + sx];
        }
      }
    }

    final bytes = Uint8List.view(pixels.buffer);
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
      bytes,
      edge,
      edge,
      ui.PixelFormat.rgba8888,
      completer.complete,
    );
    return completer.future;
  }
}

/// Pack Color into little-endian RGBA for [ui.PixelFormat.rgba8888].
int _packRgba(Color color) {
  final r = (color.r * 255.0).round() & 0xff;
  final g = (color.g * 255.0).round() & 0xff;
  final b = (color.b * 255.0).round() & 0xff;
  final a = (color.a * 255.0).round() & 0xff;
  return r | (g << 8) | (b << 16) | (a << 24);
}
