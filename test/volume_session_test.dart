import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('paintAt creates a new mass on an empty tile', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.phase, VolumeEditPhase.editing);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.draftCell?.tx, 1);
    expect(volumes.draftCell?.ty, 1);
  });

  test('paintAt grows a 4-adjacent mass', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cells, hasLength(2));
    expect(volumes.draftCell?.tx, 2);
  });

  test('paintAt merges several adjacent masses then adds the cell', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(3, 1), isTrue);
    expect(volumes.volumes, hasLength(2));
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cells, hasLength(3));
    expect(volumes.lastAbsorbedIds, isNotEmpty);
  });

  test('paintAt on an occupied tile selects it', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.draftCell?.tx, 1);
    expect(volumes.draftCell?.ty, 1);
    expect(volumes.volumes.single.cells, hasLength(2));
  });

  test('join and disconnect split and recombine a mass', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.disconnectSelected(), isTrue);
    expect(volumes.volumes, hasLength(2));
    expect(volumes.draftVolume?.cells, hasLength(1));
    expect(volumes.joinSelected(), isTrue);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cells, hasLength(2));
  });

  test('deleteSelected removes the cell and keeps the rest of the mass', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.deleteSelected(), isTrue);
    expect(volumes.volumes.single.cells, hasLength(1));
    expect(volumes.volumes.single.cells.single.tx, 1);
  });

  test('cancelDraft restores the session baseline', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.paintAt(4, 4), isTrue);
    expect(volumes.paintAt(5, 4), isTrue);
    expect(volumes.volumes, hasLength(2));
    volumes.cancelDraft();
    expect(volumes.phase, VolumeEditPhase.idle);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cellAt(1, 1), isNotNull);
    expect(volumes.volumeAt(4, 4), isNull);
  });

  test('confirmEdit skips the door-picking step', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    expect(volumes.phase, VolumeEditPhase.idle);
    expect(volumes.volumes.single.accessibleSides, isEmpty);
    expect(volumes.draftVolume, isNull);
  });

  test('blocked tiles are not painted', () {
    final volumes = VolumeStore();
    expect(
      volumes.paintAt(1, 1, blocked: (tx, ty) => tx == 1 && ty == 1),
      isFalse,
    );
    expect(volumes.volumes, isEmpty);
  });

  test('commitKeepFocus leaves the mass selected and idle', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.commitKeepFocus(), isTrue);
    expect(volumes.phase, VolumeEditPhase.idle);
    expect(volumes.draftVolume, isNotNull);
    expect(volumes.draftCell?.tx, 1);
    expect(volumes.volumes, hasLength(1));
  });

  test('adjacent paint after commit still merges into one mass', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.commitKeepFocus(), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.commitKeepFocus(), isTrue);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cells, hasLength(2));
  });

  test('joined mass exposes exterior facets only', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    final facets = volumes.volumes.single.exteriorFacets();
    expect(facets, hasLength(8));
    expect(
      facets.any((f) => f.cell.tx == 1 && f.handle == VolumeHandle.posX),
      isFalse,
    );
    expect(
      facets.any((f) => f.cell.tx == 2 && f.handle == VolumeHandle.negX),
      isFalse,
    );
    expect(
      facets.where((f) => f.handle == VolumeHandle.posY),
      hasLength(2),
    );
  });

  test('removeFocusedVolume deletes the whole joined mass', () {
    final volumes = VolumeStore();
    expect(volumes.paintAt(1, 1), isTrue);
    expect(volumes.paintAt(2, 1), isTrue);
    expect(volumes.commitKeepFocus(), isTrue);
    expect(volumes.removeFocusedVolume(), isTrue);
    expect(volumes.volumes, isEmpty);
    expect(volumes.draftVolume, isNull);
  });
}
