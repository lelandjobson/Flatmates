import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  VolumeStore storeWith(Volume volume) {
    final store = VolumeStore();
    store.volumes.add(volume);
    return store;
  }

  test('tryTranslate moves every cell of a merged volume', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 5, ty: 5, box: BoxPrimitive()),
        VolumeCell(tx: 6, ty: 5, box: BoxPrimitive()),
      ],
    );
    final store = storeWith(volume);

    expect(store.tryTranslate(volume, 1, 0), isTrue);
    expect(volume.cellAt(5, 5), isNull);
    expect(volume.cellAt(6, 5), isNotNull);
    expect(volume.cellAt(7, 5), isNotNull);
  });

  test('tryTranslate rejects another volume and path tiles', () {
    final moving = Volume(
      id: 1,
      cells: [VolumeCell(tx: 2, ty: 2, box: BoxPrimitive())],
    );
    final other = Volume(
      id: 2,
      cells: [VolumeCell(tx: 3, ty: 2, box: BoxPrimitive())],
    );
    final store = storeWith(moving);
    store.volumes.add(other);

    expect(store.tryTranslate(moving, 1, 0), isFalse);
    expect(moving.cellAt(2, 2), isNotNull);

    final paths = PathStore(grid: store.grid)..tiles.add((2, 3));
    expect(
      store.tryTranslate(moving, 0, 1, blocked: paths.contains),
      isFalse,
    );
    expect(moving.cellAt(2, 2), isNotNull);
  });

  test('tryTranslate remaps face paint keys', () {
    final volume = Volume(
      id: 1,
      cells: [VolumeCell(tx: 4, ty: 4, box: BoxPrimitive())],
    );
    final store = storeWith(volume);
    final paint = FacePaintStore();
    paint.canvasFor(
      volumeId: 1,
      cell: volume.cells.single,
      face: VolumeFace.posY,
    );
    expect(
      paint.canvases.keys.single,
      const FacePaintKey(
        volumeId: 1,
        tx: 4,
        ty: 4,
        face: VolumeFace.posY,
      ),
    );

    expect(store.tryTranslate(volume, 0, 2), isTrue);
    paint.remapVolumeTiles(1, 0, 2);
    expect(
      paint.canvases.keys.single,
      const FacePaintKey(
        volumeId: 1,
        tx: 4,
        ty: 6,
        face: VolumeFace.posY,
      ),
    );
    paint.prune(store);
    expect(paint.canvases, hasLength(1));
  });

  test('tryTranslate allows a volume to slide over its own tiles', () {
    final volume = Volume(
      id: 1,
      cells: [
        VolumeCell(tx: 5, ty: 5, box: BoxPrimitive()),
        VolumeCell(tx: 6, ty: 5, box: BoxPrimitive()),
      ],
    );
    final store = storeWith(volume);
    expect(store.tryTranslate(volume, 1, 0), isTrue);
    expect(volume.cells.map((c) => (c.tx, c.ty)), [(6, 5), (7, 5)]);
  });
}
