import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../rendering/iso/perlin_noise.dart';
import '../theme/world_theme.dart';
import 'landscape_grid.dart';
import 'landscape_material.dart';

/// Seeds a world-pixel landscape and bakes it to a sharp [ui.Image] atlas.
class LandscapeGenerator {
  LandscapeGenerator(this.params)
      : _noise = PerlinNoise(seed: params.seed),
        _terrainCdf = _cdfFor(kLandscapeTerrainFlow, params.weights),
        _forageCdf = _cdfFor(kLandscapeForage, params.weights),
        _forageShare = _groupShare(kLandscapeForage, params.weights) {
    final freq = params.noiseFrequency;
    _terrainThresholds = _probeQuantiles(
      cdf: _terrainCdf,
      ox: 0,
      oy: 0,
      freq: freq,
    );
    _forageThreshold = _probeShareThreshold(
      share: _forageShare,
      ox: 81.3,
      oy: -44.7,
      freq: freq * 2.15,
    );
    _foragePickThresholds = _probeQuantiles(
      cdf: _forageCdf,
      ox: 203.1,
      oy: 97.4,
      freq: freq * 1.35,
    );
  }

  final LandscapeGenParams params;
  final PerlinNoise _noise;
  final List<double> _terrainCdf;
  final List<double> _forageCdf;
  final double _forageShare;
  late final List<double> _terrainThresholds;
  late final double _forageThreshold;
  late final List<double> _foragePickThresholds;

  /// Weighted slice of [group]. Empty when every member weight is 0.
  static List<double> _cdfFor(
    List<LandscapeMaterial> group,
    Map<LandscapeMaterial, double> weights,
  ) {
    final raw = [
      for (final m in group) (weights[m] ?? 0).clamp(0.0, 1000.0),
    ];
    final sum = raw.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return const [];
    var acc = 0.0;
    return [
      for (final w in raw) acc += w / sum,
    ];
  }

  static double _groupShare(
    List<LandscapeMaterial> group,
    Map<LandscapeMaterial, double> weights,
  ) {
    var groupSum = 0.0;
    var total = 0.0;
    for (final m in LandscapeMaterial.values) {
      final w = (weights[m] ?? 0).clamp(0.0, 1000.0);
      total += w;
      if (group.contains(m)) groupSum += w;
    }
    if (total <= 0) return 0;
    return groupSum / total;
  }

  static const int _probeCount = 1024;

  List<double> _probeField({
    required double ox,
    required double oy,
    required double freq,
  }) {
    final samples = List<double>.filled(_probeCount, 0);
    for (var i = 0; i < _probeCount; i++) {
      final wx = (_hash01(params.seed, i, 1, 3, 5) * 4096).floor();
      final wy = (_hash01(params.seed, i, 7, 11, 13) * 4096).floor();
      samples[i] = _field(wx, wy, ox: ox, oy: oy, freq: freq);
    }
    samples.sort();
    return samples;
  }

  /// Raw-field cut points so each CDF bin matches its weight as coverage.
  List<double> _probeQuantiles({
    required List<double> cdf,
    required double ox,
    required double oy,
    required double freq,
  }) {
    if (cdf.isEmpty) return const [];
    final samples = _probeField(ox: ox, oy: oy, freq: freq);
    return [
      for (final t in cdf)
        samples[((t.clamp(0.0, 1.0)) * (_probeCount - 1)).round()],
    ];
  }

  double _probeShareThreshold({
    required double share,
    required double ox,
    required double oy,
    required double freq,
  }) {
    if (share <= 0) return double.infinity;
    final samples = _probeField(ox: ox, oy: oy, freq: freq);
    final t = (1.0 - share).clamp(0.0, 1.0);
    return samples[(t * (_probeCount - 1)).round()];
  }

  double _field(
    int wx,
    int wy, {
    required double ox,
    required double oy,
    required double freq,
  }) {
    final x = wx + ox;
    final y = wy + oy;
    final warpX = _noise.noise2(x * freq * 0.5, y * freq * 0.5) * 4.0;
    final warpY =
        _noise.noise2(x * freq * 0.5 + 17.3, y * freq * 0.5 - 9.1) * 4.0;
    return _noise.fbm2(
      (x + warpX) * freq,
      (y + warpY) * freq,
      octaves: 4,
    );
  }

  LandscapeMaterial? _pickAt(
    List<LandscapeMaterial> group,
    List<double> thresholds,
    double value,
  ) {
    if (thresholds.isEmpty) return null;
    for (var i = 0; i < thresholds.length; i++) {
      if (value <= thresholds[i]) return group[i];
    }
    return group.last;
  }

  LandscapeMaterial materialAt(int wx, int wy) {
    final freq = params.noiseFrequency;

    // Forage patches live on their own field so they don't steal the
    // water→dirt→grass→rock continuum.
    if (_forageCdf.isNotEmpty && _forageShare > 0) {
      final forage = _field(wx, wy, ox: 81.3, oy: -44.7, freq: freq * 2.15);
      if (forage > _forageThreshold) {
        final which = _field(wx, wy, ox: 203.1, oy: 97.4, freq: freq * 1.35);
        return _pickAt(kLandscapeForage, _foragePickThresholds, which)!;
      }
    }

    final ground = _field(wx, wy, ox: 0, oy: 0, freq: freq);
    return _pickAt(kLandscapeTerrainFlow, _terrainThresholds, ground) ??
        LandscapeMaterial.grass;
  }

  Color colorAt(int wx, int wy) {
    final material = materialAt(wx, wy);
    final gradient = params.gradients[material]!;
    final t = gaussianUnit(wx, wy, material.index);
    return gradient.sample(t);
  }

  /// Deterministic Gaussian sample in [0, 1], mean 0.5.
  double gaussianUnit(int wx, int wy, int materialIndex) {
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

  /// Procedural fill then atlas bake.
  Future<ui.Image> bakeAtlas({WorldTheme? theme}) async {
    final grid = LandscapeGrid.fromGenerator(this);
    return bakeAtlasFromGrid(grid, theme: theme);
  }

  /// Bake [grid] to an RGBA atlas (empty → theme background), with sharpness.
  Future<ui.Image> bakeAtlasFromGrid(
    LandscapeGrid grid, {
    WorldTheme? theme,
  }) async {
    final p = params.clamped();
    final side = grid.side;
    final sharp = p.sharpness;
    final base = Uint32List(side * side);

    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        base[y * side + x] = packRgba(grid.colorAt(x, y, p, theme: theme));
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
int packRgba(Color color) {
  final r = (color.r * 255.0).round() & 0xff;
  final g = (color.g * 255.0).round() & 0xff;
  final b = (color.b * 255.0).round() & 0xff;
  final a = (color.a * 255.0).round() & 0xff;
  return r | (g << 8) | (b << 16) | (a << 24);
}
