import 'package:flatmates/gameplay/picking/focus_click.dart';
import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('focus radius is 10% of width, capped at 200', () {
    expect(focusClickRadius(1000), 100);
    expect(focusClickRadius(4000), kFocusClickRadiusMax);
    expect(focusClickRadius(800), 80);
  });

  test('center-screen clicks are inside the focus disc', () {
    const viewport = Size(1000, 800);
    expect(isFocusClick(const Offset(500, 400), viewport), isTrue);
    expect(isFocusClick(const Offset(590, 400), viewport), isTrue);
    expect(isFocusClick(const Offset(620, 400), viewport), isFalse);
    expect(isFocusClick(const Offset(50, 50), viewport), isFalse);
  });

  test('tiles cannot focus; created objects can', () {
    expect(canFocusHit(SelectableHit.tile(1, 1)), isFalse);
    expect(canFocusHit(SelectableHit.volume(2)), isTrue);
    expect(canFocusHit(SelectableHit.path(3, 4)), isTrue);
    expect(
      canFocusHit(
        SelectableHit.region(WallRegion({(1, 1)}), tx: 1, ty: 1),
      ),
      isTrue,
    );
    expect(
      canFocusHit(
        SelectableHit.volumeFace(
          2,
          face: VolumeFace.posY,
          cell: VolumeCell(tx: 1, ty: 1, box: BoxPrimitive()),
        ),
      ),
      isTrue,
    );
  });

  test('focus requires a center re-click or a double-tap', () {
    expect(
      shouldEnterFocus(
        alreadySelected: false,
        nearCenter: true,
        doubleTap: false,
        focusable: true,
      ),
      isFalse,
    );
    expect(
      shouldEnterFocus(
        alreadySelected: true,
        nearCenter: false,
        doubleTap: false,
        focusable: true,
      ),
      isFalse,
    );
    expect(
      shouldEnterFocus(
        alreadySelected: true,
        nearCenter: true,
        doubleTap: false,
        focusable: true,
      ),
      isTrue,
    );
    expect(
      shouldEnterFocus(
        alreadySelected: false,
        nearCenter: false,
        doubleTap: true,
        focusable: true,
      ),
      isTrue,
    );
    expect(
      shouldEnterFocus(
        alreadySelected: true,
        nearCenter: true,
        doubleTap: false,
        focusable: false,
      ),
      isFalse,
    );
  });
}
