import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/viewers/coplanar_faces.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);

  WorldPlane planeOf(VolumeCell cell, VolumeFace face) =>
      WorldPlane.fromVolumeFace(grid: grid, cell: cell, face: face);

  Vector3 faceCenter(VolumeCell cell, VolumeFace face) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    return face.originAndNormal(min, max).$1;
  }

  test('joined bar shares one long-side plane', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final volumes = [
      Volume(id: 1, cells: [west]),
      Volume(id: 2, cells: [east]),
    ];
    final plane = planeOf(west, VolumeFace.posZ);
    final faces = collectCoplanarFaces(
      plane: plane,
      grid: grid,
      volumes: volumes,
    );
    expect(faces, hasLength(2));
    expect(
      faces.map((f) => (f.volumeId, f.cell.tx, f.face)).toSet(),
      {
        (1, 1, VolumeFace.posZ),
        (2, 2, VolumeFace.posZ),
      },
    );

    final eastHit = pickCoplanarFace(
      world: faceCenter(east, VolumeFace.posZ),
      plane: plane,
      grid: grid,
      volumes: volumes,
      faces: faces,
    );
    expect(eastHit, isNotNull);
    expect(eastHit!.volumeId, 2);
    expect(eastHit.face, VolumeFace.posZ);
  });

  test('C-mouth teeth are coplanar even with a gap', () {
    final top = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final bottom = VolumeCell(tx: 2, ty: 3, box: BoxPrimitive());
    final volumes = [
      Volume(id: 1, cells: [top]),
      Volume(id: 2, cells: [bottom]),
    ];
    final plane = planeOf(top, VolumeFace.posX);
    final faces = collectCoplanarFaces(
      plane: plane,
      grid: grid,
      volumes: volumes,
    );
    expect(faces, hasLength(2));

    final bottomHit = pickCoplanarFace(
      world: faceCenter(bottom, VolumeFace.posX),
      plane: plane,
      grid: grid,
      volumes: volumes,
      faces: faces,
    );
    expect(bottomHit, isNotNull);
    expect(bottomHit!.volumeId, 2);
    expect(bottomHit.cell.ty, 3);

    final gapMin = top.box.worldMax(grid, top.tx, top.ty);
    final gapMax = bottom.box.worldMin(grid, bottom.tx, bottom.ty);
    final gap = Vector3(gapMin.x, 3, (gapMin.z + gapMax.z) * 0.5);
    expect(
      pickCoplanarFace(
        world: gap,
        plane: plane,
        grid: grid,
        volumes: volumes,
        faces: faces,
      ),
      isNull,
    );
  });

  test('opposite or offset faces are not collected', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(
      tx: 2,
      ty: 1,
      box: BoxPrimitive(depthSubtiles: 4),
    );
    final volumes = [
      Volume(id: 1, cells: [west]),
      Volume(id: 2, cells: [east]),
    ];
    final plane = planeOf(west, VolumeFace.posZ);
    final faces = collectCoplanarFaces(
      plane: plane,
      grid: grid,
      volumes: volumes,
    );
    expect(faces, hasLength(1));
    expect(faces.single.volumeId, 1);

    expect(
      pickCoplanarFace(
        world: faceCenter(east, VolumeFace.posZ),
        plane: plane,
        grid: grid,
        volumes: volumes,
        faces: faces,
      ),
      isNull,
    );
    expect(
      pickCoplanarFace(
        world: faceCenter(west, VolumeFace.negZ),
        plane: plane,
        grid: grid,
        volumes: volumes,
        faces: faces,
      ),
      isNull,
    );
  });

  test('pixelAt maps a neighbor hit onto that neighbor canvas', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final volumes = [
      Volume(id: 1, cells: [west]),
      Volume(id: 2, cells: [east]),
    ];
    final plane = planeOf(west, VolumeFace.posZ);
    final world = faceCenter(east, VolumeFace.posZ);
    final hit = pickCoplanarFace(
      world: world,
      plane: plane,
      grid: grid,
      volumes: volumes,
    );
    expect(hit, isNotNull);
    final pixel = FacePaintStore.pixelAt(
      world: world,
      grid: grid,
      cell: hit!.cell,
      face: hit.face,
    );
    expect(pixel, isNotNull);
    expect(
      FacePaintStore.pixelAt(
        world: world,
        grid: grid,
        cell: west,
        face: VolumeFace.posZ,
      ),
      isNull,
    );
  });

  test('lattice walk from one bar face reaches the neighbor', () {
    final west = VolumeCell(tx: 1, ty: 1, box: BoxPrimitive());
    final east = VolumeCell(tx: 2, ty: 1, box: BoxPrimitive());
    final volumes = [
      Volume(id: 1, cells: [west]),
      Volume(id: 2, cells: [east]),
    ];
    final plane = planeOf(west, VolumeFace.posZ);
    final faces = collectCoplanarFaces(
      plane: plane,
      grid: grid,
      volumes: volumes,
    );
    final start = plane.latticeIndex(faceCenter(west, VolumeFace.posZ));
    final end = plane.latticeIndex(faceCenter(east, VolumeFace.posZ));
    final seen = <int>{};
    var x0 = start.$1;
    var y0 = start.$2;
    final x1 = end.$1;
    final y1 = end.$2;
    final dx = (x1 - x0).abs();
    final dy = (y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx - dy;
    while (true) {
      final world = plane.latticeCellCenter(x0, y0);
      final hit = pickCoplanarFace(
        world: world,
        plane: plane,
        grid: grid,
        volumes: volumes,
        faces: faces,
      );
      if (hit != null) seen.add(hit.volumeId);
      if (x0 == x1 && y0 == y1) break;
      final e2 = 2 * err;
      if (e2 > -dy) {
        err -= dy;
        x0 += sx;
      }
      if (e2 < dx) {
        err += dx;
        y0 += sy;
      }
    }
    expect(seen, {1, 2});
  });
}
