import 'dart:math' as math;

/// Classic 2D Perlin noise with seeded permutation table.
///
/// Produces smooth, deterministic noise in the range [-1, 1].
/// Infinite extent, O(1) per sample.
class PerlinNoise {
  PerlinNoise({int seed = 0}) {
    _initPermutation(seed);
  }

  late final List<int> _perm;

  static const int _tableSize = 256;
  static const int _tableMask = _tableSize - 1;

  // 12 gradient vectors uniformly distributed on the unit circle.
  static const List<(double, double)> _gradients = [
    (1, 0), (-1, 0), (0, 1), (0, -1),
    (0.7071, 0.7071), (-0.7071, 0.7071),
    (0.7071, -0.7071), (-0.7071, -0.7071),
    (0.9239, 0.3827), (-0.9239, 0.3827),
    (0.3827, 0.9239), (-0.3827, -0.9239),
  ];

  void _initPermutation(int seed) {
    final rng = math.Random(seed);
    final base = List<int>.generate(_tableSize, (i) => i);
    for (var i = _tableSize - 1; i > 0; i--) {
      final j = rng.nextInt(i + 1);
      final tmp = base[i];
      base[i] = base[j];
      base[j] = tmp;
    }
    // Double the table to avoid index wrapping.
    _perm = [...base, ...base];
  }

  /// Quintic fade curve: 6t^5 - 15t^4 + 10t^3
  static double _fade(double t) => t * t * t * (t * (t * 6 - 15) + 10);

  static double _lerp(double a, double b, double t) => a + t * (b - a);

  double _grad(int hash, double x, double y) {
    final g = _gradients[hash % _gradients.length];
    return g.$1 * x + g.$2 * y;
  }

  /// Sample 2D Perlin noise at ([x], [y]). Returns a value in ~[-1, 1].
  double noise2(double x, double y) {
    final xi = x.floor();
    final yi = y.floor();
    final xf = x - xi;
    final yf = y - yi;

    final ix = xi & _tableMask;
    final iy = yi & _tableMask;

    final aa = _perm[_perm[ix] + iy];
    final ab = _perm[_perm[ix] + iy + 1];
    final ba = _perm[_perm[ix + 1] + iy];
    final bb = _perm[_perm[ix + 1] + iy + 1];

    final u = _fade(xf);
    final v = _fade(yf);

    return _lerp(
      _lerp(_grad(aa, xf, yf), _grad(ba, xf - 1, yf), u),
      _lerp(_grad(ab, xf, yf - 1), _grad(bb, xf - 1, yf - 1), u),
      v,
    );
  }

  /// Fractal Brownian Motion — layered octaves for natural-looking terrain.
  ///
  /// [octaves] number of noise layers (more = more detail).
  /// [lacunarity] frequency multiplier per octave (typically 2.0).
  /// [persistence] amplitude multiplier per octave (typically 0.5).
  double fbm2(
    double x,
    double y, {
    int octaves = 4,
    double lacunarity = 2.0,
    double persistence = 0.5,
  }) {
    double value = 0;
    double amplitude = 1;
    double frequency = 1;
    double maxAmplitude = 0;

    for (var i = 0; i < octaves; i++) {
      value += amplitude * noise2(x * frequency, y * frequency);
      maxAmplitude += amplitude;
      amplitude *= persistence;
      frequency *= lacunarity;
    }

    return value / maxAmplitude;
  }
}
