import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('6×6 stamp fits a default floor and leftover is circulation', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(1, 1), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final cell = volume.cells.single;
    final programs = VolumeProgramStore();
    expect(programs.canAssignToVolume(volume), isTrue);
    expect(
      programs.place(
        volume: volume,
        cell: cell,
        originU: 1,
        originV: 1,
        kind: VolumeProgramKind.bedroom,
      ),
      isNotNull,
    );
    final stamp = programs.stamps.single;
    expect(stamp.width, 6);
    expect(stamp.height, 6);
    expect(stamp.originU, 1);
    expect(stamp.originV, 1);
    final floor = cell.box.widthSubtiles * cell.box.depthSubtiles;
    expect(floor - stamp.width * stamp.height, 28);
  });

  test('stamps cannot overlap on the same cell', () {
    final cell = VolumeCell(
      tx: 0,
      ty: 0,
      box: BoxPrimitive(widthSubtiles: 14, depthSubtiles: 14),
    );
    final volume = Volume(id: 1, cells: [cell]);
    final programs = VolumeProgramStore();
    expect(
      programs.place(
        volume: volume,
        cell: cell,
        originU: 0,
        originV: 0,
        kind: VolumeProgramKind.bedroom,
      ),
      isNotNull,
    );
    expect(
      programs.place(
        volume: volume,
        cell: cell,
        originU: 1,
        originV: 1,
        kind: VolumeProgramKind.common,
      ),
      isNull,
    );
    expect(
      programs.place(
        volume: volume,
        cell: cell,
        originU: 6,
        originV: 0,
        kind: VolumeProgramKind.common,
      ),
      isNotNull,
    );
    expect(programs.stamps, hasLength(2));
  });

  test('snapOrigin stays inside the cell and avoids overlap', () {
    final cell = VolumeCell(
      tx: 0,
      ty: 0,
      box: BoxPrimitive(widthSubtiles: 14, depthSubtiles: 8),
    );
    final volume = Volume(id: 1, cells: [cell]);
    final programs = VolumeProgramStore();
    expect(
      programs.place(
        volume: volume,
        cell: cell,
        originU: 0,
        originV: 0,
        kind: VolumeProgramKind.bedroom,
      ),
      isNotNull,
    );
    expect(programs.snapOrigin(cell: cell, u: 20, v: 20), (8, 2));
    expect(
      programs.snapOrigin(cell: cell, u: 0, v: 0, volumeId: volume.id),
      (6, 0),
    );
    expect(
      programs.snapOrigin(
        cell: VolumeCell(tx: 0, ty: 0, box: BoxPrimitive(widthSubtiles: 4)),
        u: 0,
        v: 0,
      ),
      isNull,
    );
  });

  test('floors smaller than 6×6 cannot take a program', () {
    final cell = VolumeCell(
      tx: 0,
      ty: 0,
      box: BoxPrimitive(widthSubtiles: 5, depthSubtiles: 8),
    );
    final volume = Volume(id: 1, cells: [cell]);
    final programs = VolumeProgramStore();
    expect(programs.canAssignProgram(cell), isFalse);
    expect(programs.canAssignToVolume(volume), isFalse);
    expect(
      programs.place(
        volume: volume,
        cell: cell,
        originU: 0,
        originV: 0,
        kind: VolumeProgramKind.common,
      ),
      isNull,
    );
  });
}
