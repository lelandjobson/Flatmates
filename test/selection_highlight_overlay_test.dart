import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flatmates/gameplay/volumes/volume_outline.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/ui/game/selection_highlight_overlay.dart';
import 'package:flatmates/ui/game/selection_highlight_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('erase highlight uses the stored cell, not every cell in the volume', () {
    final volumes = VolumeStore();
    expect(volumes.startNew(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final volume = volumes.volumes.single;
    final hit = SelectableHit.volume(volume.id, cell: volume.cellAt(3, 2));
    expect(
      volumeCellsForHighlight(hit, volume, cellOnly: false),
      volume.cells,
    );
    final piece = volumeCellsForHighlight(hit, volume, cellOnly: true);
    expect(piece, hasLength(1));
    expect(piece.single.tx, 3);
    expect(piece.single.ty, 2);
  });

  test('joined volume hover strokes the mass outline, not each cell', () {
    expect(
      highlightStrokesWholeVolume(
        kind: SelectableKind.volume,
        cellOnly: false,
      ),
      isTrue,
    );
    expect(
      highlightStrokesWholeVolume(
        kind: SelectableKind.volume,
        cellOnly: true,
      ),
      isFalse,
    );
    expect(
      highlightStrokesWholeVolume(
        kind: SelectableKind.volumeFace,
        cellOnly: false,
      ),
      isFalse,
    );

    final volumes = VolumeStore();
    expect(volumes.paintAt(2, 2), isTrue);
    expect(volumes.paintAt(3, 2), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    final outline = buildVolumeOutline(
      volumes.volumes.single,
      volumes.grid,
    );
    expect(outline.edges, hasLength(12));
  });

  test('floor picks use a thin footprint style', () {
    final floor = SelectableHit.volumeFace(1, face: VolumeFace.negY);
    final wall = SelectableHit.volumeFace(1, face: VolumeFace.posX);
    expect(highlightUsesFloorStyle(floor), isTrue);
    expect(highlightUsesFloorStyle(wall), isFalse);
    expect(
      highlightStyleFor(floor, SelectionHighlightStyle.standard),
      SelectionHighlightStyle.floor,
    );
    expect(
      highlightStyleFor(wall, SelectionHighlightStyle.standard),
      SelectionHighlightStyle.standard,
    );
    expect(
      highlightDrawsFloorQuads(
        target: const SelectableHit(kind: SelectableKind.volume, volumeId: 1),
        style: SelectionHighlightStyle.floor,
      ),
      isTrue,
    );
    expect(SelectionHighlightStyle.floor.outlineWidth, lessThan(2));
  });
}
