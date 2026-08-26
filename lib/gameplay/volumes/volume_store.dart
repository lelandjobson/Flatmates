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

  int _nextId = 1;
  int get nextId => _nextId;

  void restore({
    required List<Volume> volumes,
    Volume? draftVolume,
    VolumeCell? draftCell,
    required bool draftIsGrow,
    required VolumeEditPhase phase,
    required int nextId,
  }) {
    this.volumes
      ..clear()
      ..addAll(volumes);
    this.draftVolume = draftVolume;
    this.draftCell = draftCell;
    this.draftIsGrow = draftIsGrow;
    this.phase = phase;
    _nextId = nextId;
  }

  bool get isEditing =>
      phase == VolumeEditPhase.editing || phase == VolumeEditPhase.pickingAccess;

  /// The first committed volume needs an outdoor door. Later volumes do not.
  bool get requiresAccessibleSide => volumes.isEmpty;

  Iterable<Volume> get visibleVolumes sync* {
    yield* volumes;
    final draft = draftVolume;
    if (draft != null && !volumes.contains(draft)) yield draft;
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

  /// Shift every cell of [volume] by [dtx],[dty] if destinations are free.
  ///
  /// Destinations must be in bounds, not occupied by another volume, and not
  /// rejected by [blocked] (typically path tiles). Cells of [volume] may
  /// overlap their own current footprint.
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
      );
    }
    return true;
  }

  bool startNew(int tx, int ty) {
    if (!grid.inBounds(tx, ty) || isOccupied(tx, ty) || isEditing) return false;
    final cell = VolumeCell(tx: tx, ty: ty, box: BoxPrimitive());
    final volume = Volume(id: _nextId++, cells: [cell]);
    draftVolume = volume;
    draftCell = cell;
    draftIsGrow = false;
    phase = VolumeEditPhase.editing;
    return true;
  }

  bool startGrow(VolumeGrowCandidate candidate) {
    if (isEditing) return false;
    if (!grid.inBounds(candidate.tx, candidate.ty)) return false;
    if (isOccupied(candidate.tx, candidate.ty)) return false;
    final cell = VolumeCell(
      tx: candidate.tx,
      ty: candidate.ty,
      box: BoxPrimitive(),
    );
    candidate.volume.cells.add(cell);
    draftVolume = candidate.volume;
    draftCell = cell;
    draftIsGrow = true;
    phase = VolumeEditPhase.editing;
    return true;
  }

  void cancelDraft() {
    final volume = draftVolume;
    final cell = draftCell;
    if (volume != null && cell != null) {
      volume.cells.remove(cell);
      if (volume.cells.isEmpty) {
        volumes.remove(volume);
      }
    }
    _clearDraft();
  }

  /// Grow commits immediately. New volumes go to the door-picking step.
  bool confirmEdit() {
    if (phase != VolumeEditPhase.editing) return false;
    final volume = draftVolume;
    if (volume == null) return false;
    if (draftIsGrow) {
      if (!volumes.contains(volume)) volumes.add(volume);
      _clearDraft();
      return true;
    }
    phase = VolumeEditPhase.pickingAccess;
    return true;
  }

  bool confirmAccess() {
    if (phase != VolumeEditPhase.pickingAccess) return false;
    final volume = draftVolume;
    final cell = draftCell;
    if (volume == null || cell == null) return false;
    if (requiresAccessibleSide && cell.accessibleSides.isEmpty) return false;
    if (!volumes.contains(volume)) volumes.add(volume);
    _clearDraft();
    return true;
  }

  void toggleAccess(VolumeSide side) {
    final cell = draftCell;
    if (cell == null || phase != VolumeEditPhase.pickingAccess) return;
    if (cell.accessibleSides.contains(side)) {
      cell.accessibleSides.remove(side);
    } else {
      cell.accessibleSides.add(side);
    }
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
  }
}
