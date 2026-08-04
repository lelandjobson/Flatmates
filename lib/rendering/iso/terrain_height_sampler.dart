import 'perlin_noise.dart';

/// Produces deterministic, spatially coherent terrain elevation values
/// using fractal Perlin noise.
///
/// API mirrors [MagneticFieldSampler]: O(1) per sample, infinite extent,
/// fully deterministic from [seed].
class TerrainHeightSampler {
  TerrainHeightSampler({
    int seed = 0,
    this.frequency = 0.04,
    this.octaves = 4,
  }) : _noise = PerlinNoise(seed: seed);

  final PerlinNoise _noise;

  /// Controls spatial scale of the noise. Lower values produce larger,
  /// rolling hills; higher values produce more rugged terrain.
  /// At 0.04, one "hill" spans roughly 25 tiles.
  final double frequency;

  /// Number of fBm octaves. More octaves add finer detail.
  final int octaves;

  /// Sample terrain elevation at tile ([tileX], [tileY]).
  ///
  /// Returns a value in [0, 1] where 0 is the lowest point and 1 is the
  /// highest. The result is deterministic for any given coordinate and seed.
  double sample(int tileX, int tileY) {
    final raw = _noise.fbm2(
      tileX * frequency,
      tileY * frequency,
      octaves: octaves,
    );
    // fbm2 returns roughly [-1, 1]; remap to [0, 1].
    return (raw + 1.0) * 0.5;
  }
}
