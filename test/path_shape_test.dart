import 'package:flatmates/gameplay/paths/path_shape.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('zero mask is a centered 4x4 island', () {
    final pieces = pathFootprints(0);
    expect(pieces, hasLength(1));
    expect(
      pieces.single,
      const PathFootprint(
        originXSubtiles: 2,
        originZSubtiles: 2,
        widthSubtiles: 4,
        depthSubtiles: 4,
      ),
    );
  });

  test('opposite links are a straight through corridor', () {
    final mask = VolumeSide.east.maskBit | VolumeSide.west.maskBit;
    final pieces = pathFootprints(mask);
    expect(pieces, hasLength(3));
    expect(pieces[0].widthSubtiles, 4);
    expect(pieces.any((p) => p.originXSubtiles == 0 && p.widthSubtiles == 2), isTrue);
    expect(pieces.any((p) => p.originXSubtiles == 6 && p.widthSubtiles == 2), isTrue);
  });

  test('three links are a T', () {
    final mask = VolumeSide.north.maskBit |
        VolumeSide.east.maskBit |
        VolumeSide.south.maskBit;
    expect(pathFootprints(mask), hasLength(4));
  });

  test('four links are an X', () {
    final mask = VolumeSide.north.maskBit |
        VolumeSide.east.maskBit |
        VolumeSide.south.maskBit |
        VolumeSide.west.maskBit;
    expect(pathFootprints(mask), hasLength(5));
  });

  test('flush in_out door creates a path on the dest tile only', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);

    final byTile = pathFootprintsByTile(volumes: volumes, paths: paths);
    expect(byTile.containsKey((2, 2)), isFalse);
    expect(byTile[(3, 2)], isNotNull);
    final dest = byTile[(3, 2)]!;
    expect(
      dest,
      contains(
        const PathFootprint(
          originXSubtiles: 2,
          originZSubtiles: 2,
          widthSubtiles: 4,
          depthSubtiles: 4,
        ),
      ),
    );
    expect(
      dest,
      contains(
        const PathFootprint(
          originXSubtiles: 0,
          originZSubtiles: 2,
          widthSubtiles: 2,
          depthSubtiles: 4,
        ),
      ),
    );
  });

  test('inset in_out door adds a gap strip that does not enter the volume', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    volumes.draftCell!.box.widthSubtiles = 6;
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);

    final cell = volumes.volumes.single.cells.single;
    final gap = inOutGapFootprint(cell, VolumeSide.east);
    expect(
      gap,
      const PathFootprint(
        originXSubtiles: 6,
        originZSubtiles: 2,
        widthSubtiles: 2,
        depthSubtiles: 4,
      ),
    );
    expect(_overlapsBox(gap!, cell.box), isFalse);

    final byTile = pathFootprintsByTile(volumes: volumes, paths: paths);
    expect(byTile[(2, 2)], contains(gap));
    expect(byTile[(3, 2)], isNotNull);
  });

  test('preview place is an island, or joins to an existing neighbor', () {
    final paths = PathStore();
    expect(previewPlaceFootprints(paths, tx: 2, ty: 2), hasLength(1));
    expect(paths.addIsland(3, 2), isTrue);
    final preview = previewPlaceFootprints(paths, tx: 2, ty: 2);
    expect(preview.length, greaterThan(1));
    expect(preview.any((p) => p.originXSubtiles == 6), isTrue);
  });

  test('preview place draws join stubs on adjacent existing path tiles', () {
    final paths = PathStore();
    expect(previewPlaceFootprintsByTile(paths, tx: 2, ty: 2).keys, {(2, 2)});
    expect(paths.addIsland(3, 2), isTrue);
    final byTile = previewPlaceFootprintsByTile(paths, tx: 2, ty: 2);
    expect(byTile.keys, {(2, 2), (3, 2)});
    expect(byTile[(2, 2)]!.any((p) => p.originXSubtiles == 6), isTrue);
    expect(
      byTile[(3, 2)],
      [
        const PathFootprint(
          originXSubtiles: 0,
          originZSubtiles: 2,
          widthSubtiles: 2,
          depthSubtiles: 4,
        ),
      ],
    );
  });

  test('already-joined neighbors do not get a second hologram stub', () {
    final paths = PathStore()
      ..placeAndJoin(2, 2)
      ..placeAndJoin(3, 2);
    final byTile = previewPlaceFootprintsByTile(paths, tx: 2, ty: 2);
    expect(byTile.keys, {(2, 2)});
  });
}

bool _overlapsBox(PathFootprint p, BoxPrimitive box) {
  final ax1 = p.originXSubtiles + p.widthSubtiles;
  final az1 = p.originZSubtiles + p.depthSubtiles;
  final bx1 = box.originXSubtiles + box.widthSubtiles;
  final bz1 = box.originZSubtiles + box.depthSubtiles;
  return p.originXSubtiles < bx1 &&
      ax1 > box.originXSubtiles &&
      p.originZSubtiles < bz1 &&
      az1 > box.originZSubtiles;
}
