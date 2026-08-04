import 'package:flutter/painting.dart';

import 'hatch_pattern.dart';
import 'hatch_patterns.dart';

/// Deterministically maps material IDs to [HatchPattern] types and derives
/// accent-coloured strokes from the tile's base colour.
///
/// The mapping is hash-based: each material ID always resolves to the same
/// pattern type, but the stroke colour adapts to the tile colour so the
/// overlay harmonises visually.
abstract final class MaterialHatchRegistry {
  /// Semi-transparent lighter accent derived from [base] for hatch strokes.
  ///
  /// Bumps lightness and saturation slightly, then applies 15 % alpha so the
  /// hatch lines are visible but don't overpower the underlying tile colour.
  static Color accentColorOf(Color base) {
    final hsl = HSLColor.fromColor(base);
    return hsl
        .withSaturation((hsl.saturation + 0.15).clamp(0.0, 1.0))
        .withLightness((hsl.lightness + 0.20).clamp(0.15, 0.95))
        .toColor()
        .withValues(alpha: 0.15);
  }

  // The 10 available pattern factories, referenced by index.
  static const _patternCount = 10;

  /// Build a [HatchPattern] for [materialId] using [tileColor] as the basis
  /// for the stroke colour.
  static HatchPattern patternForMaterial(
    String materialId,
    Color tileColor, {
    double strokeMultiplier = 1.0,
  }) {
    final color = accentColorOf(tileColor);
    final index = materialId.hashCode.abs() % _patternCount;
    return _buildPattern(index, color, strokeMultiplier: strokeMultiplier);
  }

  /// Convenience: build patterns for every entry in [materialIdToColor].
  ///
  /// Returns a map of materialId → [HatchPattern].  Each pattern must still
  /// be [HatchRenderer.prepare]d before use.
  static Map<String, HatchPattern> buildAll(
    Map<String, Color> materialIdToColor, {
    double strokeMultiplier = 1.0,
  }) {
    final result = <String, HatchPattern>{};
    for (final entry in materialIdToColor.entries) {
      result[entry.key] = patternForMaterial(
        entry.key,
        entry.value,
        strokeMultiplier: strokeMultiplier,
      );
    }
    return result;
  }

  static HatchPattern _buildPattern(
    int index,
    Color color, {
    double strokeMultiplier = 1.0,
  }) {
    final double sm = strokeMultiplier;
    switch (index) {
      case 0:
        return HatchPatterns.diagonalLines(
          spacing: 6, strokeWidth: 0.8 * sm, color: color,
        );
      case 1:
        return HatchPatterns.crosshatch(
          spacing: 7, strokeWidth: 0.7 * sm, color: color,
        );
      case 2:
        return HatchPatterns.horizontalLines(
          spacing: 5, strokeWidth: 0.8 * sm, color: color,
        );
      case 3:
        return HatchPatterns.dots(
          spacing: 6, radius: 1.0 * sm, color: color,
        );
      case 4:
        return HatchPatterns.grid(
          spacing: 7, strokeWidth: 0.7 * sm, color: color,
        );
      case 5:
        return HatchPatterns.dashedHorizontal(
          spacing: 6, strokeWidth: 0.7 * sm, color: color,
        );
      case 6:
        return HatchPatterns.brick(
          width: 10, height: 5, strokeWidth: 0.7 * sm, color: color,
        );
      case 7:
        return HatchPatterns.stipple(
          spacing: 8, dotRadius: 0.7 * sm, color: color,
        );
      case 8:
        return HatchPatterns.spruce(
          scale: 1.0, strokeWidth: 0.7 * sm, color: color,
        );
      case 9:
        return HatchPatterns.vegetation(
          scale: 1.0, strokeWidth: 0.5 * sm, color: color,
        );
      default:
        return HatchPatterns.diagonalLines(
          spacing: 6, strokeWidth: 0.8 * sm, color: color,
        );
    }
  }
}
