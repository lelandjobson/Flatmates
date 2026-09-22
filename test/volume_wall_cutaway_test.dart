import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_box_mesh.dart';
import 'package:flatmates/gameplay/volumes/volume_ceiling_reveal.dart';
import 'package:flatmates/gameplay/volumes/volume_content_loader.dart';
import 'package:flatmates/gameplay/volumes/volume_datum.dart';
import 'package:flatmates/gameplay/volumes/volume_outline.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/volumes/volume_wall_cutaway.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';

VolumeStore _cellAt(int tx, int ty) {
  final volumes = VolumeStore();
  expect(volumes.paintAt(tx, ty), isTrue);
  expect(volumes.confirmEdit(), isTrue);
  return volumes;
}

void main() {
  test('east camera hides only the east wall', () {
    final center = Vector3(0, 0, 0);
    final camera = Vector3(10, 4, 0);
    expect(
      wallFacing(
        camera: camera,
        cellCenter: center,
        outwardNormal: VolumeFace.posX.worldNormal,
      ),
      closeTo(1, 1e-6),
    );
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.posX.worldNormal,
        ),
      ),
      0,
    );
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.negX.worldNormal,
        ),
      ),
      1,
    );
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.posZ.worldNormal,
        ),
      ),
      1,
    );
  });

  test('southeast camera hides east and south walls', () {
    final center = Vector3(0, 0, 0);
    final camera = Vector3(10, 4, 10);
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.posX.worldNormal,
        ),
      ),
      0,
    );
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.posZ.worldNormal,
        ),
      ),
      0,
    );
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.negX.worldNormal,
        ),
      ),
      1,
    );
    expect(
      wallCutawayOpacity(
        wallFacing(
          camera: camera,
          cellCenter: center,
          outwardNormal: VolumeFace.negZ.worldNormal,
        ),
      ),
      1,
    );
  });

  test('walls stay opaque while the ceiling is up', () {
    expect(
      wallOpacityForReveal(ceilingOpacity: 1, cutaway: 0),
      1,
    );
    expect(
      wallOpacityForReveal(ceilingOpacity: 0, cutaway: 0),
      0,
    );
    expect(
      wallOpacityForReveal(ceilingOpacity: 0.5, cutaway: 0),
      closeTo(0.5, 1e-9),
    );
  });

  test('above-datum volumes hide when zoomed in without waiting for load', () {
    expect(
      volumeAboveCurrentDatum(
        volumeDatum: 1,
        currentDatum: 0,
        zoomedIn: true,
      ),
      isTrue,
    );
    expect(
      volumeAboveCurrentDatum(
        volumeDatum: 1,
        currentDatum: 0,
        zoomedIn: false,
      ),
      isFalse,
    );
    expect(
      volumeAtCurrentDatum(volumeDatum: 0, currentDatum: 0),
      isTrue,
    );
    expect(
      volumeBelowCurrentDatum(volumeDatum: 0, currentDatum: 1),
      isTrue,
    );

    final volumes = _cellAt(2, 2);
    volumes.volumes.add(
      Volume(
        id: 99,
        datum: 1,
        cells: [VolumeCell(tx: 6, ty: 6, box: BoxPrimitive())],
      ),
    );
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
      currentDatum: 0,
    );
    expect(reveal.wantsReveal, isTrue);
    expect(loader.isLoaded(const VolumePartId(6, 6)), isFalse);
    expect(
      volumeAboveCurrentDatum(
        volumeDatum: 1,
        currentDatum: 0,
        zoomedIn: reveal.wantsReveal,
      ),
      isTrue,
    );

    final scene = Scene();
    addTearDown(scene.dispose);
    syncVolumeMeshes(
      scene,
      volumes,
      hiddenByDatumVolumeIds: {
        for (final volume in volumes.visibleVolumes)
          if (volumeAboveCurrentDatum(
            volumeDatum: volume.datum,
            currentDatum: 0,
            zoomedIn: reveal.wantsReveal,
          ))
            volume.id,
      },
    );
    expect(scene.meshById(volumeMeshId(99, 6, 6)), isNull);
    expect(
      scene.meshById(volumeMeshId(volumes.volumes.first.id, 2, 2)),
      isNotNull,
    );
  });

  test('current-datum walls cut away after the ceiling opens', () async {
    final volumes = _cellAt(2, 2);
    final loader = VolumeContentLoader(loadPart: (_) async {});
    addTearDown(loader.dispose);
    final reveal = VolumeCeilingReveal(
      loader: loader,
      fadeDuration: Duration.zero,
    );
    addTearDown(reveal.dispose);
    final look = volumes.grid.tileCenter(2, 2);
    final east = look + Vector3(12, 6, 0);
    reveal.update(
      volumes: volumes,
      lookAt: look,
      distance: 18,
      enabled: true,
      cameraPosition: east,
      currentDatum: 0,
    );
    await Future<void>.delayed(Duration.zero);
    expect(reveal.opacityFor(const VolumePartId(2, 2)), 0);
    expect(reveal.hidesFace(2, 2, VolumeFace.posX), isTrue);
    expect(reveal.hidesFace(2, 2, VolumeFace.negX), isFalse);
    expect(reveal.hidesHandle(2, 2, VolumeHandle.posX), isTrue);
    expect(reveal.hidesHandle(2, 2, VolumeHandle.negX), isFalse);
  });

  test('opened tiles hide outer wall outline curves', () async {
    final volumes = _cellAt(2, 2);
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
      cameraPosition: look + Vector3(12, 6, 0),
      currentDatum: 0,
    );
    await Future<void>.delayed(Duration.zero);
    final outline = buildVolumeOutline(volumes.volumes.single, volumes.grid);
    expect(outline.edges, isNotEmpty);
    final eastX = volumes.grid.tileOrigin(2, 2).x + volumes.grid.tileSize;
    final eastEdges = outline.edges.where(
      (edge) =>
          (edge.a.x - eastX).abs() < 1e-6 && (edge.b.x - eastX).abs() < 1e-6,
    );
    expect(eastEdges, isNotEmpty);
    for (final edge in outline.edges) {
      expect(
        reveal.outlineOpacityFor(edge, volumes.grid),
        0,
        reason: 'opened tile must hide wall/roof silhouette edges',
      );
    }

    reveal.update(
      volumes: volumes,
      lookAt: look,
      distance: 33,
      enabled: true,
      cameraPosition: look + Vector3(12, 6, 0),
      currentDatum: 0,
    );
    for (final edge in outline.edges) {
      expect(reveal.outlineOpacityFor(edge, volumes.grid), 1);
    }
  });

  test('below-datum volumes stay intact while a higher story is current',
      () async {
    final volumes = _cellAt(2, 2);
    volumes.volumes.add(
      Volume(
        id: 7,
        datum: 1,
        cells: [VolumeCell(tx: 2, ty: 3, box: BoxPrimitive())],
      ),
    );
    final loader = VolumeContentLoader(loadPart: (_) async {});
    addTearDown(loader.dispose);
    final reveal = VolumeCeilingReveal(
      loader: loader,
      fadeDuration: Duration.zero,
    );
    addTearDown(reveal.dispose);
    final look = volumes.grid.tileCenter(2, 3);
    final east = look + Vector3(12, 6, 0);
    reveal.update(
      volumes: volumes,
      lookAt: look,
      distance: 18,
      enabled: true,
      cameraPosition: east,
      currentDatum: 1,
    );
    await Future<void>.delayed(Duration.zero);
    expect(reveal.opacityFor(const VolumePartId(2, 3)), 0);
    expect(reveal.hidesFace(2, 3, VolumeFace.posX), isTrue);
    expect(reveal.opacityFor(const VolumePartId(2, 2)), 1);
    expect(reveal.hidesFace(2, 2, VolumeFace.posY), isFalse);
    expect(reveal.hidesFace(2, 2, VolumeFace.posX), isFalse);
    expect(reveal.hidesFace(2, 2, VolumeFace.negY), isTrue);
  });
}
