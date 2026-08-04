import 'package:flutter/material.dart';

/// Theme type for material rendering. Colors come from crafts.
/// Colors now come from crafts; this provides theme type and fallback.
enum MaterialThemeType { dark, light }

/// Provides fallback colors when crafts are not loaded.
/// Primary color source is CraftsTechProvider.materialIdToColor.
class MaterialTheme {
  MaterialTheme._({required this.type});

  final MaterialThemeType type;

  /// Default grey for empty/unknown materials
  static const Color fallbackGrey = Color(0xFF6B6B6B);

  /// Get fallback color for unknown material IDs
  Color colorForUnknown(String materialId) => fallbackGrey;

  static final MaterialTheme dark = MaterialTheme._(type: MaterialThemeType.dark);
  static final MaterialTheme light =
      MaterialTheme._(type: MaterialThemeType.light);

  static MaterialTheme fromType(MaterialThemeType type) {
    switch (type) {
      case MaterialThemeType.dark:
        return dark;
      case MaterialThemeType.light:
        return light;
    }
  }
}
