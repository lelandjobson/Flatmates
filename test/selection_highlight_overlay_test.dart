import 'package:flatmates/gameplay/picking/selectable.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/ui/game/selection_highlight_overlay.dart';
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
}
