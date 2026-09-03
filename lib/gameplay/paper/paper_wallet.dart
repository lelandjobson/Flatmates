import 'package:flutter/foundation.dart';

import '../paths/path_store.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_store.dart';
import 'paper_cost.dart';

/// Held sheets plus per-construct committed costs.
///
/// [settle] snaps committed values to the current ceil(cost) so bouncing
/// around a rounding boundary cannot mint paper.
class PaperWallet extends ChangeNotifier {
  PaperWallet({int held = kStartingPaper}) : _held = held;

  int _held;
  final Map<int, int> volumeCommitted = {};
  int pathCommitted = 0;
  int wallCommitted = 0;

  int get held => _held;

  PaperWallet copy() {
    final next = PaperWallet(held: _held);
    next.volumeCommitted.addAll(volumeCommitted);
    next.pathCommitted = pathCommitted;
    next.wallCommitted = wallCommitted;
    return next;
  }

  void restoreFrom(PaperWallet other) {
    _held = other._held;
    volumeCommitted
      ..clear()
      ..addAll(other.volumeCommitted);
    pathCommitted = other.pathCommitted;
    wallCommitted = other.wallCommitted;
    notifyListeners();
  }

  /// Apply [next] committed map. Returns false and leaves state unchanged
  /// when the wallet cannot cover the extra spend.
  bool settleVolumes(Map<int, int> next) {
    return _settleMap(volumeCommitted, next);
  }

  bool settlePath(int next) => _settleScalar(() => pathCommitted, (v) {
        pathCommitted = v;
      }, next);

  bool settleWalls(int next) => _settleScalar(() => wallCommitted, (v) {
        wallCommitted = v;
      }, next);

  /// Recompute every construct from the live stores.
  bool settleWorld({
    required VolumeStore volumes,
    required PathStore paths,
    required WallStore walls,
  }) {
    final volumeCosts = <int, int>{
      for (final volume in volumes.visibleVolumes)
        volume.id: volumePaperCost(volume, volumes.grid),
    };
    final pathCost = pathPaperCost(paths, subtilesPerTile: volumes.grid.subtilesPerTile);
    final wallCost = wallPaperCost(walls.edges.length);

    final backup = copy();
    if (!settleVolumes(volumeCosts) ||
        !settlePath(pathCost) ||
        !settleWalls(wallCost)) {
      restoreFrom(backup);
      return false;
    }
    return true;
  }

  bool _settleMap(Map<int, int> current, Map<int, int> next) {
    var need = 0;
    var refund = 0;
    for (final entry in next.entries) {
      final prior = current[entry.key] ?? 0;
      if (entry.value > prior) {
        need += entry.value - prior;
      } else {
        refund += prior - entry.value;
      }
    }
    for (final entry in current.entries) {
      if (!next.containsKey(entry.key)) refund += entry.value;
    }
    if (_held + refund < need) return false;
    _held = _held + refund - need;
    current
      ..clear()
      ..addAll(next);
    notifyListeners();
    return true;
  }

  bool _settleScalar(int Function() read, void Function(int) write, int next) {
    final prior = read();
    final need = next > prior ? next - prior : 0;
    final refund = next < prior ? prior - next : 0;
    if (_held + refund < need) return false;
    _held = _held + refund - need;
    write(next);
    notifyListeners();
    return true;
  }
}
