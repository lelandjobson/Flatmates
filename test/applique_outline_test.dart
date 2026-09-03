import 'package:flatmates/gameplay/outlines/applique_outline.dart';
import 'package:flatmates/gameplay/outlines/outline_paint.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_applique.dart';
import 'package:flatmates/gameplay/volumes/volume_door.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('applique outline is thinner and lighter than world outlines', () {
    expect(kAppliqueOutlineStrokeWidth, lessThan(kWorldOutlineStrokeWidth));
    expect(kAppliqueOutlineColor.r, greaterThan(kWorldOutlineColor.r));
    expect(kAppliqueOutlineColor.g, greaterThan(kWorldOutlineColor.g));
    expect(kAppliqueOutlineColor.b, greaterThan(kWorldOutlineColor.b));
  });

  test('a camera-facing door applique has four outer edges', () {
    final (volumes, appliques, cell) = _southDoor();
    final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
    final midX = (min.x + max.x) * 0.5;
    final front = Vector3(midX, 4, max.z + 10);
    final edges = buildAppliqueOutline(
      appliques: appliques.items,
      volumes: volumes,
      camera: front,
    );
    expect(edges, hasLength(4));
  });

  test('applique outlines skip faces that do not look at the camera', () {
    final (volumes, appliques, cell) = _southDoor();
    final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
    final midX = (min.x + max.x) * 0.5;
    final behind = Vector3(midX, 4, min.z - 10);
    final edges = buildAppliqueOutline(
      appliques: appliques.items,
      volumes: volumes,
      camera: behind,
    );
    expect(edges, isEmpty);
  });

  test('applique outlines skip tiles that are not visible', () {
    final (volumes, appliques, cell) = _southDoor();
    final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
    final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
    final front = Vector3((min.x + max.x) * 0.5, 4, max.z + 10);
    final edges = buildAppliqueOutline(
      appliques: appliques.items,
      volumes: volumes,
      camera: front,
      tileVisible: (tx, ty) => false,
    );
    expect(edges, isEmpty);
  });
}

(VolumeStore, VolumeAppliqueStore, VolumeCell) _southDoor() {
  final volumes = VolumeStore();
  expect(volumes.startNew(2, 2), isTrue);
  expect(volumes.confirmEdit(), isTrue);
  final volume = volumes.volumes.single;
  final cell = volume.cells.single;
  final door = volumeDoorForSide(cell.box, VolumeSide.south)!;
  final appliques = VolumeAppliqueStore()
    ..placeOrMoveDoor(
      volume: volume,
      cell: cell,
      side: VolumeSide.south,
      door: door,
    );
  return (volumes, appliques, cell);
}
