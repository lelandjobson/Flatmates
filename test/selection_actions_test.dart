import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/picking/selection_actions.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_program.dart';
import 'package:flatmates/gameplay/walls/wall_regions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<SelectionActionId> ids(SelectableHit hit, {Volume? volume}) {
    return inferSelectionActions(
      hit: hit,
      volume: volume,
      programs: VolumeProgramStore(),
    ).map((a) => a.id).toList();
  }

  test('tile and path only expose isolate; region also exposes program', () {
    expect(ids(SelectableHit.tile(2, 3)), [SelectionActionId.isolate]);
    expect(
      ids(SelectableHit.region(WallRegion({(1, 1), (1, 2)}), tx: 1, ty: 1)),
      [SelectionActionId.isolate, SelectionActionId.program],
    );
    expect(ids(SelectableHit.path(4, 5)), [SelectionActionId.isolate]);
  });

  test('volume exposes isolate, optional program, and delete', () {
    final volume = Volume(
      id: 1,
      cells: [VolumeCell(tx: 2, ty: 2, box: BoxPrimitive())],
    );
    expect(ids(SelectableHit.volume(1, cell: volume.cells.first), volume: volume), [
      SelectionActionId.isolate,
      SelectionActionId.program,
      SelectionActionId.delete,
    ]);
  });

  test('volume face exposes isolate and focus face, not a click-to-isolate path', () {
    expect(
      ids(
        SelectableHit.volumeFace(
          1,
          face: VolumeFace.posY,
          cell: VolumeCell(tx: 2, ty: 2, box: BoxPrimitive()),
        ),
      ),
      [SelectionActionId.isolate, SelectionActionId.focusFace],
    );
  });

  test('volume floor face also exposes program', () {
    expect(
      ids(
        SelectableHit.volumeFace(
          1,
          face: VolumeFace.negY,
          cell: VolumeCell(tx: 2, ty: 2, box: BoxPrimitive()),
        ),
      ),
      [
        SelectionActionId.isolate,
        SelectionActionId.program,
        SelectionActionId.focusFace,
      ],
    );
  });

  test('programmed floor also exposes stuff', () {
    final programs = VolumeProgramStore()
      ..assignIndoor(tx: 2, ty: 2, programId: kProgramBedroom);
    final hit = SelectableHit.volumeFace(
      1,
      face: VolumeFace.negY,
      cell: VolumeCell(tx: 2, ty: 2, box: BoxPrimitive()),
    );
    expect(
      inferSelectionActions(hit: hit, programs: programs).map((a) => a.id),
      [
        SelectionActionId.isolate,
        SelectionActionId.program,
        SelectionActionId.stuff,
        SelectionActionId.focusFace,
      ],
    );
  });

  test('stuff exposes focus floor and delete', () {
    expect(
      ids(SelectableHit.stuff('1', volumeId: 1, tx: 2, ty: 2)),
      [SelectionActionId.isolate, SelectionActionId.delete],
    );
    expect(
      isolateOpensVolumeInterior(
        SelectableHit.stuff('1', volumeId: 1, tx: 2, ty: 2),
      ),
      isFalse,
    );
  });

  test('volume isolate zooms in-map instead of crop isolate', () {
    final volume = Volume(
      id: 1,
      cells: [VolumeCell(tx: 2, ty: 2, box: BoxPrimitive())],
    );
    expect(
      isolateOpensVolumeInterior(
        SelectableHit.volume(1, cell: volume.cells.first),
      ),
      isTrue,
    );
    expect(
      isolateOpensVolumeInterior(
        SelectableHit.volumeFace(
          1,
          face: VolumeFace.posY,
          cell: volume.cells.first,
        ),
      ),
      isTrue,
    );
    expect(isolateOpensVolumeInterior(SelectableHit.tile(2, 3)), isFalse);
    expect(isolateOpensVolumeInterior(SelectableHit.path(4, 5)), isFalse);
  });

  test('friend exposes focus only', () {
    expect(
      ids(SelectableHit.friend('cubeboy')),
      [SelectionActionId.focusFriend],
    );
  });

  test('blocked hover does not keep the last selected outline', () {
    final last = SelectableHit.tile(1, 3);
    expect(
      selectionOutlineHit(hover: null, blocked: true),
      isNull,
    );
    expect(
      selectionOutlineHit(hover: last, blocked: true),
      isNull,
    );
    expect(
      selectionOutlineHit(hover: SelectableHit.tile(0, 2), blocked: false)?.tx,
      0,
    );
  });
}
