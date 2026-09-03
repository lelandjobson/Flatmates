import 'package:flatmates/gameplay/game_history.dart';
import 'package:flatmates/gameplay/paint/face_paint_store.dart';
import 'package:flatmates/gameplay/paper/paper_cost.dart';
import 'package:flatmates/gameplay/paper/paper_wallet.dart';
import 'package:flatmates/gameplay/paths/path_store.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flatmates/gameplay/volumes/volume_store.dart';
import 'package:flatmates/gameplay/walls/wall_edge.dart';
import 'package:flatmates/gameplay/walls/wall_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  GameSnapshot capture(
    VolumeStore volumes,
    PathStore paths,
    FacePaintStore paint, {
    WallStore? walls,
    PaperWallet? paper,
    String label = 'test',
  }) {
    return GameSnapshot.capture(
      volumes: volumes,
      paths: paths,
      walls: walls ?? WallStore(grid: volumes.grid),
      landscape: null,
      facePaint: paint,
      paper: paper,
      label: label,
    );
  }

  void apply(
    GameSnapshot snap,
    VolumeStore volumes,
    PathStore paths,
    FacePaintStore paint, {
    WallStore? walls,
    PaperWallet? paper,
  }) {
    snap.applyTo(
      volumes: volumes,
      paths: paths,
      walls: walls ?? WallStore(grid: volumes.grid),
      landscape: null,
      facePaint: paint,
      paper: paper,
    );
  }

  test('undo and redo restore a placed volume draft', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final paint = FacePaintStore();
    final history = GameHistory();

    final before = capture(volumes, paths, paint);
    expect(volumes.startNew(1, 2), isTrue);
    history.pushSnapshot(before);

    expect(volumes.draftVolume, isNotNull);
    expect(volumes.phase, VolumeEditPhase.editing);

    final undone = history.undo(capture(volumes, paths, paint));
    expect(undone, isNotNull);
    apply(undone!, volumes, paths, paint);
    expect(volumes.draftVolume, isNull);
    expect(volumes.volumes, isEmpty);
    expect(volumes.phase, VolumeEditPhase.idle);

    final redone = history.redo(capture(volumes, paths, paint));
    expect(redone, isNotNull);
    apply(redone!, volumes, paths, paint);
    expect(volumes.draftVolume, isNotNull);
    expect(volumes.draftCell?.tx, 1);
    expect(volumes.draftCell?.ty, 2);
    expect(volumes.phase, VolumeEditPhase.editing);
  });

  test('undo and redo restore a path island', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final paint = FacePaintStore();
    final history = GameHistory();

    final before = capture(volumes, paths, paint);
    expect(paths.addIsland(4, 5), isTrue);
    history.pushSnapshot(before);

    expect(paths.contains(4, 5), isTrue);
    apply(history.undo(capture(volumes, paths, paint))!, volumes, paths, paint);
    expect(paths.contains(4, 5), isFalse);

    apply(history.redo(capture(volumes, paths, paint))!, volumes, paths, paint);
    expect(paths.contains(4, 5), isTrue);
  });

  test('grow undo keeps the original volume and drops the extra cell', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final paint = FacePaintStore();
    final history = GameHistory();

    expect(volumes.startNew(3, 3), isTrue);
    expect(volumes.confirmEdit(), isTrue);
    volumes.toggleAccess(VolumeSide.east);
    expect(volumes.confirmAccess(), isTrue);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cells, hasLength(1));

    final candidates = volumes.growCandidates();
    expect(candidates, isNotEmpty);
    final before = capture(volumes, paths, paint);
    expect(volumes.startGrow(candidates.first), isTrue);
    history.pushSnapshot(before);
    expect(volumes.draftVolume?.cells, hasLength(2));

    apply(history.undo(capture(volumes, paths, paint))!, volumes, paths, paint);
    expect(volumes.phase, VolumeEditPhase.idle);
    expect(volumes.volumes, hasLength(1));
    expect(volumes.volumes.single.cells, hasLength(1));
    expect(volumes.volumes.single.cells.single.tx, 3);
    expect(volumes.volumes.single.cells.single.ty, 3);
  });

  test('undo and redo restore a painted wall', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final paint = FacePaintStore();
    final history = GameHistory();

    final before = capture(volumes, paths, paint, walls: walls);
    expect(walls.add(WallEdge(2, 3, 3, 3)), isTrue);
    history.pushSnapshot(before);

    apply(
      history.undo(capture(volumes, paths, paint, walls: walls))!,
      volumes,
      paths,
      paint,
      walls: walls,
    );
    expect(walls.contains(WallEdge(2, 3, 3, 3)), isFalse);

    apply(
      history.redo(capture(volumes, paths, paint, walls: walls))!,
      volumes,
      paths,
      paint,
      walls: walls,
    );
    expect(walls.contains(WallEdge(2, 3, 3, 3)), isTrue);
  });

  test('snapshot clones are independent of later live mutations', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final paint = FacePaintStore();

    expect(volumes.startNew(0, 0), isTrue);
    volumes.draftCell!.box.widthSubtiles = 5;
    final snap = capture(volumes, paths, paint);
    volumes.draftCell!.box.widthSubtiles = 8;

    apply(snap, volumes, paths, paint);
    expect(volumes.draftCell!.box.widthSubtiles, 5);
  });

  test('undo and redo restore paper held and committed', () {
    final volumes = VolumeStore();
    final paths = PathStore(grid: volumes.grid);
    final walls = WallStore(grid: volumes.grid);
    final paint = FacePaintStore();
    final paper = PaperWallet();
    final history = GameHistory();

    final before = capture(volumes, paths, paint, walls: walls, paper: paper);
    expect(volumes.paintAt(1, 1), isTrue);
    expect(paper.settleWorld(volumes: volumes, paths: paths, walls: walls), isTrue);
    expect(paper.held, kStartingPaper - 20);
    history.pushSnapshot(before);

    apply(
      history.undo(capture(volumes, paths, paint, walls: walls, paper: paper))!,
      volumes,
      paths,
      paint,
      walls: walls,
      paper: paper,
    );
    expect(paper.held, kStartingPaper);
    expect(paper.volumeCommitted, isEmpty);

    apply(
      history.redo(capture(volumes, paths, paint, walls: walls, paper: paper))!,
      volumes,
      paths,
      paint,
      walls: walls,
      paper: paper,
    );
    expect(paper.held, kStartingPaper - 20);
    expect(paper.volumeCommitted.values.single, 20);
  });
}
