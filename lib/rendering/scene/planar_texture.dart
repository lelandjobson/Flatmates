import 'dart:ui' as ui;
import 'package:vector_math/vector_math_64.dart';

/// Shared GPU image. Slots retain this handle when a dirty atlas replaces it.
class PlanarTextureAtlas {
  ui.Image? image;
  void replace(ui.Image next) {
    final old = image;
    image = next;
    old?.dispose();
  }

  void dispose() {
    image?.dispose();
    image = null;
  }
}

/// A sprite in a shared atlas, positioned on a world-space plane. Canvas applies
/// the camera homography, so the texture remains perspective-correct.
class PlanarTexture {
  PlanarTexture({
    required this.origin,
    required this.u,
    required this.v,
    required this.bounds,
    required this.source,
    required this.atlas,
  });
  final Vector3 origin, u, v;
  final ui.Rect bounds, source;
  final PlanarTextureAtlas atlas;
}
