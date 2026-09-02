import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_solid.dart';
import 'package:flatmates/gameplay/volumes/volume_solid_sync.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('interior view hides roof and outward faces until exterior is shown', () {
    final hidden = volumeInteriorViewSpec(showExterior: false);
    expect(hidden.hideRoof, isTrue);
    expect(hidden.hideOutwardFaces, isTrue);

    final shown = volumeInteriorViewSpec(showExterior: true);
    expect(shown.hideRoof, isTrue);
    expect(shown.hideOutwardFaces, isFalse);
  });

  test('interior classification keeps courtyard walls as enclosure', () {
    final volumes = VolumeStore();
    for (var ty = 1; ty <= 3; ty++) {
      for (var tx = 1; tx <= 3; tx++) {
        volumes.paintAt(tx, ty);
      }
    }
    volumes.commitKeepFocus();
    volumes.removeCellAt(2, 2);
    final solid = resolveVolumeSolid(volumes.volumes.single, volumes.grid);
    expect(solid.holeTiles, {(2, 2)});
    for (final wall in solid.courtyardWalls()) {
      expect(wall.kind, VolumeSurfaceKind.wall);
      expect(wall.enclosure, VolumeEnclosure.courtyard);
      expect(solid.isHandleFullyInternal(wall.tx, wall.ty, wall.handle), isFalse);
    }
    expect(
      solid.surfaces.where((s) => s.kind == VolumeSurfaceKind.roof),
      hasLength(8),
    );
  });
}
