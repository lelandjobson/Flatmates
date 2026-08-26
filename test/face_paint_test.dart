import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
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
}
