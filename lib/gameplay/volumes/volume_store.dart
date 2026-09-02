import 'volume.dart';

enum VolumeEditPhase { idle, editing, pickingAccess }

/// Occupancy + draft lifecycle for map volumes.
class VolumeStore {
  VolumeStore({VolumeGrid? grid}) : grid = grid ?? const VolumeGrid();

  final VolumeGrid grid;
  final List<Volume> volumes = [];

  Volume? draftVolume;
  VolumeCell? draftCell;
  bool draftIsGrow = false;
  VolumeEditPhase phase = VolumeEditPhase.idle;

  /// Volumes created or edited in the open placement session.
  final Set<int> sessionTouchedIds = {};

  /// Snapshot of [volumes] when the current session began.
  List<Volume>? sessionBaseline;
  int sessionNextId = 1;

  int _nextId = 1;
  int get nextId => _nextId;

  final List<int> lastAbsorbedIds = [];

  void restore({
    required List<Volume> volumes,
    Volume? draftVolume,
    VolumeCell? draftCell,
    required bool draftIsGrow,
    required VolumeEditPhase phase,
    required int nextId,
    Set<int>? sessionTouchedIds,
    List<Volume>? sessionBaseline,
    int? sessionNextId,
  }) {
    this.volumes
      ..clear()
      ..addAll(volumes);
    this.draftVolume = draftVolume;
    this.draftCell = draftCell;
    this.draftIsGrow = draftIsGrow;
    this.phase = phase == VolumeEditPhase.pickingAccess
        ? VolumeEditPhase.editing
        : phase;
    _nextId = nextId;
    this.sessionTouchedIds
      ..clear()
      ..addAll(sessionTouchedIds ?? const {});
    this.sessionBaseline = sessionBaseline == null
        ? null
        : [for (final volume in sessionBaseline) volume.clone()];
    this.sessionNextId = sessionNextId ?? nextId;
  }

  bool get isEditing =>
      phase == VolumeEditPhase.editing || phase == VolumeEditPhase.pickingAccess;

  /// Door picking is optional and is no longer required to commit.
  bool get requiresAccessibleSide => false;

  Iterable<Volume> get visibleVolumes sync* {
    yield* volumes;
    final draft = draftVolume;
    if (draft != null && !volumes.contains(draft)) yield draft;
  }

  Iterable<Volume> get sessionVolumes sync* {
    for (final volume in visibleVolumes) {
      if (sessionTouchedIds.contains(volume.id)) yield volume;
    }
  }

  int? occupant(int tx, int ty) {
    for (final volume in visibleVolumes) {
      if (volume.cellAt(tx, ty) != null) return volume.id;
    }
    return null;
  }

  bool isOccupied(int tx, int ty) => occupant(tx, ty) != null;

  Volume? volumeById(int id) {
    for (final volume in visibleVolumes) {
      if (volume.id == id) return volume;
    }
    return null;
  }

  Volume? volumeAt(int tx, int ty) {
    final id = occupant(tx, ty);
    if (id == null) return null;
    return volumeById(id);
  }

  /// Volumes whose cells are 4-adjacent to [tx],[ty].
  List<Volume> adjacentVolumes(int tx, int ty) {
    final found = <int, Volume>{};
    for (final side in VolumeSide.values) {
      final (dx, dy) = side.tileDelta;
      final volume = volumeAt(tx + dx, ty + dy);
      if (volume != null) found[volume.id] = volume;
    }
    return found.values.toList();
  }

  /// Volumes that share a 4-adjacent edge with any cell of [volume].
  List<Volume> neighborsOf(Volume volume) {
    final found = <int, Volume>{};
    for (final cell in volume.cells) {
      for (final other in adjacentVolumes(cell.tx, cell.ty)) {
        if (other.id == volume.id) continue;
        found[other.id] = other;
      }
    }
    return found.values.toList();
  }

  void _ensureSession() {
    if (phase != VolumeEditPhase.idle) return;
    sessionBaseline = [for (final volume in volumes) volume.clone()];
    sessionNextId = _nextId;
    sessionTouchedIds.clear();
    phase = VolumeEditPhase.editing;
  }

  void _select(Volume volume, VolumeCell cell) {
    draftVolume = volume;
    draftCell = cell;
    sessionTouchedIds.add(volume.id);
  }

  bool selectAt(int tx, int ty) {
    final volume = volumeAt(tx, ty);
    final cell = volume?.cellAt(tx, ty);
    if (volume == null || cell == null) return false;
    _ensureSession();
    _select(volume, cell);
    draftIsGrow = false;
    return true;
  }

  /// Place a cell, auto-joining adjacent masses, or select an existing cell.
  bool paintAt(
    int tx,
    int ty, {
    bool Function(int tx, int ty)? blocked,
  }) {
    if (!grid.inBounds(tx, ty)) return false;
    if (blocked?.call(tx, ty) ?? false) return false;
    if (isOccupied(tx, ty)) return selectAt(tx, ty);

    _ensureSession();
    lastAbsorbedIds.clear();
    final neighbors = adjacentVolumes(tx, ty);
    final cell = VolumeCell(tx: tx, ty: ty, box: BoxPrimitive());

    if (neighbors.isEmpty) {
      final volume = Volume(id: _nextId++, cells: [cell]);
      volumes.add(volume);
      _select(volume, cell);
      draftIsGrow = false;
      return true;
    }

    final keeper = neighbors.first;
    for (final other in neighbors.skip(1)) {
      lastAbsorbedIds.addAll(mergeVolumes(keeper, other));
    }
    keeper.cells.add(cell);
    _select(keeper, cell);
    draftIsGrow = neighbors.length == 1 && neighbors.first.cells.length > 1;
    return true;
  }

  /// Absorb [other] into [keeper]. Caller remaps paint / programs.
  List<int> mergeVolumes(Volume keeper, Volume other) {
    if (identical(keeper, other) || keeper.id == other.id) return const [];
    keeper.cells.addAll(other.cells);
    volumes.remove(other);
    if (identical(draftVolume, other)) draftVolume = keeper;
    sessionTouchedIds.remove(other.id);
    sessionTouchedIds.add(keeper.id);
    return [other.id];
  }

  bool joinSelected() {
    final volume = draftVolume;
    if (volume == null) return false;
    lastAbsorbedIds.clear();
    final neighbors = neighborsOf(volume);
    if (neighbors.isEmpty) return false;
    for (final other in neighbors) {
      lastAbsorbedIds.addAll(mergeVolumes(volume, other));
    }
    final cell = draftCell;
    if (cell != null) {
      draftCell = volume.cellAt(cell.tx, cell.ty) ?? volume.cells.first;
    }
    return true;
  }

  /// Split the selected cell out of its mass into a new volume.
  bool disconnectSelected() {
    final volume = draftVolume;
    final cell = draftCell;
    if (volume == null || cell == null) return false;
    if (volume.cells.length < 2) return false;
    volume.cells.remove(cell);
    final split = Volume(id: _nextId++, cells: [cell]);
    volumes.add(split);
    _select(split, cell);
    draftIsGrow = false;
    return true;
  }

  bool deleteSelected() {
    final volume = draftVolume;
    final cell = draftCell;
    if (volume == null || cell == null) return false;
    volume.cells.remove(cell);
    if (volume.cells.isEmpty) {
      volumes.remove(volume);
      sessionTouchedIds.remove(volume.id);
      draftVolume = null;
      draftCell = null;
      final next = sessionVolumes.isEmpty ? null : sessionVolumes.first;
      if (next != null && next.cells.isNotEmpty) {
        _select(next, next.cells.first);
      }
    } else {
      _select(volume, volume.cells.first);
    }
    return true;
  }

  /// Removes the entire focused mass.
  bool removeFocusedVolume() {
    final volume = draftVolume;
    if (volume == null) return false;
    return removeVolume(volume);
  }

  bool removeVolume(Volume volume) {
    if (!volumes.remove(volume)) return false;
    sessionTouchedIds.remove(volume.id);
    if (identical(draftVolume, volume)) {
      draftVolume = null;
      draftCell = null;
      draftIsGrow = false;
    }
    return true;
  }

  /// Shift every cell of [volume] by [dtx],[dty] if destinations are free.
  bool tryTranslate(
    Volume volume,
    int dtx,
    int dty, {
    bool Function(int tx, int ty)? blocked,
  }) {
    if (dtx == 0 && dty == 0) return false;
    if (isEditing) return false;
    if (!volumes.contains(volume)) return false;

    final destinations = <(int, int)>[];
    for (final cell in volume.cells) {
      final ntx = cell.tx + dtx;
      final nty = cell.ty + dty;
      if (!grid.inBounds(ntx, nty)) return false;
      final occ = occupant(ntx, nty);
      if (occ != null && occ != volume.id) return false;
      if (blocked?.call(ntx, nty) ?? false) return false;
      destinations.add((ntx, nty));
    }

    for (var i = 0; i < volume.cells.length; i++) {
      final old = volume.cells[i];
      volume.cells[i] = VolumeCell(
        tx: destinations[i].$1,
        ty: destinations[i].$2,
        box: old.box,
        accessibleSides: old.accessibleSides,
        doorOrigins: Map<VolumeSide, int>.from(old.doorOrigins),
      );
    }
    if (identical(draftVolume, volume) && draftCell != null) {
      draftCell = volume.cellAt(destinations.first.$1, destinations.first.$2) ??
          volume.cells.first;
    }
    return true;
  }

  bool startNew(int tx, int ty) {
    if (!grid.inBounds(tx, ty) || isOccupied(tx, ty)) return false;
    if (phase == VolumeEditPhase.pickingAccess) return false;
    if (isEditing) return false;
    return paintAt(tx, ty);
  }

  bool startGrow(VolumeGrowCandidate candidate) {
    if (phase == VolumeEditPhase.pickingAccess) return false;
    if (!grid.inBounds(candidate.tx, candidate.ty)) return false;
    if (isOccupied(candidate.tx, candidate.ty)) return false;
    _ensureSession();
    final cell = VolumeCell(
      tx: candidate.tx,
      ty: candidate.ty,
      box: BoxPrimitive(),
    );
    candidate.volume.cells.add(cell);
    if (!volumes.contains(candidate.volume)) volumes.add(candidate.volume);
    _select(candidate.volume, cell);
    draftIsGrow = true;
    return true;
  }

  void cancelDraft() {
    final baseline = sessionBaseline;
    if (baseline != null) {
      volumes
        ..clear()
        ..addAll([for (final volume in baseline) volume.clone()]);
      _nextId = sessionNextId;
    } else {
      final volume = draftVolume;
      final cell = draftCell;
      if (volume != null && cell != null && !volumes.contains(volume)) {
        volume.cells.remove(cell);
        if (volume.cells.isEmpty) {
          volumes.remove(volume);
        }
      }
    }
    _clearDraft();
  }

  /// Ends the placement session. Door picking is skipped.
  bool confirmEdit() {
    if (!_finishSession()) return false;
    draftVolume = null;
    draftCell = null;
    return true;
  }

  /// Commits the open session but keeps [draftVolume] / [draftCell] focused
  /// so transform handles stay available.
  bool commitKeepFocus() {
    return _finishSession();
  }

  bool _finishSession() {
    if (phase != VolumeEditPhase.editing &&
        phase != VolumeEditPhase.pickingAccess) {
      return false;
    }
    final volume = draftVolume;
    if (volume != null && !volumes.contains(volume)) {
      volumes.add(volume);
    }
    draftIsGrow = false;
    phase = VolumeEditPhase.idle;
    sessionTouchedIds.clear();
    sessionBaseline = null;
    sessionNextId = _nextId;
    return true;
  }

  /// Focus an existing cell without opening a cancelable session.
  bool focusAt(int tx, int ty) {
    if (isEditing) commitKeepFocus();
    final volume = volumeAt(tx, ty);
    final cell = volume?.cellAt(tx, ty);
    if (volume == null || cell == null) return false;
    draftVolume = volume;
    draftCell = cell;
    draftIsGrow = false;
    return true;
  }

  void clearFocus() {
    if (isEditing) commitKeepFocus();
    draftVolume = null;
    draftCell = null;
    draftIsGrow = false;
  }

  bool confirmAccess() {
    if (phase == VolumeEditPhase.idle) return true;
    return confirmEdit();
  }

  void toggleAccess(VolumeSide side) {
    final cell = draftCell ??
        (volumes.isEmpty ? null : volumes.last.cells.last);
    if (cell == null) return;
    if (cell.accessibleSides.contains(side)) {
      cell.accessibleSides.remove(side);
      cell.doorOrigins.remove(side);
    } else {
      cell.accessibleSides.add(side);
    }
  }

  /// Place or move a 2×4 door paper on [side] of [cell].
  bool placeDoor({
    required Volume volume,
    required VolumeCell cell,
    required VolumeSide side,
    required int originU,
  }) {
    final live = volume.cellAt(cell.tx, cell.ty);
    if (live == null) return false;
    final faceW = switch (side) {
      VolumeSide.east || VolumeSide.west => live.box.depthSubtiles,
      VolumeSide.north || VolumeSide.south => live.box.widthSubtiles,
    };
    final maxU = faceW - 2;
    if (maxU < 0) return false;
    live.accessibleSides.add(side);
    live.doorOrigins[side] = originU.clamp(0, maxU);
    return true;
  }

  bool removeDoor({
    required Volume volume,
    required VolumeCell cell,
    required VolumeSide side,
  }) {
    final live = volume.cellAt(cell.tx, cell.ty);
    if (live == null) return false;
    final had = live.accessibleSides.remove(side);
    live.doorOrigins.remove(side);
    return had;
  }

  List<VolumeGrowCandidate> growCandidates({
    bool Function(int tx, int ty)? blocked,
  }) {
    if (isEditing) return const [];
    final out = <VolumeGrowCandidate>[];
    for (final volume in volumes) {
      for (final cell in volume.cells) {
        for (final side in VolumeSide.values) {
          final (dx, dy) = side.tileDelta;
          final tx = cell.tx + dx;
          final ty = cell.ty + dy;
          if (!grid.inBounds(tx, ty) || isOccupied(tx, ty)) continue;
          if (blocked?.call(tx, ty) ?? false) continue;
          if (!cell.box.touchesTileEdge(side, grid.subtilesPerTile)) continue;
          out.add(
            VolumeGrowCandidate(
              volume: volume,
              source: cell,
              side: side,
              tx: tx,
              ty: ty,
            ),
          );
        }
      }
    }
    return out;
  }

  /// Remove the committed cell at [tx],[ty]. No-op while a draft is open.
  bool removeCellAt(int tx, int ty) {
    if (isEditing) return false;
    for (final volume in List<Volume>.from(volumes)) {
      final cell = volume.cellAt(tx, ty);
      if (cell == null) continue;
      volume.cells.remove(cell);
      if (volume.cells.isEmpty) volumes.remove(volume);
      return true;
    }
    return false;
  }

  void _clearDraft() {
    draftVolume = null;
    draftCell = null;
    draftIsGrow = false;
    phase = VolumeEditPhase.idle;
    sessionTouchedIds.clear();
    sessionBaseline = null;
    sessionNextId = _nextId;
  }
}
