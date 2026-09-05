import 'package:flutter/material.dart';

import '../walls/wall_regions.dart';
import 'volume.dart';
import 'volume_store.dart';

/// Max chips in a mass-level alert / possession row.
const kMaxProgramChips = 5;

const kProgramCirculation = 'circulation';
const kProgramBedroom = 'bedroom';
const kProgramStorage = 'storage';
const kProgramLeisure = 'leisure';
const kProgramGarden = 'garden';

/// One programmable use. Catalog order is display order.
class ProgramSpec {
  const ProgramSpec({
    required this.id,
    required this.label,
    required this.icon,
    required this.color,
    this.indoor = false,
    this.outdoor = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final Color color;
  final bool indoor;
  final bool outdoor;
}

/// Ordered catalog. Append new programs; do not reorder existing IDs.
const List<ProgramSpec> kProgramCatalog = [
  ProgramSpec(
    id: kProgramCirculation,
    label: 'Circulation',
    icon: Icons.directions_walk,
    color: Color(0xFF9E9E9E),
    indoor: true,
    outdoor: true,
  ),
  ProgramSpec(
    id: kProgramBedroom,
    label: 'Bedroom',
    icon: Icons.bed_outlined,
    color: Color(0xFFEC407A),
    indoor: true,
  ),
  ProgramSpec(
    id: kProgramStorage,
    label: 'Storage',
    icon: Icons.inventory_2_outlined,
    color: Color(0xFF42A5F5),
    indoor: true,
  ),
  ProgramSpec(
    id: kProgramLeisure,
    label: 'Leisure',
    icon: Icons.weekend_outlined,
    color: Color(0xFFFDD835),
    indoor: true,
    outdoor: true,
  ),
  ProgramSpec(
    id: kProgramGarden,
    label: 'Garden',
    icon: Icons.yard_outlined,
    color: Color(0xFF66BB6A),
    outdoor: true,
  ),
];

ProgramSpec? programById(String id) {
  for (final spec in kProgramCatalog) {
    if (spec.id == id) return spec;
  }
  return null;
}

bool isKnownProgram(String id) => programById(id) != null;

List<ProgramSpec> programsForSurface({required bool outdoor}) {
  return [
    for (final spec in kProgramCatalog)
      if (outdoor ? spec.outdoor : spec.indoor) spec,
  ];
}

/// Unique IDs from [ids], sorted by catalog order, capped at [kMaxProgramChips].
List<ProgramSpec> sortProgramsByCatalog(Iterable<String> ids) {
  final set = ids.toSet();
  final out = <ProgramSpec>[];
  for (final spec in kProgramCatalog) {
    if (!set.contains(spec.id)) continue;
    out.add(spec);
    if (out.length >= kMaxProgramChips) break;
  }
  return out;
}

/// Per-tile indoor and outdoor program assignments.
///
/// Indoor cells have no default (null = unprogrammed). Outdoor tiles default
/// to circulation when missing.
class VolumeProgramStore {
  VolumeProgramStore();

  final Map<(int, int), String> _indoor = {};
  final Map<(int, int), String> _outdoor = {};

  Map<(int, int), String> get indoorAssignments =>
      Map<(int, int), String>.unmodifiable(_indoor);

  Map<(int, int), String> get outdoorAssignments =>
      Map<(int, int), String>.unmodifiable(_outdoor);

  String? indoorAt(int tx, int ty) => _indoor[(tx, ty)];

  /// Outdoor program, defaulting to circulation.
  String outdoorAt(int tx, int ty) =>
      _outdoor[(tx, ty)] ?? kProgramCirculation;

  bool assignIndoor({
    required int tx,
    required int ty,
    required String programId,
  }) {
    final spec = programById(programId);
    if (spec == null || !spec.indoor) return false;
    _indoor[(tx, ty)] = programId;
    return true;
  }

  /// Assign [programId] to one cell. The first program on a mass also fills
  /// every other unprogrammed cell with circulation.
  bool assignIndoorInVolume({
    required Volume volume,
    required int tx,
    required int ty,
    required String programId,
  }) {
    if (volume.cellAt(tx, ty) == null) return false;
    final first = !isVolumeProgrammed(volume);
    if (!assignIndoor(tx: tx, ty: ty, programId: programId)) return false;
    if (!first) return true;
    for (final cell in volume.cells) {
      if (cell.tx == tx && cell.ty == ty) continue;
      if (_indoor.containsKey((cell.tx, cell.ty))) continue;
      assignIndoor(
        tx: cell.tx,
        ty: cell.ty,
        programId: kProgramCirculation,
      );
    }
    return true;
  }

  bool clearIndoor(int tx, int ty) => _indoor.remove((tx, ty)) != null;

  bool assignOutdoorRegion(Iterable<(int, int)> tiles, String programId) {
    final spec = programById(programId);
    if (spec == null || !spec.outdoor) return false;
    if (programId == kProgramCirculation) {
      for (final tile in tiles) {
        _outdoor.remove(tile);
      }
    } else {
      for (final tile in tiles) {
        _outdoor[tile] = programId;
      }
    }
    return true;
  }

  /// Dominant outdoor program for [tiles] (majority, catalog-order ties).
  String outdoorRegionProgram(Iterable<(int, int)> tiles) {
    final counts = <String, int>{};
    for (final tile in tiles) {
      final id = outdoorAt(tile.$1, tile.$2);
      counts[id] = (counts[id] ?? 0) + 1;
    }
    if (counts.isEmpty) return kProgramCirculation;
    String? best;
    var bestCount = -1;
    for (final spec in kProgramCatalog) {
      final n = counts[spec.id] ?? 0;
      if (n > bestCount) {
        best = spec.id;
        bestCount = n;
      }
    }
    return best ?? kProgramCirculation;
  }

  bool isVolumeProgrammed(Volume volume) {
    for (final cell in volume.cells) {
      if (_indoor.containsKey((cell.tx, cell.ty))) return true;
    }
    return false;
  }

  bool canAssignToVolume(Volume volume) => volume.cells.isNotEmpty;

  List<ProgramSpec> programsPossessed(Volume volume) {
    return sortProgramsByCatalog([
      for (final cell in volume.cells) ?_indoor[(cell.tx, cell.ty)],
    ]);
  }

  List<ProgramSpec> programsPossessedRegion(WallRegion region) {
    return sortProgramsByCatalog({
      for (final tile in region.tiles) outdoorAt(tile.$1, tile.$2),
    });
  }

  void remapVolumeTiles(Volume volume, int dtx, int dty) {
    if (dtx == 0 && dty == 0) return;
    final oldTiles = <(int, int)>[
      for (final cell in volume.cells) (cell.tx - dtx, cell.ty - dty),
    ];
    _remapMap(_indoor, dtx, dty, oldTiles);
    _remapMap(_outdoor, dtx, dty, oldTiles);
  }

  /// No-op: assignments are keyed by tile, not volume id.
  void rekeyVolume(int fromId, int toId) {}

  void prune(VolumeStore store) {
    _indoor.removeWhere((tile, _) {
      final volume = store.volumeAt(tile.$1, tile.$2);
      return volume == null || volume.cellAt(tile.$1, tile.$2) == null;
    });
  }

  void restore({
    required Map<(int, int), String> indoor,
    required Map<(int, int), String> outdoor,
  }) {
    _indoor
      ..clear()
      ..addAll(indoor);
    _outdoor
      ..clear()
      ..addAll(outdoor);
  }

  VolumeProgramStore copy() {
    final next = VolumeProgramStore();
    next.restore(
      indoor: Map<(int, int), String>.from(_indoor),
      outdoor: Map<(int, int), String>.from(_outdoor),
    );
    return next;
  }

  void restoreFrom(VolumeProgramStore other) {
    restore(
      indoor: Map<(int, int), String>.from(other._indoor),
      outdoor: Map<(int, int), String>.from(other._outdoor),
    );
  }
}

void _remapMap(
  Map<(int, int), String> map,
  int dtx,
  int dty,
  Iterable<(int, int)> oldTiles,
) {
  final moving = <(int, int), String>{};
  for (final tile in oldTiles) {
    final id = map.remove(tile);
    if (id != null) {
      moving[(tile.$1 + dtx, tile.$2 + dty)] = id;
    }
  }
  map.addAll(moving);
}
