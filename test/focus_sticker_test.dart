import 'package:flatmates/gameplay/picking/focus_sticker.dart';
import 'package:flatmates/gameplay/volumes/volume_door.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('wall focus offers a standard door sticker', () {
    final stickers = focusStickersFor(FocusWorkSurface.facade);
    expect(stickers, [kFocusDoorSticker]);
    expect(stickers.single.kind, FocusStickerKind.door);
    expect(DoorKind.values, [DoorKind.standard]);
  });

  test('floor focus offers room plan stickers', () {
    expect(
      focusStickersFor(FocusWorkSurface.floor).map((s) => s.kind),
      [FocusStickerKind.bedroom, FocusStickerKind.common],
    );
  });

  test('door origin is valid only when fully on the face', () {
    expect(
      doorOriginInBounds(originU: 0, faceWidth: 8, width: kDoorWidthSubtiles),
      isTrue,
    );
    expect(
      doorOriginInBounds(originU: 6, faceWidth: 8, width: kDoorWidthSubtiles),
      isTrue,
    );
    expect(
      doorOriginInBounds(originU: 7, faceWidth: 8, width: kDoorWidthSubtiles),
      isFalse,
    );
    expect(
      doorOriginInBounds(originU: -1, faceWidth: 8, width: kDoorWidthSubtiles),
      isFalse,
    );
  });
}
