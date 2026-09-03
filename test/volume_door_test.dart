import 'package:flatmates/crafting/placed_paper.dart';
import 'package:flatmates/gameplay/graph/connection_graph.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_box_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume_door.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('door is 2 wide by 4 high, centered, on the floor', () {
    final box = BoxPrimitive();
    final door = volumeDoorForSide(box, VolumeSide.east)!;
    expect(door.width, 2);
    expect(door.height, 4);
    expect(door.originY, 0);
    expect(door.originU, 3);
    expect(door.containsFacePixel(3, 0), isTrue);
    expect(door.containsFacePixel(4, 3), isTrue);
    expect(door.containsFacePixel(2, 0), isFalse);
    expect(door.containsFacePixel(3, 4), isFalse);

    var n = 0;
    for (var v = 0; v < box.heightSubtiles; v++) {
      for (var u = 0; u < box.depthSubtiles; u++) {
        if (door.containsFacePixel(u, v)) n++;
      }
    }
    expect(n, 8);
  });

  test('joined mass mesh omits the shared wall', () {
    final geom = volumeBoxGeometry(
      min: Vector3(0, 0, 0),
      max: Vector3(8, 6, 8),
      id: 'v',
      omitHandles: {VolumeHandle.posX},
    );
    expect(geom.faces, hasLength(5));
  });

  test('door clamps to a minimum-size face', () {
    final box = BoxPrimitive(
      widthSubtiles: 4,
      depthSubtiles: 4,
      heightSubtiles: 4,
    );
    final door = volumeDoorForSide(box, VolumeSide.south)!;
    expect(door.width, 2);
    expect(door.height, 4);
    expect(door.originU, 1);
    expect(door.originY, 0);
  });

  test('door world corners sit on the accessible face', () {
    const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
    final box = BoxPrimitive();
    final door = volumeDoorForSide(box, VolumeSide.north)!;
    final corners = doorWorldCorners(
      grid: grid,
      tx: 0,
      ty: 0,
      box: box,
      door: door,
    );
    expect(corners, hasLength(4));
    final min = box.worldMin(grid, 0, 0);
    for (final c in corners) {
      expect(c.z, closeTo(min.z, 1e-9));
    }
    expect(corners[0].y, closeTo(0, 1e-9));
    expect(corners[2].y, closeTo(4 * grid.subtileSize, 1e-9));
  });

  test('door paper is hidden when the camera is behind the volume', () {
    const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
    final box = BoxPrimitive();
    final door = volumeDoorForSide(box, VolumeSide.north)!;
    final corners = doorWorldCorners(
      grid: grid,
      tx: 0,
      ty: 0,
      box: box,
      door: door,
    );
    final min = box.worldMin(grid, 0, 0);
    final max = box.worldMax(grid, 0, 0);
    expect(
      doorFacesCamera(
        face: VolumeFace.negZ,
        corners: corners,
        cameraPosition: Vector3(min.x + 4, 4, min.z - 10),
      ),
      isTrue,
    );
    expect(
      doorFacesCamera(
        face: VolumeFace.negZ,
        corners: corners,
        cameraPosition: Vector3(min.x + 4, 4, max.z + 10),
      ),
      isFalse,
    );
  });

  test('shared interior sides do not get a door', () {
    final a = VolumeCell(
      tx: 1,
      ty: 1,
      box: BoxPrimitive(),
      accessibleSides: {VolumeSide.east},
    );
    final b = VolumeCell(
      tx: 2,
      ty: 1,
      box: BoxPrimitive(),
      accessibleSides: {VolumeSide.east},
    );
    final volume = Volume(id: 1, cells: [a, b]);
    expect(exteriorDoors(volume, a), isEmpty);
    expect(exteriorDoors(volume, b).single.side, VolumeSide.east);
  });

  test('holed volume mesh keeps the door opening as one face notch', () {
    final geom = volumeBoxGeometry(
      min: Vector3(0, 0, 0),
      max: Vector3(8, 6, 8),
      id: 'v',
      doors: [
        const VolumeDoor(
          side: VolumeSide.east,
          originU: 3,
          originY: 0,
          width: 2,
          height: 4,
        ),
      ],
      subtileSize: 1,
    );
    expect(geom.faces.length, 6);
    expect(geom.faces.where((f) => f.length > 4), hasLength(1));
  });

  test('door pixels stay paintable; applique sits on top', () {
    final store = FacePaintStore();
    final cell = VolumeCell(
      tx: 0,
      ty: 0,
      box: BoxPrimitive(),
      accessibleSides: {VolumeSide.east},
    );
    final canvas = store.canvasFor(
      volumeId: 1,
      cell: cell,
      face: VolumeFace.posX,
    );
    expect(canvas.isVoid(3, 0), isFalse);
    expect(canvas.paint(3, 0, PaperColor.pink), isTrue);
    expect(canvas.colorAt(3, 0), PaperColor.pink);
    expect(canvas.paint(0, 0, PaperColor.pink), isTrue);
  });

  test('door stamp is 2×4, sets access, and removal clears it', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    expect(
      volumes.placeDoor(
        volume: volume,
        cell: cell,
        side: VolumeSide.east,
        originU: 1,
      ),
      isTrue,
    );
    expect(cell.accessibleSides, {VolumeSide.east});
    expect(cell.doorOrigins[VolumeSide.east], 1);
    final door = volumeDoorForSide(
      cell.box,
      VolumeSide.east,
      originU: cell.doorOrigins[VolumeSide.east],
    )!;
    expect(door.width, kDoorWidthSubtiles);
    expect(door.height, kDoorHeightSubtiles);
    expect(door.originU, 1);
    expect(door.originY, 0);
    expect(door.containsFacePixel(1, 0), isTrue);
    expect(door.containsFacePixel(2, 3), isTrue);
    expect(door.containsFacePixel(0, 0), isFalse);

    expect(
      volumes.removeDoor(volume: volume, cell: cell, side: VolumeSide.east),
      isTrue,
    );
    expect(cell.accessibleSides, isEmpty);
    expect(cell.doorOrigins, isEmpty);
  });

  test('stamped door origin is used by mesh punch and connection graph', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    expect(
      volumes.placeDoor(
        volume: volume,
        cell: cell,
        side: VolumeSide.east,
        originU: 0,
      ),
      isTrue,
    );

    final paint = FacePaintStore();
    final canvas = paint.canvasFor(
      volumeId: volume.id,
      cell: cell,
      face: VolumeFace.posX,
    );
    expect(canvas.isVoid(0, 0), isFalse);
    expect(canvas.paint(0, 0, PaperColor.pink), isTrue);

    final geom = volumeBoxGeometry(
      min: Vector3(0, 0, 0),
      max: Vector3(8, 6, 8),
      id: 'v',
      doors: exteriorDoors(volume, cell).toList(),
      subtileSize: 1,
    );
    expect(geom.faces.where((f) => f.length > 4), hasLength(1));

    final graph = ConnectionGraph.build(volumes: volumes, paths: paths);
    expect(graph.edges.where((e) => e.kind == JointKind.inOut), hasLength(1));
  });
}
