import 'package:flutter/material.dart';

import '../../crafting/placed_paper.dart';
import '../volumes/volume_door.dart';

/// What the focused plane is editing.
enum FocusWorkSurface { facade, floor }

/// Palette item that drops onto the focused work surface.
enum FocusStickerKind { door }

/// Door catalog. More kinds will sit beside [standard] later.
enum DoorKind { standard }

class FocusStickerSpec {
  const FocusStickerSpec({
    required this.kind,
    required this.label,
    required this.icon,
    required this.swatch,
  });

  final FocusStickerKind kind;
  final String label;
  final IconData icon;
  final Color swatch;
}

const kFocusDoorSticker = FocusStickerSpec(
  kind: FocusStickerKind.door,
  label: 'Door',
  icon: Icons.door_front_door_outlined,
  swatch: Color(0xFF2ECC71),
);

/// Stickers offered for the current focus. Doors come from paths, not the palette.
List<FocusStickerSpec> focusStickersFor(FocusWorkSurface surface) {
  return switch (surface) {
    FocusWorkSurface.facade => const [],
    FocusWorkSurface.floor => const [],
  };
}

/// True when a 2-wide door at [originU] sits fully on a face of [faceWidth].
bool doorOriginInBounds({
  required int originU,
  required int faceWidth,
  int width = kDoorWidthSubtiles,
}) {
  return width > 0 && originU >= 0 && originU + width <= faceWidth;
}

/// Pink wash used when a loose piece sits outside the work surface.
const Color kFocusStickerInvalid = Color(0xFFFF80AB);

/// Paint-column accent taken from the active paper color.
Color focusPaintAccent(PaperColor color, Color Function(PaperColor)? resolve) =>
    resolve?.call(color) ?? color.color;
