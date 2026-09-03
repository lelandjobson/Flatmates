import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/paint/face_applique_atlas.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodeFaceCanvasRgba writes one pixel per painted cell', () {
    final canvas = FaceCanvas(width: 8, height: 8);
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        canvas.paint(x, y, PaperColor.pink);
      }
    }
    expect(canvas.paintedCount, 64);
    final rgba = encodeFaceCanvasRgba(canvas, paper: (c) => c.color);
    expect(rgba.length, 8 * 8 * 4);
    var painted = 0;
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 0) painted++;
    }
    expect(painted, 64);
  });

  testWidgets('8×8 fill bakes one atlas slot, not 64', (tester) async {
    final box = BoxPrimitive();
    final cell = VolumeCell(tx: 0, ty: 0, box: box);
    final store = FacePaintStore();
    final canvas = store.canvasFor(
      volumeId: 1,
      cell: cell,
      face: VolumeFace.posY,
    );
    for (var y = 0; y < canvas.height; y++) {
      for (var x = 0; x < canvas.width; x++) {
        canvas.paint(x, y, PaperColor.green);
      }
    }
    expect(canvas.paintedCount, 64);

    final atlas = FaceAppliqueAtlas();
    addTearDown(atlas.dispose);
    await tester.runAsync(() => atlas.syncFrom(store));

    expect(atlas.paintedSlotCount, 1);
    expect(
      atlas.slotFor(
        const FacePaintKey(
          volumeId: 1,
          tx: 0,
          ty: 0,
          face: VolumeFace.posY,
        ),
      ),
      isNotNull,
    );
  });

  testWidgets('empty face is evicted from the atlas', (tester) async {
    final cell = VolumeCell(tx: 0, ty: 0, box: BoxPrimitive());
    final store = FacePaintStore();
    final canvas = store.canvasFor(
      volumeId: 1,
      cell: cell,
      face: VolumeFace.posY,
    );
    canvas.paint(2, 2, PaperColor.yellow);
    final atlas = FaceAppliqueAtlas();
    addTearDown(atlas.dispose);
    await tester.runAsync(() => atlas.syncFrom(store));
    expect(atlas.paintedSlotCount, 1);

    canvas.erase(2, 2);
    await tester.runAsync(() => atlas.syncFrom(store));
    expect(atlas.paintedSlotCount, 0);
  });

  test('FaceAppliqueKey can later address a shared texture', () {
    const unique = FaceAppliqueKey.unique(
      FacePaintKey(volumeId: 1, tx: 0, ty: 0, face: VolumeFace.posY),
    );
    const shared = FaceAppliqueKey.shared('brick');
    expect(unique.isShared, isFalse);
    expect(shared.isShared, isTrue);
    expect(unique, isNot(shared));
  });
}
