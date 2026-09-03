import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_solid.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fill floods empty region and stops at drawn pixels', () {
    final canvas = FaceCanvas(width: 5, height: 5);
    canvas.paint(2, 0, PaperColor.yellow);
    canvas.paint(2, 1, PaperColor.yellow);
    canvas.paint(2, 2, PaperColor.yellow);
    canvas.paint(2, 3, PaperColor.yellow);
    canvas.paint(2, 4, PaperColor.yellow);

    expect(canvas.fill(0, 2, PaperColor.pink), isTrue);
    expect(canvas.colorAt(0, 2), PaperColor.pink);
    expect(canvas.colorAt(1, 4), PaperColor.pink);
    expect(canvas.colorAt(2, 2), PaperColor.yellow);
    expect(canvas.colorAt(4, 2), isNull);

    expect(canvas.fill(4, 2, PaperColor.green), isTrue);
    expect(canvas.colorAt(4, 2), PaperColor.green);
    expect(canvas.colorAt(3, 0), PaperColor.green);
    expect(canvas.colorAt(1, 0), PaperColor.pink);

    expect(canvas.fill(2, 2, PaperColor.green), isTrue);
    expect(canvas.colorAt(2, 2), PaperColor.green);
    expect(canvas.colorAt(2, 1), PaperColor.yellow);
  });

  test('pixelCorners wind so the geometric normal faces outward', () {
    const grid = VolumeGrid(tilesSide: 16, tileSize: 10);
    final cell = VolumeCell(tx: 1, ty: 2, box: BoxPrimitive());
    for (final face in VolumeFace.values) {
      final corners = FacePaintStore.pixelCorners(
        u: 1,
        v: 1,
        grid: grid,
        cell: cell,
        face: face,
      );
      final n = (corners[1] - corners[0]).cross(corners[2] - corners[0])
        ..normalize();
      expect(
        n.dot(face.worldNormal),
        greaterThan(0.9),
        reason: '$face winding points inward',
      );
    }
  });

  test('faceCorners wind so the geometric normal faces outward', () {
    const grid = VolumeGrid(tilesSide: 16, tileSize: 10);
    final cell = VolumeCell(tx: 1, ty: 2, box: BoxPrimitive());
    for (final face in VolumeFace.values) {
      final corners = FacePaintStore.faceCorners(
        grid: grid,
        cell: cell,
        face: face,
      );
      final n = (corners[1] - corners[0]).cross(corners[2] - corners[0])
        ..normalize();
      expect(
        n.dot(face.worldNormal),
        greaterThan(0.9),
        reason: '$face winding points inward',
      );
    }
  });

  test('fillFace paints remaining fragments and skips swallowed interior', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    final volume = volumes.volumes.single;
    final west = volume.cellAt(1, 1)!;
    final solid = resolveVolumeSolid(volume, volumes.grid);
    final store = FacePaintStore();

    expect(
      store.fillFace(
        volumeId: volume.id,
        cell: west,
        face: VolumeFace.posX,
        color: PaperColor.pink,
        solid: solid,
      ),
      isFalse,
    );
    expect(
      store.fillFace(
        volumeId: volume.id,
        cell: west,
        face: VolumeFace.negX,
        color: PaperColor.pink,
        solid: solid,
      ),
      isTrue,
    );

    expect(
      store.canvases[FacePaintKey(
        volumeId: volume.id,
        tx: 1,
        ty: 1,
        face: VolumeFace.posX,
      )]!.colorAt(0, 0),
      isNull,
    );
    expect(
      store.canvases[FacePaintKey(
        volumeId: volume.id,
        tx: 1,
        ty: 1,
        face: VolumeFace.negX,
      )]!.colorAt(0, 0),
      PaperColor.pink,
    );
  });

  test('fillCell paints one cell exteriors; fillSolid paints the joined mass', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    final volume = volumes.volumes.single;
    final west = volume.cellAt(1, 1)!;
    final east = volume.cellAt(2, 1)!;
    final solid = resolveVolumeSolid(volume, volumes.grid);
    final store = FacePaintStore();

    expect(
      store.fillCell(
        volumeId: volume.id,
        cell: west,
        color: PaperColor.yellow,
        solid: solid,
      ),
      isTrue,
    );
    expect(
      store.canvases[FacePaintKey(
        volumeId: volume.id,
        tx: 1,
        ty: 1,
        face: VolumeFace.negX,
      )]!.colorAt(0, 0),
      PaperColor.yellow,
    );
    expect(
      store.canvases[FacePaintKey(
        volumeId: volume.id,
        tx: 1,
        ty: 1,
        face: VolumeFace.posX,
      )]!.colorAt(0, 0),
      isNull,
    );
    expect(
      store.canvases.containsKey(
        FacePaintKey(
          volumeId: volume.id,
          tx: 2,
          ty: 1,
          face: VolumeFace.posX,
        ),
      ),
      isFalse,
    );

    expect(
      store.fillSolid(
        volume: volume,
        color: PaperColor.green,
        solid: solid,
      ),
      isTrue,
    );
    expect(
      store.canvases[FacePaintKey(
        volumeId: volume.id,
        tx: 2,
        ty: 1,
        face: VolumeFace.posX,
      )]!.colorAt(0, 0),
      PaperColor.green,
    );
    expect(
      store.canvases[FacePaintKey(
        volumeId: volume.id,
        tx: 2,
        ty: 1,
        face: VolumeFace.negX,
      )]!.colorAt(0, 0),
      isNull,
    );
    expect(east.tx, 2);
  });
}
