import 'package:flutter/foundation.dart';

import '../landscape/landscape_grid.dart';
import 'paint/face_paint_store.dart';
import 'paper/paper_wallet.dart';
import 'paths/path_store.dart';
import 'volumes/volume.dart';
import 'volumes/volume_program.dart';
import 'volumes/volume_store.dart';
import 'walls/wall_edge.dart';
import 'walls/wall_store.dart';

/// Immutable snapshot of gameplay world state (volumes, paths, landscape, paint).
class GameSnapshot {
  GameSnapshot({
    required this.volumes,
    required this.draftVolume,
    required this.draftCell,
    required this.draftIsGrow,
    required this.phase,
    required this.nextVolumeId,
    required this.pathTiles,
    required this.pathEdges,
    required this.wallEdges,
    required this.landscape,
    required this.facePaint,
    required this.label,
    PaperWallet? paper,
    this.programs,
    this.sessionTouchedIds = const {},
    this.sessionBaseline,
    this.sessionNextId,
    this.noOp = false,
    this.restoresOperativeOnRedo = false,
  }) : paper = paper ?? PaperWallet();

  final List<Volume> volumes;
  final Volume? draftVolume;
  final VolumeCell? draftCell;
  final bool draftIsGrow;
  final VolumeEditPhase phase;
  final int nextVolumeId;
  final Set<(int, int)> pathTiles;
  final Set<PathEdge> pathEdges;
  final Set<WallEdge> wallEdges;
  final LandscapeGrid? landscape;
  final FacePaintStore facePaint;
  final PaperWallet paper;
  final VolumeProgramStore? programs;
  final Set<int> sessionTouchedIds;
  final List<Volume>? sessionBaseline;
  final int? sessionNextId;
  final String label;
  final bool noOp;
  final bool restoresOperativeOnRedo;

  GameSnapshot copyWith({
    bool? restoresOperativeOnRedo,
  }) {
    return GameSnapshot(
      volumes: volumes,
      draftVolume: draftVolume,
      draftCell: draftCell,
      draftIsGrow: draftIsGrow,
      phase: phase,
      nextVolumeId: nextVolumeId,
      pathTiles: pathTiles,
      pathEdges: pathEdges,
      wallEdges: wallEdges,
      landscape: landscape,
      facePaint: facePaint,
      paper: paper,
      programs: programs,
      sessionTouchedIds: sessionTouchedIds,
      sessionBaseline: sessionBaseline,
      sessionNextId: sessionNextId,
      label: label,
      noOp: noOp,
      restoresOperativeOnRedo:
          restoresOperativeOnRedo ?? this.restoresOperativeOnRedo,
    );
  }

  factory GameSnapshot.capture({
    required VolumeStore volumes,
    required PathStore paths,
    required WallStore walls,
    required LandscapeGrid? landscape,
    required FacePaintStore facePaint,
    required String label,
    PaperWallet? paper,
    VolumeProgramStore? programs,
    bool noOp = false,
  }) {
    final cloned = <Volume>[
      for (final volume in volumes.volumes) volume.clone(),
    ];
    Volume? draft;
    VolumeCell? draftCell;
    final liveDraft = volumes.draftVolume;
    if (liveDraft != null) {
      if (volumes.volumes.contains(liveDraft)) {
        draft = cloned.firstWhere((v) => v.id == liveDraft.id);
      } else {
        draft = liveDraft.clone();
      }
      final liveCell = volumes.draftCell;
      if (liveCell != null) {
        draftCell = draft.cellAt(liveCell.tx, liveCell.ty);
      }
    }
    return GameSnapshot(
      volumes: cloned,
      draftVolume: draft,
      draftCell: draftCell,
      draftIsGrow: volumes.draftIsGrow,
      phase: volumes.phase,
      nextVolumeId: volumes.nextId,
      pathTiles: Set<(int, int)>.from(paths.tiles),
      pathEdges: Set<PathEdge>.from(paths.edges),
      wallEdges: Set<WallEdge>.from(walls.edges),
      landscape: landscape?.copy(),
      facePaint: facePaint.copy(),
      paper: paper?.copy(),
      programs: programs?.copy(),
      sessionTouchedIds: Set<int>.from(volumes.sessionTouchedIds),
      sessionBaseline: volumes.sessionBaseline == null
          ? null
          : [for (final volume in volumes.sessionBaseline!) volume.clone()],
      sessionNextId: volumes.sessionNextId,
      label: label,
      noOp: noOp,
    );
  }

  void applyTo({
    required VolumeStore volumes,
    required PathStore paths,
    required WallStore walls,
    required LandscapeGrid? landscape,
    required FacePaintStore facePaint,
    PaperWallet? paper,
    VolumeProgramStore? programs,
  }) {
    final clonedVolumes = [for (final volume in this.volumes) volume.clone()];
    Volume? draft;
    VolumeCell? cell;
    final snapDraft = draftVolume;
    if (snapDraft != null) {
      final listed = [
        for (final volume in clonedVolumes)
          if (volume.id == snapDraft.id) volume,
      ];
      final restoredDraft =
          listed.isNotEmpty ? listed.first : snapDraft.clone();
      draft = restoredDraft;
      final snapCell = draftCell;
      if (snapCell != null) {
        cell = restoredDraft.cellAt(snapCell.tx, snapCell.ty);
      }
    }
    volumes.restore(
      volumes: clonedVolumes,
      draftVolume: draft,
      draftCell: cell,
      draftIsGrow: draftIsGrow,
      phase: phase,
      nextId: nextVolumeId,
      sessionTouchedIds: Set<int>.from(sessionTouchedIds),
      sessionBaseline: sessionBaseline == null
          ? null
          : [for (final volume in sessionBaseline!) volume.clone()],
      sessionNextId: sessionNextId,
    );
    paths.restore(
      tiles: Set<(int, int)>.from(pathTiles),
      edges: Set<PathEdge>.from(pathEdges),
    );
    walls.restore(Set<WallEdge>.from(wallEdges));
    if (landscape != null && this.landscape != null) {
      landscape.restoreFrom(this.landscape!);
    }
    facePaint.restoreFrom(this.facePaint);
    paper?.restoreFrom(this.paper);
    if (programs != null && this.programs != null) {
      programs.restoreFrom(this.programs!);
    }
  }
}

/// Snapshot-based undo / redo stack, matching [CraftingHistory].
class GameHistory extends ChangeNotifier {
  final List<GameSnapshot> _undoStack = [];
  final List<GameSnapshot> _redoStack = [];
  static const int maxDepth = 50;

  int _operativeActionCount = 0;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoDepth => _undoStack.length;
  int get operativeActionCount => _operativeActionCount;

  /// Push the state **before** a mutation so undoing restores it.
  void pushSnapshot(GameSnapshot snapshot) {
    _undoStack.add(snapshot);
    if (!snapshot.noOp) {
      _operativeActionCount++;
    }
    if (_undoStack.length > maxDepth) {
      final removed = _undoStack.removeAt(0);
      if (!removed.noOp) {
        _operativeActionCount--;
      }
    }
    _redoStack.clear();
    notifyListeners();
  }

  GameSnapshot? undo(GameSnapshot current) {
    if (_undoStack.isEmpty) return null;
    final previous = _undoStack.removeLast();
    if (!previous.noOp) {
      _operativeActionCount--;
    }
    _redoStack.add(
      current.copyWith(restoresOperativeOnRedo: !previous.noOp),
    );
    notifyListeners();
    return previous;
  }

  GameSnapshot? redo(GameSnapshot current) {
    if (_redoStack.isEmpty) return null;
    _undoStack.add(current);
    final next = _redoStack.removeLast();
    if (next.restoresOperativeOnRedo) {
      _operativeActionCount++;
    }
    notifyListeners();
    return next;
  }

  void clear() {
    if (_undoStack.isEmpty && _redoStack.isEmpty && _operativeActionCount == 0) {
      return;
    }
    _undoStack.clear();
    _redoStack.clear();
    _operativeActionCount = 0;
    notifyListeners();
  }
}
