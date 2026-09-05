import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

/// Maps a ground color to an optional repeating paper texture.
///
/// Colors without an entry stay a flat atlas fill. Painted [PaperColor]s tint
/// [white]'s grain via a multiply pass until they get their own assets.
class ColorTextureCatalog {
  ColorTextureCatalog._();

  /// Off-white that matches [whiteAsset].
  static const Color white = Color(0xFFF3F1EC);

  static const String whiteAsset = 'assets/textures/paper/white.jpg';

  /// World units per one repeat of [whiteAsset].
  static const double whiteRepeatWorld = 2.0;

  static String? assetFor(Color color) =>
      color == white ? whiteAsset : null;

  static Future<ui.Image?> load(Color color) async {
    final path = assetFor(color);
    if (path == null) return null;
    try {
      final data = await rootBundle.load(path);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }
}
