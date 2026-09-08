import 'package:flatmates/gameplay/stuff/stuff_catalog.dart';
import 'package:flatmates/gameplay/stuff/stuff_hull.dart';
import 'package:flatmates/gameplay/stuff/stuff_instance.dart';
import 'package:flatmates/gameplay/stuff/stuff_store.dart';
import 'package:flatmates/gameplay/stuff/stuff_twist.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  test('bedroom lists bed, desk, and lamp; lamp is also leisure', () {
    expect(
      stuffForProgram(kProgramBedroom).map((s) => s.id),
      [kStuffBed, kStuffDesk, kStuffLamp],
    );
    expect(
      stuffForProgram(kProgramLeisure).map((s) => s.id),
      [kStuffLamp, kStuffChair],
    );
    expect(stuffById(kStuffLamp)!.programIds, [
      kProgramBedroom,
      kProgramLeisure,
    ]);
  });

  test('shelf is wall-only; floor specs sit on the floor', () {
    expect(stuffById(kStuffShelf)!.anchor, StuffAnchor.wall);
    expect(stuffById(kStuffBed)!.anchor, StuffAnchor.floor);
    expect(stuffFaceMatchesAnchor(VolumeFace.negY, StuffAnchor.floor), isTrue);
    expect(stuffFaceMatchesAnchor(VolumeFace.posX, StuffAnchor.floor), isFalse);
    expect(stuffFaceMatchesAnchor(VolumeFace.posX, StuffAnchor.wall), isTrue);
    expect(stuffFaceMatchesAnchor(VolumeFace.negY, StuffAnchor.wall), isFalse);
  });

  test('hull expands to pad and min; yaw is only around the plane normal', () {
    final item = StuffInstance(
      id: '1',
      specId: kStuffLamp,
      volumeId: 1,
      tx: 4,
      ty: 4,
      face: VolumeFace.negY,
      origin: Vector3(4, 0.06, 4),
    );
    final (min, max) = stuffSelectionHull(item);
    expect(max.x - min.x, greaterThanOrEqualTo(kStuffHullMin));
    expect(max.y - min.y, greaterThanOrEqualTo(kStuffHullMin));
    expect(max.z - min.z, greaterThanOrEqualTo(kStuffHullMin));
    expect(min.y, greaterThanOrEqualTo(item.origin.y));

    expect(stuffEuler(VolumeFace.negY, 1.25), Vector3(0, 1.25, 0));
    expect(stuffEuler(VolumeFace.negZ, 0.4), Vector3(0, 0, 0.4));
  });

  test('floor inset is valid; side-wall penetration is not; floor slab is ignored', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(4, 4), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
    final center = Vector3(
      (min.x + max.x) * 0.5,
      min.y + kStuffPlaneEpsilon,
      (min.z + max.z) * 0.5,
    );

    final inset = StuffInstance(
      id: '1',
      specId: kStuffLamp,
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      face: VolumeFace.negY,
      origin: center,
    );
    expect(stuffIsValid(inset, volumes), isTrue);

    final throughWall = StuffInstance(
      id: '2',
      specId: kStuffBed,
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      face: VolumeFace.negY,
      origin: Vector3(min.x + 0.08, center.y, center.z),
    );
    expect(stuffIsValid(throughWall, volumes), isFalse);

    final floorOverlap = StuffInstance(
      id: '3',
      specId: kStuffLamp,
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      face: VolumeFace.negY,
      origin: Vector3(center.x, min.y - 0.04, center.z),
    );
    expect(stuffIsValid(floorOverlap, volumes), isTrue);
  });

  test('activeInTiles skips invalid pieces', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(4, 4), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    final min = cell.box.worldMin(volumes.grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(volumes.grid, cell.tx, cell.ty);
    final store = StuffStore();
    store.add(
      StuffInstance(
        id: '1',
        specId: kStuffLamp,
        volumeId: volume.id,
        tx: cell.tx,
        ty: cell.ty,
        face: VolumeFace.negY,
        origin: Vector3(
          (min.x + max.x) * 0.5,
          min.y + kStuffPlaneEpsilon,
          (min.z + max.z) * 0.5,
        ),
      ),
    );
    store.add(
      StuffInstance(
        id: '2',
        specId: kStuffBed,
        volumeId: volume.id,
        tx: cell.tx,
        ty: cell.ty,
        face: VolumeFace.negY,
        origin: Vector3(min.x + 0.08, min.y + kStuffPlaneEpsilon, (min.z + max.z) * 0.5),
      ),
    );
    final tiles = [(cell.tx, cell.ty)];
    expect(store.inTiles(tiles), hasLength(2));
    expect(
      store.activeInTiles(tiles, (item) => stuffIsValid(item, volumes)),
      hasLength(1),
    );
    expect(
      store.activeInTiles(tiles, (item) => stuffIsValid(item, volumes)).single.id,
      '1',
    );
  });

  test('clockwise screen twist increases yaw when looking down at a floor', () {
    final camera = Camera(
      name: 'twist',
      position: Vector3(0, 12, 0.01),
      target: Vector3(0, 0, 0),
      fovDegrees: 50,
    );
    final twist = stuffScreenTwist(
      a0: const Offset(0, 0),
      b0: const Offset(20, 0),
      a1: const Offset(0, 0),
      b1: const Offset(0, 20),
    );
    expect(twist, greaterThan(0));
    expect(
      stuffYawDeltaFromScreenTwist(
        screenTwist: twist,
        planeNormal: VolumeFace.negY.worldNormal,
        camera: camera,
      ),
      greaterThan(0),
    );
  });
}
