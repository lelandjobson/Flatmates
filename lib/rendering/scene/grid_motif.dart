import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Tileable ground-plane stamp. UVs are world XZ / [worldSize], so a swap of
/// [image] (or [worldSize]) changes the grid type without new path math.
class GridMotif {
  GridMotif({
    required this.id,
    required this.worldSize,
    required this.image,
  }) : assert(worldSize > 0);

  /// One world-lattice cell: +X and +Z edges only so repeats do not double up.
  factory GridMotif.subtileLines({
    required double worldSize,
    int pixels = 32,
    Color line = const Color(0x88FFFFFF),
  }) {
    return GridMotif(
      id: 'subtile_lines',
      worldSize: worldSize,
      image: rasterizeEdgeLines(pixels: pixels, line: line),
    );
  }

  final String id;
  final double worldSize;
  final ui.Image image;

  ui.ImageShader? _shader;

  /// Cached repeating shader. Valid until [dispose].
  ui.ImageShader get shader =>
      _shader ??= ui.ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        Matrix4.identity().storage,
      );

  static ui.Image rasterizeEdgeLines({
    int pixels = 32,
    Color line = const Color(0x88FFFFFF),
  }) {
    final size = pixels.clamp(4, 256);
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final paint = Paint()
      ..color = line
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none;
    final edge = size - 0.5;
    canvas.drawLine(Offset(edge, 0), Offset(edge, size.toDouble()), paint);
    canvas.drawLine(Offset(0, edge), Offset(size.toDouble(), edge), paint);
    final picture = recorder.endRecording();
    final image = picture.toImageSync(size, size);
    picture.dispose();
    return image;
  }

  /// Perspective-correct-enough ground cells: one quad per [worldSize] so the
  /// motif copies in a single later [drawVertices].
  static void projectCells({
    required double minX,
    required double maxX,
    required double minZ,
    required double maxZ,
    required double y,
    required double worldSize,
    required double imageWidth,
    required double imageHeight,
    required Offset? Function(double x, double y, double z) project,
    required List<Offset> positions,
    required List<Offset> texCoords,
  }) {
    if (worldSize <= 1e-8 || maxX - minX < 1e-8 || maxZ - minZ < 1e-8) {
      return;
    }
    final segsX = math.max(1, ((maxX - minX) / worldSize).ceil());
    final segsZ = math.max(1, ((maxZ - minZ) / worldSize).ceil());
    Offset tex(double x, double z) => Offset(
      (x / worldSize) * imageWidth,
      (z / worldSize) * imageHeight,
    );

    for (var jz = 0; jz < segsZ; jz++) {
      final z0 = minZ + (maxZ - minZ) * (jz / segsZ);
      final z1 = minZ + (maxZ - minZ) * ((jz + 1) / segsZ);
      for (var ix = 0; ix < segsX; ix++) {
        final x0 = minX + (maxX - minX) * (ix / segsX);
        final x1 = minX + (maxX - minX) * ((ix + 1) / segsX);
        final p00 = project(x0, y, z0);
        final p10 = project(x1, y, z0);
        final p11 = project(x1, y, z1);
        final p01 = project(x0, y, z1);
        if (p00 == null || p10 == null || p11 == null || p01 == null) {
          continue;
        }
        positions
          ..add(p00)
          ..add(p10)
          ..add(p11)
          ..add(p00)
          ..add(p11)
          ..add(p01);
        texCoords
          ..add(tex(x0, z0))
          ..add(tex(x1, z0))
          ..add(tex(x1, z1))
          ..add(tex(x0, z0))
          ..add(tex(x1, z1))
          ..add(tex(x0, z1));
      }
    }
  }

  void dispose() {
    _shader?.dispose();
    _shader = null;
    image.dispose();
  }
}
