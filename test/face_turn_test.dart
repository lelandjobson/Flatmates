import 'package:flatmates/gameplay/viewers/face_turn.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  final min = Vector3(0, 0, 0);
  final max = Vector3(4, 6, 8);

  /// Look along +X: screen x = z, screen y = -y (y-up).
  Offset? projectPosX(Vector3 w) => Offset(w.z, -w.y);

  /// Look along +Z: screen x = x, screen y = -y.
  Offset? projectPosZ(Vector3 w) => Offset(w.x, -w.y);

  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  WorldPlane planeOf(VolumeCell cell, VolumeFace face) =>
      WorldPlane.fromVolumeFace(grid: grid, cell: cell, face: face);

  test('point to segment pulls onto the finite edge', () {
    expect(
      distancePointToSegment2d(
        const Offset(5, 0),
        const Offset(0, 0),
        const Offset(10, 0),
      ),
      closeTo(0, 1e-9),
    );
    expect(
      distancePointToSegment2d(
        const Offset(5, 3),
        const Offset(0, 0),
        const Offset(10, 0),
      ),
      closeTo(3, 1e-9),
    );
    expect(
      distancePointToSegment2d(
        const Offset(12, 0),
        const Offset(0, 0),
        const Offset(10, 0),
      ),
      closeTo(2, 1e-9),
    );
  });

  test('panning off +X toward +Z selects the south face', () {
    final next = closestAdjacentVolumeFace(
      face: VolumeFace.posX,
      min: min,
      max: max,
      screenPoint: const Offset(20, -3),
      project: projectPosX,
    );
    expect(next, VolumeFace.posZ);
  });

  test('panning off +X toward -Z selects the north face', () {
    final next = closestAdjacentVolumeFace(
      face: VolumeFace.posX,
      min: min,
      max: max,
      screenPoint: const Offset(-20, -3),
      project: projectPosX,
    );
    expect(next, VolumeFace.negZ);
  });

  test('panning off +X toward +Y selects the top face', () {
    final next = closestAdjacentVolumeFace(
      face: VolumeFace.posX,
      min: min,
      max: max,
      screenPoint: const Offset(4, -20),
      project: projectPosX,
    );
    expect(next, VolumeFace.posY);
  });

  test('panning off +X toward -Y selects the bottom face', () {
    final next = closestAdjacentVolumeFace(
      face: VolumeFace.posX,
      min: min,
      max: max,
      screenPoint: const Offset(4, 20),
      project: projectPosX,
    );
    expect(next, VolumeFace.negY);
  });

  test('posX edges include every neighbor except -X', () {
    final adjacents = {
      for (final e in volumeFaceEdges(VolumeFace.posX, min, max)) e.adjacent,
    };
    expect(
      adjacents,
      {
        VolumeFace.posY,
        VolumeFace.negY,
        VolumeFace.posZ,
        VolumeFace.negZ,
      },
    );
  });

  test('touching neighbor south face is preferred over wrapping', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final volumes = [
      Volume(id: 1, cells: [west]),
      Volume(id: 2, cells: [east]),
    ];
    final wMax = west.box.worldMax(grid, west.tx, west.ty);
    final lookAt = Vector3(wMax.x + 0.5, 3, wMax.z);
    final next = nextPlane2dFaceTurn(
      volumeId: 1,
      cell: west,
      face: VolumeFace.posZ,
      lookAt: lookAt,
      screenCenter: Offset(wMax.x + 20, -3),
      project: projectPosZ,
      grid: grid,
      volumes: volumes,
      currentPlane: planeOf(west, VolumeFace.posZ),
    );
    expect(next, isNotNull);
    expect(next!.volumeId, 2);
    expect(next.face, VolumeFace.posZ);
    expect(next.coplanar, isTrue);
  });

  test('gapped neighbor in the row still pans to its face', () {
    final west = VolumeCell(
      tx: 1,
      ty: 1,
      box: BoxPrimitive(widthSubtiles: 4),
    );
    final east = VolumeCell(
      tx: 2,
      ty: 1,
      box: BoxPrimitive(originXSubtiles: 4, widthSubtiles: 4),
    );
    final volumes = [
      Volume(id: 1, cells: [west]),
      Volume(id: 2, cells: [east]),
    ];
    final wMax = west.box.worldMax(grid, west.tx, west.ty);
    final eMin = east.box.worldMin(grid, east.tx, east.ty);
    expect(eMin.x - wMax.x, greaterThan(1));
    final lookAt = Vector3(wMax.x + 0.5, 3, wMax.z);
    final next = nextPlane2dFaceTurn(
      volumeId: 1,
      cell: west,
      face: VolumeFace.posZ,
      lookAt: lookAt,
      screenCenter: Offset(wMax.x + 20, -3),
      project: projectPosZ,
      grid: grid,
      volumes: volumes,
      currentPlane: planeOf(west, VolumeFace.posZ),
    );
    expect(next, isNotNull);
    expect(next!.volumeId, 2);
    expect(next.cell.tx, 2);
    expect(next.face, VolumeFace.posZ);
    expect(next.coplanar, isTrue);
  });

  test('no neighbor still wraps around the current volume', () {
    final cell = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final wMax = cell.box.worldMax(grid, cell.tx, cell.ty);
    final next = nextPlane2dFaceTurn(
      volumeId: 1,
      cell: cell,
      face: VolumeFace.posZ,
      lookAt: Vector3(wMax.x + 4, 3, wMax.z),
      screenCenter: Offset(wMax.x + 20, -3),
      project: projectPosZ,
      grid: grid,
      volumes: [
        Volume(id: 1, cells: [cell]),
      ],
      currentPlane: planeOf(cell, VolumeFace.posZ),
    );
    expect(next, isNotNull);
    expect(next!.volumeId, 1);
    expect(next.face, VolumeFace.posX);
    expect(next.coplanar, isFalse);
  });

  test('panning up still wraps to the roof even with a neighbor', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final wMin = west.box.worldMin(grid, west.tx, west.ty);
    final wMax = west.box.worldMax(grid, west.tx, west.ty);
    final midX = (wMin.x + wMax.x) * 0.5;
    final next = nextPlane2dFaceTurn(
      volumeId: 1,
      cell: west,
      face: VolumeFace.posZ,
      lookAt: Vector3(midX, wMax.y + 4, wMax.z),
      screenCenter: Offset(midX, -40),
      project: projectPosZ,
      grid: grid,
      volumes: [
        Volume(id: 1, cells: [west]),
        Volume(id: 2, cells: [east]),
      ],
      currentPlane: planeOf(west, VolumeFace.posZ),
    );
    expect(next, isNotNull);
    expect(next!.volumeId, 1);
    expect(next.face, VolumeFace.posY);
    expect(next.coplanar, isFalse);
  });

  test('non-coplanar neighbor face asks for a camera reframe', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(
      tx: 2,
      ty: 1,
      box: BoxPrimitive(depthSubtiles: 4),
    );
    final wMax = west.box.worldMax(grid, west.tx, west.ty);
    final eMax = east.box.worldMax(grid, east.tx, east.ty);
    expect(eMax.z, isNot(closeTo(wMax.z, 1e-6)));
    final next = nextPlane2dFaceTurn(
      volumeId: 1,
      cell: west,
      face: VolumeFace.posZ,
      lookAt: Vector3(wMax.x + 4, 3, wMax.z),
      screenCenter: Offset(wMax.x + 20, -3),
      project: projectPosZ,
      grid: grid,
      volumes: [
        Volume(id: 1, cells: [west]),
        Volume(id: 2, cells: [east]),
      ],
      currentPlane: planeOf(west, VolumeFace.posZ),
    );
    expect(next, isNotNull);
    expect(next!.volumeId, 2);
    expect(next.face, VolumeFace.posZ);
    expect(next.coplanar, isFalse);
  });

  test('merged same-volume cells stay coplanar without wrapping', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final volume = Volume(id: 1, cells: [west, east]);
    final wMax = west.box.worldMax(grid, west.tx, west.ty);
    final next = nextPlane2dFaceTurn(
      volumeId: 1,
      cell: west,
      face: VolumeFace.posZ,
      lookAt: lookAtFor(wMax),
      screenCenter: Offset(wMax.x + 20, -3),
      project: projectPosZ,
      grid: grid,
      volumes: [volume],
      currentPlane: planeOf(west, VolumeFace.posZ),
    );
    expect(next, isNotNull);
    expect(next!.volumeId, 1);
    expect(next.cell.tx, 2);
    expect(next.face, VolumeFace.posZ);
    expect(next.coplanar, isTrue);
  });

  test('collinear overlapping segments share an edge', () {
    expect(
      segmentsShareEdge(
        Vector3(0, 0, 0),
        Vector3(0, 4, 0),
        Vector3(0, 1, 0),
        Vector3(0, 5, 0),
      ),
      isTrue,
    );
    expect(
      segmentsShareEdge(
        Vector3(0, 0, 0),
        Vector3(0, 4, 0),
        Vector3(1, 0, 0),
        Vector3(1, 4, 0),
      ),
      isFalse,
    );
  });
}

Vector3 lookAtFor(Vector3 wMax) => Vector3(wMax.x + 0.5, 3, wMax.z);
