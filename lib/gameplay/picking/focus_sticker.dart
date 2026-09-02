import 'package:flutter/material.dart';

import '../../crafting/placed_paper.dart';
import '../volumes/volume_door.dart';
import '../volumes/volume_program.dart';

/// What the focused plane is editing.
enum FocusWorkSurface { facade, floor }

/// Palette item that drops onto the focused work surface.
enum FocusStickerKind { door, bedroom, common }

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
  swatch: Color(0xFFF7F7F2),
);

const kFocusBedroomSticker = FocusStickerSpec(
  kind: FocusStickerKind.bedroom,
  label: 'Bedroom',
  icon: Icons.bed_outlined,
  swatch: Color(0xFFFFF2F4),
);

const kFocusCommonSticker = FocusStickerSpec(
  kind: FocusStickerKind.common,
  label: 'Common',
  icon: Icons.weekend_outlined,
  swatch: Color(0xFFF2F6FF),
);

/// Stickers offered for the current focus. Wall faces get doors; floors get rooms.
List<FocusStickerSpec> focusStickersFor(FocusWorkSurface surface) {
  return switch (surface) {
    FocusWorkSurface.facade => const [kFocusDoorSticker],
    FocusWorkSurface.floor => const [kFocusBedroomSticker, kFocusCommonSticker],
  };
}

VolumeProgramKind? programKindForSticker(FocusStickerKind kind) =>
    switch (kind) {
      FocusStickerKind.bedroom => VolumeProgramKind.bedroom,
      FocusStickerKind.common => VolumeProgramKind.common,
      FocusStickerKind.door => null,
    };

FocusStickerKind stickerKindForProgram(VolumeProgramKind kind) =>
    switch (kind) {
      VolumeProgramKind.bedroom => FocusStickerKind.bedroom,
      VolumeProgramKind.common => FocusStickerKind.common,
    };

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
