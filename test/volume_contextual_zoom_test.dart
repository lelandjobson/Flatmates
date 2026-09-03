import 'dart:async';
import 'dart:math' as math;

import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_box_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume_ceiling_reveal.dart';
import 'package:flatmates/gameplay/volumes/volume_content_loader.dart';
import 'package:flatmates/gameplay/volumes/volume_solid.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedRandom implements math.Random {
  _FixedRandom(this._values);

  final List<double> _values;
  var _i = 0;

  @override
  double nextDouble() => _values[_i++ % _values.length];

  @override
  int nextInt(int max) => 0;

  @override
  bool nextBool() => false;
}

VolumeStore _joinedPair() {
  final volumes = VolumeStore();
  expect(volumes.paintAt(2, 2), isTrue);
  expect(volumes.paintAt(3, 2), isTrue);
  expect(volumes.volumes, hasLength(1));
  expect(volumes.volumes.single.cells, hasLength(2));
  return volumes;
}

void main() {
  test('reveal hysteresis opens below 28.5 and restores past 30', () {
    expect(
      volumeCeilingWantsReveal(distance: 28.4, currentlyRevealing: false),
      isTrue,
    );
    expect(
      volumeCeilingWantsReveal(distance: 28.5, currentlyRevealing: true),
      isTrue,
    );
    expect(
      volumeCeilingWantsReveal(distance: 28.5, currentlyRevealing: false),
      isFalse,
    );
    expect(
      volumeCeilingWantsReveal(distance: 31, currentlyRevealing: true),
      isFalse,
    );
  });

  test('adjacent parts are ordered by distance to the cursor', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.paintAt(2, 3), isTrue);
    expect(volumes.paintAt(3, 3), isTrue);
    final origin = VolumePartId(2, 2);
    final eastish = volumes.grid.tileCenter(2, 2)
      ..x += 3;
    final ordered = adjacentVolumeParts(
      volumes: volumes,
      origin: origin,
      cursor: eastish,
    );
    expect(ordered, [
      const VolumePartId(3, 2),
      const VolumePartId(2, 3),
      const VolumePartId(3, 3),
    ]);
  });

  test('loader starts the focused part and queues nearer neighbors first', () async {
    final started = <VolumePartId>[];
    final gates = <VolumePartId, Completer<void>>{};
    final loader = VolumeContentLoader(
      maxConcurrent: 1,
      loadPart: (part) async {
        started.add(part);
        await gates.putIfAbsent(part, Completer<void>.new).future;
      },
    );
    addTearDown(loader.dispose);
    const focus = VolumePartId(2, 2);
    const east = VolumePartId(3, 2);
    const south = VolumePartId(2, 3);
    loader.request(focus: focus, neighbors: const [east, south]);
    await Future<void>.delayed(Duration.zero);
    expect(started, [focus]);
    expect(loader.queued, [east, south]);
    gates[focus]!.complete();
    await Future<void>.delayed(Duration.zero);
    expect(loader.isLoaded(focus), isTrue);
    expect(started, [focus, east]);
    expect(loader.queued, [south]);
  });

  test('ceiling stays up until the focused part has loaded', () {
    final volumes = _joinedPair();
    final loader = VolumeContentLoader(loadPart: (_) async {});
    addTearDown(loader.dispose);
    final reveal = VolumeCeilingReveal(
      loader: loader,
      fadeDuration: Duration.zero,
    );
    addTearDown(reveal.dispose);
    final look = volumes.grid.tileCenter(2, 2);

    reveal.update(
      volumes: volumes,
      lookAt: look,
      distance: 18,
      enabled: true,
    );
    expect(reveal.wantsReveal, isTrue);
    expect(reveal.focus, const VolumePartId(2, 2));
    expect(reveal.opacityFor(const VolumePartId(2, 2)), 1);
    expect(reveal.opacityFor(const VolumePartId(3, 2)), 1);
  });

  test('loaded focus and adjacent parts lose their ceilings', () async {
    final volumes = _joinedPair();
    expect(volumes.paintAt(2, 3), isTrue);
    expect(volumes.paintAt(3, 3), isTrue);
    expect(volumes.paintAt(6, 6), isTrue);
    final loader = VolumeContentLoader(loadPart: (_) async {});
    addTearDown(loader.dispose);
    final reveal = VolumeCeilingReveal(
      loader: loader,
      fadeDuration: Duration.zero,
    );
    addTearDown(reveal.dispose);
    final look = volumes.grid.tileCenter(2, 2);

    reveal.update(
      volumes: volumes,
      lookAt: look,
      distance: 18,
      enabled: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(loader.isLoaded(const VolumePartId(2, 2)), isTrue);
    expect(loader.isLoaded(const VolumePartId(3, 2)), isTrue);
    expect(loader.isLoaded(const VolumePartId(2, 3)), isTrue);
    expect(loader.isLoaded(const VolumePartId(3, 3)), isTrue);
    expect(reveal.opacityFor(const VolumePartId(2, 2)), 0);
    expect(reveal.opacityFor(const VolumePartId(3, 2)), 0);
    expect(reveal.opacityFor(const VolumePartId(2, 3)), 0);
    expect(reveal.opacityFor(const VolumePartId(3, 3)), 0);
    expect(reveal.opacityFor(const VolumePartId(6, 6)), 1);

    reveal.update(
      volumes: volumes,
      lookAt: look,
      distance: 32,
      enabled: true,
    );
    expect(reveal.opacityFor(const VolumePartId(2, 2)), 1);
    expect(reveal.opacityFor(const VolumePartId(3, 2)), 1);
  });

  test('dummy load delay is a random wait up to 1.5 seconds', () {
    expect(
      dummyVolumeContentLoadDelay(_FixedRandom(const [0])),
      Duration.zero,
    );
    expect(
      dummyVolumeContentLoadDelay(_FixedRandom(const [1.0])),
      kDummyVolumeContentLoadMax,
    );
    expect(
      dummyVolumeContentLoadDelay(_FixedRandom(const [0.5])),
      const Duration(milliseconds: 750),
    );
  });

  test('syncVolumeMeshes fades only the requested part roof', () {
    final volumes = _joinedPair();
    final scene = Scene();
    addTearDown(scene.dispose);
    final volumeId = volumes.volumes.single.id;
    syncVolumeMeshes(
      scene,
      volumes,
      ceilingOpacityByPart: {const VolumePartId(2, 2): 0.4},
    );

    final focused = scene.meshById(volumeMeshId(volumeId, 2, 2))!;
    final neighbor = scene.meshById(volumeMeshId(volumeId, 3, 2))!;
    expect(focused.material.exactPerFaceColors, isTrue);
    expect(
      focused.material.perFaceColors!.any((c) => c.a < 1),
      isTrue,
    );
    expect(focused.material.perFaceColors, contains(kVolumeFloorColor));
    expect(neighbor.material.exactPerFaceColors, isFalse);
    expect(neighbor.material.perFaceColors, isNull);

    final cell = volumes.volumes.single.cellAt(2, 2)!;
    final floorY = cell.box.worldMin(volumes.grid, 2, 2).y;
    final roofY = cell.box.worldMax(volumes.grid, 2, 2).y;
    expect(volumeRoofFaceIndices(focused.geometry, roofY), isNotEmpty);
    expect(volumeFloorFaceIndices(focused.geometry, floorY), isNotEmpty);
    expect(volumeFloorFaceIndices(neighbor.geometry, floorY), isEmpty);

    syncVolumeMeshes(
      scene,
      volumes,
      ceilingOpacityByPart: {const VolumePartId(2, 2): 0},
    );
    final hidden = scene.meshById(volumeMeshId(volumeId, 2, 2))!;
    expect(volumeRoofFaceIndices(hidden.geometry, roofY), isEmpty);
    expect(volumeFloorFaceIndices(hidden.geometry, floorY), isNotEmpty);
    expect(
      volumeRoofFaceIndices(neighbor.geometry, roofY),
      isNotEmpty,
    );
    expect(volumeFloorFaceIndices(neighbor.geometry, floorY), isEmpty);
  });

  test('hidden ceilings hide roof handles and keep wall handles', () async {
    final volumes = _joinedPair();
    final loader = VolumeContentLoader(loadPart: (_) async {});
    addTearDown(loader.dispose);
    final reveal = VolumeCeilingReveal(
      loader: loader,
      fadeDuration: Duration.zero,
    );
    addTearDown(reveal.dispose);
    reveal.update(
      volumes: volumes,
      lookAt: volumes.grid.tileCenter(2, 2),
      distance: 18,
      enabled: true,
    );
    await Future<void>.delayed(Duration.zero);
    expect(reveal.hidesHandle(2, 2, VolumeHandle.posY), isTrue);
    expect(reveal.hidesFace(2, 2, VolumeFace.posY), isTrue);
    expect(reveal.hidesHandle(2, 2, VolumeHandle.posX), isFalse);
    expect(reveal.hidesFace(2, 2, VolumeFace.negY), isFalse);
    expect(reveal.featureOpacityForHandle(2, 2, VolumeHandle.posY), 0);

    reveal.update(
      volumes: volumes,
      lookAt: volumes.grid.tileCenter(2, 2),
      distance: 32,
      enabled: true,
    );
    expect(reveal.hidesHandle(2, 2, VolumeHandle.posY), isFalse);
    expect(reveal.hidesFace(2, 2, VolumeFace.negY), isTrue);
  });

  test('joined solid still keeps a roof on every cell', () {
    final volumes = _joinedPair();
    final solid = resolveVolumeSolid(volumes.volumes.single, volumes.grid);
    expect(solid.surfaceAt(2, 2, VolumeHandle.posY), isNotNull);
    expect(solid.surfaceAt(3, 2, VolumeHandle.posY), isNotNull);
  });
}
