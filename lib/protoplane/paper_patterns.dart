import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/widgets.dart';
import '../rendering/scene/surface_texture.dart';
import 'materials.dart';

/// Small immutable application-wide swatch atlas and repeating GPU tiles.
/// These shared assets are independent of world saves and never rebake on pan.
class PaperPatternAtlas {
  PaperPatternAtlas._();
  static final shared = PaperPatternAtlas._();
  static const pixels = 32;
  final Map<PaperMaterial, SurfaceTexture> _textures = {};
  ui.Image? _atlas;
  void dispose() {
    _atlas?.dispose();
    _atlas = null;
    for (final texture in _textures.values) {
      texture.dispose();
    }
    _textures.clear();
  }

  SurfaceTexture texture(
    PaperMaterial material,
  ) => _textures.putIfAbsent(material, () {
    final recorder = ui.PictureRecorder();
    // Each tile uses a dedicated recorder; the atlas reuses these baked images.
    final tile = Canvas(recorder);
    tile.drawRect(
      const Rect.fromLTWH(0, 0, 32, 32),
      Paint()..color = material.base,
    );
    final ink = Paint()
      ..color = material.ink
      ..isAntiAlias = true;
    if (material.pattern == PaperPattern.dots) {
      tile.drawCircle(
        const Offset(16, 16),
        pixels * math.sqrt(.20 / math.pi),
        ink,
      );
    } else if (material.pattern == PaperPattern.diagonalLines) {
      ink.strokeWidth = pixels * .25 / math.sqrt2;
      for (var c = -64; c <= 96; c += pixels) {
        tile.drawLine(Offset(-32, c + 32.0), Offset(64, c - 64.0), ink);
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(pixels, pixels);
    picture.dispose();
    return SurfaceTexture(image);
  });
  ui.Image get image {
    if (_atlas != null) return _atlas!;
    final recorder = ui.PictureRecorder();
    final atlasCanvas = Canvas(recorder);
    for (final material in PaperMaterial.values) {
      atlasCanvas.drawImage(
        texture(material).image,
        Offset(material.index * pixels.toDouble(), 0),
        Paint(),
      );
    }
    final picture = recorder.endRecording();
    _atlas = picture.toImageSync(pixels * PaperMaterial.values.length, pixels);
    picture.dispose();
    return _atlas!;
  }

  Rect source(PaperMaterial material) => Rect.fromLTWH(
    material.index * pixels.toDouble(),
    0,
    pixels.toDouble(),
    pixels.toDouble(),
  );
}

class PaperSwatch extends StatelessWidget {
  const PaperSwatch({super.key, required this.material});
  final PaperMaterial material;
  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _SwatchPainter(material));
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.material);
  final PaperMaterial material;
  @override
  void paint(Canvas canvas, Size size) {
    final atlas = PaperPatternAtlas.shared;
    if (material.patterned) {
      canvas.save();
      // An eight-pixel repeat keeps the inventory swatch legible at both sizes.
      canvas.scale(128);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width / 128, size.height / 128),
        Paint()..shader = atlas.texture(material).shader,
      );
      canvas.restore();
      return;
    }
    canvas.drawImageRect(
      atlas.image,
      atlas.source(material),
      Offset.zero & size,
      Paint()..filterQuality = FilterQuality.low,
    );
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.material != material;
}
