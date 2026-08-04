import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../geometry/geometry_slicer.dart' show kSpriteGridSize;

/// A color theme that maps a [kSpriteGridSize]x[kSpriteGridSize] coordinate
/// grid to colors. Each cell at `[row][col]` gets a unique tint applied via
/// [IsoSpriteGrid.drawAllWithTheme].
class SpriteColorTheme {
  const SpriteColorTheme({
    required this.name,
    required this.icon,
    required this.previewColors,
    required this.buildGrid,
  });

  final String name;
  final IconData icon;

  /// 2-3 representative colors for the swatch preview.
  final List<Color> previewColors;

  /// Generates the full 5x5 color grid. Called lazily so we don't
  /// pre-allocate all 16 grids at startup.
  final List<List<Color>> Function() buildGrid;

  List<List<Color>> get colors => buildGrid();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<List<Color>> _gradientGrid(Color from, Color to,
    {bool diagonal = false}) {
  return List.generate(kSpriteGridSize, (r) {
    return List.generate(kSpriteGridSize, (c) {
      final t = diagonal
          ? (r + c) / ((kSpriteGridSize - 1) * 2)
          : r / (kSpriteGridSize - 1);
      return Color.lerp(from, to, t)!;
    });
  });
}

List<List<Color>> _checkerGrid(Color a, Color b) {
  return List.generate(kSpriteGridSize, (r) {
    return List.generate(kSpriteGridSize, (c) {
      return (r + c) % 2 == 0 ? a : b;
    });
  });
}

List<List<Color>> _noiseGrid(List<Color> palette, int seed) {
  final rng = math.Random(seed);
  return List.generate(kSpriteGridSize, (_) {
    return List.generate(kSpriteGridSize, (_) {
      return palette[rng.nextInt(palette.length)];
    });
  });
}

List<List<Color>> _ringGrid(List<Color> ring) {
  final center = kSpriteGridSize ~/ 2;
  final maxDist = center.toDouble();
  return List.generate(kSpriteGridSize, (r) {
    return List.generate(kSpriteGridSize, (c) {
      final dx = (c - center).abs();
      final dy = (r - center).abs();
      final dist = math.max(dx, dy).toDouble();
      final t = dist / maxDist;
      final idx = (t * (ring.length - 1)).round().clamp(0, ring.length - 1);
      return ring[idx];
    });
  });
}

List<List<Color>> _stripeGrid(List<Color> colors, {bool vertical = false}) {
  return List.generate(kSpriteGridSize, (r) {
    return List.generate(kSpriteGridSize, (c) {
      final idx = (vertical ? c : r) % colors.length;
      return colors[idx];
    });
  });
}

// ---------------------------------------------------------------------------
// The 16 built-in themes
// ---------------------------------------------------------------------------

final List<SpriteColorTheme> builtInColorThemes = [
  // --- Subtle / monochromatic ---
  SpriteColorTheme(
    name: 'Bone',
    icon: Icons.grain,
    previewColors: [const Color(0xFFF5F0E8), const Color(0xFFE8E0D0)],
    buildGrid: () => _gradientGrid(
      const Color(0xFFF5F0E8),
      const Color(0xFFE8E0D0),
    ),
  ),

  SpriteColorTheme(
    name: 'Fog',
    icon: Icons.cloud,
    previewColors: [const Color(0xFFE0E4EA), const Color(0xFFCCD2DC)],
    buildGrid: () => _gradientGrid(
      const Color(0xFFE0E4EA),
      const Color(0xFFCCD2DC),
      diagonal: true,
    ),
  ),

  SpriteColorTheme(
    name: 'Grass',
    icon: Icons.grass,
    previewColors: [const Color(0xFF8BC34A), const Color(0xFF689F38)],
    buildGrid: () => _noiseGrid([
      const Color(0xFF8BC34A),
      const Color(0xFF9CCC65),
      const Color(0xFF7CB342),
      const Color(0xFF689F38),
      const Color(0xFFA5D66F),
    ], 42),
  ),

  SpriteColorTheme(
    name: 'Sand',
    icon: Icons.landscape,
    previewColors: [const Color(0xFFF5DEB3), const Color(0xFFDEB887)],
    buildGrid: () => _noiseGrid([
      const Color(0xFFF5DEB3),
      const Color(0xFFEDD5A0),
      const Color(0xFFDEB887),
      const Color(0xFFD2B48C),
    ], 17),
  ),

  // --- Cool tones ---
  SpriteColorTheme(
    name: 'Ice',
    icon: Icons.ac_unit,
    previewColors: [const Color(0xFFE0F7FA), const Color(0xFF80DEEA)],
    buildGrid: () => _gradientGrid(
      const Color(0xFFE0F7FA),
      const Color(0xFF80DEEA),
    ),
  ),

  SpriteColorTheme(
    name: 'Ocean',
    icon: Icons.water,
    previewColors: [
      const Color(0xFF0077B6),
      const Color(0xFF00B4D8),
      const Color(0xFF90E0EF),
    ],
    buildGrid: () => _stripeGrid([
      const Color(0xFF0077B6),
      const Color(0xFF0096C7),
      const Color(0xFF00B4D8),
      const Color(0xFF48CAE4),
      const Color(0xFF90E0EF),
    ]),
  ),

  SpriteColorTheme(
    name: 'Slate',
    icon: Icons.rectangle,
    previewColors: [const Color(0xFF78909C), const Color(0xFF546E7A)],
    buildGrid: () => _checkerGrid(
      const Color(0xFF78909C),
      const Color(0xFF607D8B),
    ),
  ),

  // --- Warm tones ---
  SpriteColorTheme(
    name: 'Terracotta',
    icon: Icons.local_fire_department,
    previewColors: [const Color(0xFFE07A5F), const Color(0xFFC45B3E)],
    buildGrid: () => _noiseGrid([
      const Color(0xFFE07A5F),
      const Color(0xFFD4654A),
      const Color(0xFFC45B3E),
      const Color(0xFFE8886E),
    ], 88),
  ),

  SpriteColorTheme(
    name: 'Sunset',
    icon: Icons.wb_twilight,
    previewColors: [
      const Color(0xFFFF6B6B),
      const Color(0xFFFFAB76),
      const Color(0xFFFFE66D),
    ],
    buildGrid: () => _gradientGrid(
      const Color(0xFFFF6B6B),
      const Color(0xFFFFE66D),
    ),
  ),

  SpriteColorTheme(
    name: 'Autumn',
    icon: Icons.eco,
    previewColors: [
      const Color(0xFFD4A373),
      const Color(0xFFE07A5F),
      const Color(0xFF81B29A),
    ],
    buildGrid: () => _noiseGrid([
      const Color(0xFFD4A373),
      const Color(0xFFE07A5F),
      const Color(0xFF81B29A),
      const Color(0xFFF2CC8F),
      const Color(0xFF3D405B),
    ], 33),
  ),

  // --- Medium variance ---
  SpriteColorTheme(
    name: 'Candy',
    icon: Icons.cake,
    previewColors: [
      const Color(0xFFFF6B9D),
      const Color(0xFFC06CE8),
      const Color(0xFF6EB5FF),
    ],
    buildGrid: () => _ringGrid([
      const Color(0xFFFF6B9D),
      const Color(0xFFC06CE8),
      const Color(0xFF6EB5FF),
    ]),
  ),

  SpriteColorTheme(
    name: 'Mosaic',
    icon: Icons.grid_view,
    previewColors: [
      const Color(0xFF264653),
      const Color(0xFF2A9D8F),
      const Color(0xFFE9C46A),
    ],
    buildGrid: () => _checkerGrid(
      const Color(0xFF2A9D8F),
      const Color(0xFFE9C46A),
    ),
  ),

  SpriteColorTheme(
    name: 'Neon',
    icon: Icons.flash_on,
    previewColors: [
      const Color(0xFF00FF87),
      const Color(0xFF00E0FF),
      const Color(0xFFFF00E5),
    ],
    buildGrid: () => _stripeGrid([
      const Color(0xFF00FF87),
      const Color(0xFF00E0FF),
      const Color(0xFFFF00E5),
      const Color(0xFFFFE500),
      const Color(0xFF7B00FF),
    ], vertical: true),
  ),

  // --- High variance ---
  SpriteColorTheme(
    name: 'Potpourri',
    icon: Icons.local_florist,
    previewColors: [
      const Color(0xFFE8A0BF),
      const Color(0xFFBA68C8),
      const Color(0xFF7986CB),
      const Color(0xFF4DB6AC),
    ],
    buildGrid: () => _noiseGrid([
      const Color(0xFFE8A0BF),
      const Color(0xFFBA68C8),
      const Color(0xFF7986CB),
      const Color(0xFF4DB6AC),
      const Color(0xFFFFCC80),
      const Color(0xFFEF9A9A),
      const Color(0xFFA5D6A7),
      const Color(0xFF90CAF9),
    ], 77),
  ),

  SpriteColorTheme(
    name: 'Rainbow',
    icon: Icons.brightness_7,
    previewColors: [
      const Color(0xFFFF0000),
      const Color(0xFFFF8800),
      const Color(0xFFFFFF00),
      const Color(0xFF00CC00),
      const Color(0xFF0044FF),
    ],
    buildGrid: () {
      return List.generate(kSpriteGridSize, (r) {
        return List.generate(kSpriteGridSize, (c) {
          final t = (r + c) / ((kSpriteGridSize - 1) * 2);
          return spectralColorForTheme(t);
        });
      });
    },
  ),

  SpriteColorTheme(
    name: 'Prism',
    icon: Icons.auto_awesome,
    previewColors: [
      const Color(0xFFFF4081),
      const Color(0xFF7C4DFF),
      const Color(0xFF18FFFF),
      const Color(0xFF76FF03),
      const Color(0xFFFFD740),
    ],
    buildGrid: () => _noiseGrid([
      const Color(0xFFFF4081),
      const Color(0xFF7C4DFF),
      const Color(0xFF18FFFF),
      const Color(0xFF76FF03),
      const Color(0xFFFFD740),
      const Color(0xFFFF6E40),
      const Color(0xFFE040FB),
      const Color(0xFF40C4FF),
      const Color(0xFF69F0AE),
      const Color(0xFFFFFF00),
    ], 99),
  ),
];

/// Spectral color gradient (same algorithm as [IsoSpriteGrid.spectralColor]).
/// Duplicated here to avoid a circular import.
Color spectralColorForTheme(double t) {
  t = t.clamp(0.0, 1.0);
  if (t < 0.25) {
    return Color.lerp(
        const Color(0xFFFF0000), const Color(0xFFFF8800), t / 0.25)!;
  } else if (t < 0.5) {
    return Color.lerp(
        const Color(0xFFFF8800), const Color(0xFFFFFF00), (t - 0.25) / 0.25)!;
  } else if (t < 0.75) {
    return Color.lerp(
        const Color(0xFFFFFF00), const Color(0xFF00CC00), (t - 0.5) / 0.25)!;
  } else {
    return Color.lerp(
        const Color(0xFF00CC00), const Color(0xFF0044FF), (t - 0.75) / 0.25)!;
  }
}
