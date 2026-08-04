import 'dart:math' as math;
import 'dart:ui' show Color, lerpDouble;

import 'foliage_provider.dart';

/// Configuration for a type of foliage to generate in clusters.
class FoliageTypeConfig {
  const FoliageTypeConfig({
    required this.typeId,
    required this.materialId,
    this.minScale = 0.7,
    this.maxScale = 1.3,
    this.colorLight = const Color(0xFF889677),
    this.colorDark = const Color(0xFF4C5F4D),
    this.gathersPerInstance = kDefaultFoliageGathers,
    this.averagePerTile = 3.0,
    this.minSpacing = 0.35,
  });

  final String typeId;
  final String materialId;
  final double minScale;
  final double maxScale;
  final Color colorLight;
  final Color colorDark;
  final int gathersPerInstance;

  /// Target number of foliage instances per tile at the cluster center.
  final double averagePerTile;

  /// Minimum distance between two foliage positions (in tile units).
  final double minSpacing;
}

/// Defines a single cluster of foliage to generate.
class ClusterSpec {
  const ClusterSpec({
    required this.centerX,
    required this.centerY,
    required this.radius,
    required this.config,
  });

  final double centerX;
  final double centerY;

  /// Cluster radius in tile units. Area covered ~ pi * radius^2.
  /// Max recommended ~4 (covers ~16 tiles).
  final double radius;

  final FoliageTypeConfig config;
}

/// Generates clusters of foliage instances using seeded randomness,
/// density falloff toward edges, and minimum-spacing rejection sampling.
///
/// Positions are emitted as tile + UV coordinates.
class FoliageClusterGenerator {
  FoliageClusterGenerator({required this.seed});

  final int seed;
  int _idCounter = 0;

  /// Generate foliage for a single cluster specification.
  List<FoliageInstance> generateCluster(ClusterSpec spec) {
    final rng = math.Random(
      seed ^ (spec.centerX * 73856093).toInt() ^ (spec.centerY * 19349663).toInt(),
    );

    final results = <FoliageInstance>[];
    // Track placed positions in world coordinates for spacing checks.
    final placed = <(double, double)>[];
    final minSpacingSq = spec.config.minSpacing * spec.config.minSpacing;

    final tileMinX = (spec.centerX - spec.radius).floor();
    final tileMaxX = (spec.centerX + spec.radius).ceil();
    final tileMinY = (spec.centerY - spec.radius).floor();
    final tileMaxY = (spec.centerY + spec.radius).ceil();

    for (var tx = tileMinX; tx <= tileMaxX; tx++) {
      for (var ty = tileMinY; ty <= tileMaxY; ty++) {
        final tileCenterX = tx + 0.5;
        final tileCenterY = ty + 0.5;
        final dx = tileCenterX - spec.centerX;
        final dy = tileCenterY - spec.centerY;
        final dist = math.sqrt(dx * dx + dy * dy);
        if (dist > spec.radius) continue;

        final falloff = 1.0 - (dist / spec.radius) * (dist / spec.radius);
        final targetCount = (spec.config.averagePerTile * falloff).round();
        if (targetCount <= 0) continue;

        for (var i = 0; i < targetCount; i++) {
          final instance = _tryPlaceInTile(
            rng, tx, ty, spec.config, placed, minSpacingSq,
          );
          if (instance != null) {
            results.add(instance);
            placed.add((instance.worldX, instance.worldY));
          }
        }
      }
    }

    return results;
  }

  /// Generate foliage for multiple clusters.
  List<FoliageInstance> generateClusters(List<ClusterSpec> specs) {
    final all = <FoliageInstance>[];
    for (final spec in specs) {
      all.addAll(generateCluster(spec));
    }
    return all;
  }

  /// Try to place one foliage instance within tile (tx, ty) using rejection
  /// sampling to enforce minimum spacing.  Emits tile + UV coordinates.
  FoliageInstance? _tryPlaceInTile(
    math.Random rng,
    int tx,
    int ty,
    FoliageTypeConfig config,
    List<(double, double)> existing,
    double minSpacingSq,
  ) {
    const maxAttempts = 12;
    const margin = 0.08;

    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      final u = margin + rng.nextDouble() * (1.0 - 2 * margin);
      final v = margin + rng.nextDouble() * (1.0 - 2 * margin);
      final px = tx + u;
      final py = ty + v;

      bool tooClose = false;
      for (final (ex, ey) in existing) {
        final ddx = px - ex;
        final ddy = py - ey;
        if (ddx * ddx + ddy * ddy < minSpacingSq) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;

      final t = rng.nextDouble();
      final scale = lerpDouble(config.minScale, config.maxScale, t)!;
      final facing = rng.nextDouble() * 360.0;
      final tint = Color.lerp(config.colorLight, config.colorDark, rng.nextDouble());

      return FoliageInstance(
        id: 'foliage_${_idCounter++}',
        typeId: config.typeId,
        materialId: config.materialId,
        tileX: tx,
        tileY: ty,
        u: u,
        v: v,
        remainingGathers: config.gathersPerInstance,
        maxGathers: config.gathersPerInstance,
        scale: scale,
        facingAngleDeg: facing,
        tint: tint,
      );
    }

    return null;
  }
}

/// Default tree foliage configuration.
const FoliageTypeConfig defaultTreeConfig = FoliageTypeConfig(
  typeId: 'type_tree',
  materialId: 'fm-logs',
);
