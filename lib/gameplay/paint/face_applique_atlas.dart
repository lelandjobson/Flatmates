import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../crafting/placed_paper.dart';
import '../../theme/world_theme.dart';
import 'face_paint_store.dart';

/// Identifies an applique slot. Unique to one face today; a later shared
/// repeating texture can use [FaceAppliqueKey.shared] without rebaking keys.
@immutable
class FaceAppliqueKey {
  const FaceAppliqueKey.unique(this.face) : textureId = null;

  const FaceAppliqueKey.shared(this.textureId) : face = null;

  final FacePaintKey? face;
  final String? textureId;

  bool get isShared => textureId != null;

  @override
  bool operator ==(Object other) =>
      other is FaceAppliqueKey &&
      other.face == face &&
      other.textureId == textureId;

  @override
  int get hashCode => Object.hash(face, textureId);
}

/// Packed (or standalone) image for one [FaceAppliqueKey].
class AtlasSlot {
  AtlasSlot({
    required this.key,
    required this.image,
    this.srcRect,
  });

  final FaceAppliqueKey key;
  final ui.Image image;
  final Rect? srcRect;

  Rect get rect =>
      srcRect ??
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
}

/// RGBA bytes for a face canvas. Empty cells stay transparent so the volume
/// paper mesh shows through.
Uint8List encodeFaceCanvasRgba(
  FaceCanvas canvas, {
  required Color Function(PaperColor) paper,
}) {
  final out = Uint8List(canvas.width * canvas.height * 4);
  var i = 0;
  for (var y = 0; y < canvas.height; y++) {
    for (var x = 0; x < canvas.width; x++) {
      final color = canvas.colorAt(x, y);
      if (color == null) {
        i += 4;
        continue;
      }
      final argb = paper(color).toARGB32();
      out[i++] = (argb >> 16) & 0xff;
      out[i++] = (argb >> 8) & 0xff;
      out[i++] = argb & 0xff;
      out[i++] = (argb >> 24) & 0xff;
    }
  }
  return out;
}

Future<ui.Image> decodeRgbaImage(Uint8List bytes, int width, int height) {
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    completer.complete,
  );
  return completer.future;
}

/// Bakes [FaceCanvas] grids to one textured slot per painted face.
class FaceAppliqueAtlas extends ChangeNotifier {
  final Map<FaceAppliqueKey, AtlasSlot> _slots = {};
  final Map<FaceAppliqueKey, int> _fingerprints = {};

  List<AtlasSlot> get slots => List.unmodifiable(_slots.values);

  int get paintedSlotCount => _slots.length;

  AtlasSlot? slotFor(FacePaintKey face) =>
      _slots[FaceAppliqueKey.unique(face)];

  Future<void> syncFrom(
    FacePaintStore store, {
    WorldTheme? theme,
  }) async {
    Color paper(PaperColor id) => theme?.paper(id) ?? id.color;
    final keep = <FaceAppliqueKey>{};
    var changed = false;
    for (final entry in store.canvases.entries) {
      final key = FaceAppliqueKey.unique(entry.key);
      final canvas = entry.value;
      if (!canvas.hasPaint) {
        if (_evict(key)) changed = true;
        continue;
      }
      keep.add(key);
      final fingerprint = Object.hashAll(canvas.cells);
      if (_fingerprints[key] == fingerprint && _slots.containsKey(key)) {
        continue;
      }
      final image = await decodeRgbaImage(
        encodeFaceCanvasRgba(canvas, paper: paper),
        canvas.width,
        canvas.height,
      );
      _slots[key]?.image.dispose();
      _slots[key] = AtlasSlot(key: key, image: image);
      _fingerprints[key] = fingerprint;
      changed = true;
    }
    final stale = _slots.keys.where((k) => !keep.contains(k)).toList();
    for (final key in stale) {
      if (_evict(key)) changed = true;
    }
    if (changed) notifyListeners();
  }

  bool _evict(FaceAppliqueKey key) {
    final slot = _slots.remove(key);
    _fingerprints.remove(key);
    slot?.image.dispose();
    return slot != null;
  }

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.image.dispose();
    }
    _slots.clear();
    _fingerprints.clear();
    super.dispose();
  }
}
