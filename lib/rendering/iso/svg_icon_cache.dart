import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../data/crafts_tech_provider.dart';

/// Cache of SVG and PNG icons loaded from crafts assets, keyed by material/craft ID.
/// Used for rendering material icons on tiles, blueprint overlays, and UI.
class SvgIconCache {
  SvgIconCache();

  final Map<String, PictureInfo> _pictureCache = {};
  final Map<String, ui.Image> _imageCache = {};
  bool _disposed = false;

  static final Paint _drawPaint = Paint();
  static final Paint _layerPaint = Paint();

  /// Returns cached PictureInfo for SVG, or null.
  PictureInfo? getPicture(String materialId) => _pictureCache[materialId];

  /// Returns cached ui.Image for PNG, or null.
  ui.Image? getImage(String materialId) => _imageCache[materialId];

  /// Returns true if we have either SVG or PNG cached for [materialId].
  bool hasIcon(String materialId) =>
      _pictureCache.containsKey(materialId) || _imageCache.containsKey(materialId);

  /// Attempts to load the icon for [materialId] using [provider].
  /// Tries SVG first, then PNG. Returns true if loaded.
  Future<bool> loadForMaterialId(
    String materialId,
    CraftsTechProvider provider,
  ) async {
    if (_disposed) return false;
    final thumbnailUrl = provider.materialIdToThumbnailUrl[materialId];
    if (thumbnailUrl == null) return false;
    final candidates = provider.resolveImagePathCandidates(thumbnailUrl);
    for (final path in candidates) {
      if (path.endsWith('.svg')) {
        if (await loadSvgFromAsset(materialId, path)) return true;
      } else {
        if (await loadPngFromAsset(materialId, path)) return true;
      }
    }
    return false;
  }

  /// Loads SVG from [assetPath] and caches under [materialId].
  Future<bool> loadSvgFromAsset(String materialId, String assetPath) async {
    if (_disposed) return false;
    try {
      await rootBundle.load(assetPath);
    } catch (_) {
      return false;
    }
    try {
      final info = await vg.loadPicture(
        SvgAssetLoader(assetPath),
        null,
      );
      if (_disposed) {
        info.picture.dispose();
        return false;
      }
      _pictureCache[materialId]?.picture.dispose();
      _pictureCache[materialId] = info;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Loads PNG from [assetPath] and caches under [materialId].
  Future<bool> loadPngFromAsset(String materialId, String assetPath) async {
    if (_disposed) return false;
    try {
      final data = await rootBundle.load(assetPath);
      final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
      final frame = await codec.getNextFrame();
      if (_disposed) {
        frame.image.dispose();
        return false;
      }
      _imageCache[materialId]?.dispose();
      _imageCache[materialId] = frame.image;
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Legacy: loads from single path (tries as SVG).
  Future<bool> loadFromAsset(String materialId, String assetPath) async {
    if (assetPath.endsWith('.svg')) {
      return loadSvgFromAsset(materialId, assetPath);
    }
    return loadPngFromAsset(materialId, assetPath);
  }

  /// Preloads icons for all material IDs that have thumbnail URLs in [provider].
  Future<void> loadFromProvider(CraftsTechProvider provider) async {
    for (final materialId in provider.materialIdToThumbnailUrl.keys) {
      await loadForMaterialId(materialId, provider);
    }
  }

  /// Draws the cached icon into [canvas] at [dst] with optional [alpha].
  /// Uses SVG if available, else PNG, else does nothing.
  void drawIcon(Canvas canvas, Rect dst, String materialId, {double alpha = 1.0}) {
    final pic = _pictureCache[materialId];
    if (pic != null) {
      canvas.save();
      if (alpha < 1.0) {
        _layerPaint.color = Color.fromRGBO(255, 255, 255, alpha);
        canvas.saveLayer(dst, _layerPaint);
      }
      canvas.translate(dst.left, dst.top);
      canvas.scale(
        dst.width / pic.size.width,
        dst.height / pic.size.height,
      );
      canvas.drawPicture(pic.picture);
      canvas.restore();
      if (alpha < 1.0) canvas.restore();
      return;
    }
    final img = _imageCache[materialId];
    if (img != null) {
      canvas.save();
      if (alpha < 1.0) {
        _layerPaint.color = Color.fromRGBO(255, 255, 255, alpha);
        canvas.saveLayer(dst, _layerPaint);
      }
      final src = Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble());
      canvas.drawImageRect(img, src, dst, _drawPaint);
      canvas.restore();
      if (alpha < 1.0) canvas.restore();
    }
  }

  /// Clears the cache and disposes all resources.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final info in _pictureCache.values) {
      info.picture.dispose();
    }
    _pictureCache.clear();
    for (final img in _imageCache.values) {
      img.dispose();
    }
    _imageCache.clear();
  }
}
