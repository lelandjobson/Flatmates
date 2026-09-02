import 'volume.dart';
import 'volume_store.dart';

/// Floor programs placed as 6×6 paper stamps. Circulation is leftover floor.
enum VolumeProgramKind { bedroom, common }

extension VolumeProgramKindVisual on VolumeProgramKind {
  /// Almost-white paper tint.
  int get paperArgb => switch (this) {
        VolumeProgramKind.bedroom => 0xFFFFF2F4,
        VolumeProgramKind.common => 0xFFF2F6FF,
      };

  String get label => switch (this) {
        VolumeProgramKind.bedroom => 'Bedroom',
        VolumeProgramKind.common => 'Common',
      };
}

/// One program paper on a volume-cell floor. Size is always [sizeSubtiles].
class ProgramStamp {
  ProgramStamp({
    required this.id,
    required this.volumeId,
    required this.tx,
    required this.ty,
    required this.originU,
    required this.originV,
    required this.kind,
  });

  static const int sizeSubtiles = 6;

  final int id;
  final int volumeId;
  final int tx;
  final int ty;
  final int originU;
  final int originV;
  final VolumeProgramKind kind;

  int get width => sizeSubtiles;
  int get height => sizeSubtiles;

  bool overlaps(ProgramStamp other) {
    if (volumeId != other.volumeId || tx != other.tx || ty != other.ty) {
      return false;
    }
    return originU < other.originU + other.width &&
        originU + width > other.originU &&
        originV < other.originV + other.height &&
        originV + height > other.originV;
  }

  bool fits(BoxPrimitive box) {
    return originU >= 0 &&
        originV >= 0 &&
        originU + width <= box.widthSubtiles &&
        originV + height <= box.depthSubtiles;
  }

  ProgramStamp clone() => ProgramStamp(
        id: id,
        volumeId: volumeId,
        tx: tx,
        ty: ty,
        originU: originU,
        originV: originV,
        kind: kind,
      );
}

/// Floor program stamps. A volume may hold a program once it is a committed
/// mass with a floor large enough for a 6×6 stamp.
class VolumeProgramStore {
  VolumeProgramStore();

  final List<ProgramStamp> stamps = [];
  int _nextId = 1;
  int get nextId => _nextId;

  void restore({
    required List<ProgramStamp> stamps,
    required int nextId,
  }) {
    this.stamps
      ..clear()
      ..addAll(stamps);
    _nextId = nextId;
  }

  Iterable<ProgramStamp> stampsOn({
    required int volumeId,
    int? tx,
    int? ty,
  }) sync* {
    for (final stamp in stamps) {
      if (stamp.volumeId != volumeId) continue;
      if (tx != null && stamp.tx != tx) continue;
      if (ty != null && stamp.ty != ty) continue;
      yield stamp;
    }
  }

  bool canAssignProgram(VolumeCell cell) {
    return cell.box.widthSubtiles >= ProgramStamp.sizeSubtiles &&
        cell.box.depthSubtiles >= ProgramStamp.sizeSubtiles;
  }

  bool canAssignToVolume(Volume volume) =>
      volume.cells.any(canAssignProgram);

  bool canPlace({
    required Volume volume,
    required VolumeCell cell,
    required int originU,
    required int originV,
    int? ignoreStampId,
  }) {
    if (volume.cellAt(cell.tx, cell.ty) == null) return false;
    if (!canAssignProgram(cell)) return false;
    final stamp = ProgramStamp(
      id: -1,
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      originU: originU,
      originV: originV,
      kind: VolumeProgramKind.bedroom,
    );
    if (!stamp.fits(cell.box)) return false;
    for (final other in stampsOn(volumeId: volume.id, tx: cell.tx, ty: cell.ty)) {
      if (ignoreStampId != null && other.id == ignoreStampId) continue;
      if (stamp.overlaps(other)) return false;
    }
    return true;
  }

  /// Snap a floor click into a valid 6×6 origin, or null if it cannot fit.
  (int u, int v)? snapOrigin({
    required VolumeCell cell,
    required int u,
    required int v,
    int? volumeId,
  }) {
    final maxU = cell.box.widthSubtiles - ProgramStamp.sizeSubtiles;
    final maxV = cell.box.depthSubtiles - ProgramStamp.sizeSubtiles;
    if (maxU < 0 || maxV < 0) return null;
    final preferredU = u.clamp(0, maxU);
    final preferredV = v.clamp(0, maxV);
    bool blocked(int ou, int ov) {
      if (volumeId == null) return false;
      final probe = ProgramStamp(
        id: -1,
        volumeId: volumeId,
        tx: cell.tx,
        ty: cell.ty,
        originU: ou,
        originV: ov,
        kind: VolumeProgramKind.bedroom,
      );
      for (final other in stampsOn(
        volumeId: volumeId,
        tx: cell.tx,
        ty: cell.ty,
      )) {
        if (probe.overlaps(other)) return true;
      }
      return false;
    }

    if (!blocked(preferredU, preferredV)) return (preferredU, preferredV);
    (int, int)? best;
    var bestDist = 1 << 30;
    for (var ou = 0; ou <= maxU; ou++) {
      for (var ov = 0; ov <= maxV; ov++) {
        if (blocked(ou, ov)) continue;
        final dist = (ou - preferredU).abs() + (ov - preferredV).abs();
        if (dist < bestDist) {
          bestDist = dist;
          best = (ou, ov);
        }
      }
    }
    return best;
  }

  ProgramStamp? place({
    required Volume volume,
    required VolumeCell cell,
    required int originU,
    required int originV,
    required VolumeProgramKind kind,
  }) {
    if (!canPlace(
      volume: volume,
      cell: cell,
      originU: originU,
      originV: originV,
    )) {
      return null;
    }
    final stamp = ProgramStamp(
      id: _nextId++,
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      originU: originU,
      originV: originV,
      kind: kind,
    );
    stamps.add(stamp);
    return stamp;
  }

  bool remove(int id) {
    final before = stamps.length;
    stamps.removeWhere((s) => s.id == id);
    return stamps.length < before;
  }

  void remapVolumeTiles(int volumeId, int dtx, int dty) {
    if (dtx == 0 && dty == 0) return;
    for (var i = 0; i < stamps.length; i++) {
      final s = stamps[i];
      if (s.volumeId != volumeId) continue;
      stamps[i] = ProgramStamp(
        id: s.id,
        volumeId: s.volumeId,
        tx: s.tx + dtx,
        ty: s.ty + dty,
        originU: s.originU,
        originV: s.originV,
        kind: s.kind,
      );
    }
  }

  void rekeyVolume(int fromId, int toId) {
    if (fromId == toId) return;
    for (var i = 0; i < stamps.length; i++) {
      final s = stamps[i];
      if (s.volumeId != fromId) continue;
      stamps[i] = ProgramStamp(
        id: s.id,
        volumeId: toId,
        tx: s.tx,
        ty: s.ty,
        originU: s.originU,
        originV: s.originV,
        kind: s.kind,
      );
    }
  }

  void prune(VolumeStore store) {
    stamps.removeWhere((s) {
      final volume = store.volumeById(s.volumeId);
      if (volume == null) return true;
      return volume.cellAt(s.tx, s.ty) == null;
    });
  }

  VolumeProgramStore copy() {
    final next = VolumeProgramStore();
    next.restore(
      stamps: [for (final s in stamps) s.clone()],
      nextId: _nextId,
    );
    return next;
  }

  void restoreFrom(VolumeProgramStore other) {
    restore(
      stamps: [for (final s in other.stamps) s.clone()],
      nextId: other._nextId,
    );
  }
}
