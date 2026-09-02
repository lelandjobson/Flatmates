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

  test('tile, region, and path only expose isolate', () {
    expect(ids(SelectableHit.tile(2, 3)), [SelectionActionId.isolate]);
    expect(
      ids(SelectableHit.region(WallRegion({(1, 1), (1, 2)}), tx: 1, ty: 1)),
      [SelectionActionId.isolate],
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

  test('volume isolate opens interior view instead of crop isolate', () {
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
}
