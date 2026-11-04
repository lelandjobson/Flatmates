import 'dart:ui' as ui;
import 'package:vector_math/vector_math_64.dart';

/// Immutable repeating GPU texture. Pattern geometry is rasterized only once.
class SurfaceTexture {
  SurfaceTexture(this.image, {this.worldPeriod = 1 / 16})
    : shader = ui.ImageShader(
        image,
        ui.TileMode.repeated,
        ui.TileMode.repeated,
        (Matrix4.identity()..scaleByDouble(
              worldPeriod / image.width,
              worldPeriod / image.height,
              1,
              1,
            ))
            .storage,
      );
  final ui.Image image;
  final ui.ImageShader shader;
  final double worldPeriod;
  void dispose() {
    shader.dispose();
    image.dispose();
  }
}
