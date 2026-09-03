import 'package:flatmates/gameplay/friends/friend_instance_store.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/picking/map_selector.dart';
import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

void main() {
  late VolumeStore volumes;
  late FriendInstanceStore friends;
  late Camera camera;
  const viewport = Size(200, 200);
  const center = Offset(100, 100);

  setUp(() {
    volumes = VolumeStore();
    friends = FriendInstanceStore();
    expect(volumes.startNew(8, 8), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    // Look at the volume from above / +Z so the center ray hits a face.
    camera = Camera(
      name: 'selector-test',
      position: Vector3(4, 28, 22),
      target: Vector3(4, 3, 4),
      fovDegrees: 50,
    );
  });

  SelectableHit? pick(double distance) {
    return const MapSelector().pick(
      screen: center,
      viewport: viewport,
      camera: camera,
      distance: distance,
      volumes: volumes,
      friends: friends,
      regions: const [],
    );
  }

  test('close distance selects a volume face, not the mass', () {
    final hit = pick(40);
    expect(hit, isNotNull);
    expect(hit!.kind, SelectableKind.volumeFace);
    expect(hit.volumeId, volumes.volumes.single.id);
    expect(hit.face, isNotNull);
  });

  test('far distance selects the volume, not a face', () {
    final hit = pick(45);
    expect(hit, isNotNull);
    expect(hit!.kind, SelectableKind.volume);
    expect(hit.volumeId, volumes.volumes.single.id);
  });

  test('solid-scope distance still picks the volume mass', () {
    final hit = pick(62);
    expect(hit, isNotNull);
    expect(hit!.kind, SelectableKind.volume);
    expect(hit.volumeId, volumes.volumes.single.id);
    expect(hit.cell, isNotNull);
  });

  test('tool scope is face, then cell, then joined solid', () {
    expect(volumeToolScope(40), VolumeToolScope.face);
    expect(volumeToolScope(45), VolumeToolScope.cell);
    expect(volumeToolScope(61.9), VolumeToolScope.cell);
    expect(volumeToolScope(62), VolumeToolScope.solid);
    expect(volumeToolScope(80), VolumeToolScope.solid);
  });

  test('transform handles filter to the hovered cell only in mid zoom', () {
    VolumeCell? gizmoCell(double distance, VolumeCell cell) =>
        volumeToolScope(distance) == VolumeToolScope.cell ? cell : null;
    final cell = volumes.volumes.single.cells.single;
    expect(gizmoCell(40, cell), isNull);
    expect(gizmoCell(50, cell), same(cell));
    expect(gizmoCell(62, cell), isNull);
  });

  test('empty ground falls back to a tile', () {
    camera = Camera(
      name: 'empty',
      position: Vector3(-32, 30, -16),
      target: Vector3(-32, 0, -32),
      fovDegrees: 50,
    );
    final hit = const MapSelector().pick(
      screen: center,
      viewport: viewport,
      camera: camera,
      distance: 40,
      volumes: volumes,
      friends: friends,
      regions: const [],
    );
    expect(hit, isNotNull);
    expect(hit!.kind, SelectableKind.tile);
  });

  test('path tiles are preferred over regions', () {
    camera = Camera(
      name: 'path',
      position: Vector3(-32, 30, -16),
      target: Vector3(-32, 0, -32),
      fovDegrees: 50,
    );
    final ground = const MapSelector().pick(
      screen: center,
      viewport: viewport,
      camera: camera,
      distance: 40,
      volumes: volumes,
      friends: friends,
      regions: const [],
    );
    expect(ground, isNotNull);
    final tx = ground!.tx!;
    final ty = ground.ty!;
    final paths = PathStore(grid: volumes.grid)..addIsland(tx, ty);
    final hit = const MapSelector().pick(
      screen: center,
      viewport: viewport,
      camera: camera,
      distance: 40,
      volumes: volumes,
      friends: friends,
      regions: [WallRegion({(tx, ty)})],
      paths: paths,
    );
    expect(hit, isNotNull);
    expect(hit!.kind, SelectableKind.path);
    expect(hit.tx, tx);
    expect(hit.ty, ty);
  });
}
