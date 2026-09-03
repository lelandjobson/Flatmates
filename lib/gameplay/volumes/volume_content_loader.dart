import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import 'volume.dart';
import 'volume_store.dart';

/// One stored box / tile of a volume mass. Joined volumes have many parts.
@immutable
class VolumePartId {
  const VolumePartId(this.tx, this.ty);

  final int tx;
  final int ty;

  /// The part under [lookAt], or null when that tile has no volume.
  static VolumePartId? atLookAt(VolumeStore volumes, Vector3 lookAt) {
    final tile = volumes.grid.tileAtWorld(lookAt);
    if (tile == null) return null;
    if (volumes.volumeAt(tile.$1, tile.$2) == null) return null;
    return VolumePartId(tile.$1, tile.$2);
  }

  @override
  bool operator ==(Object other) =>
      other is VolumePartId && other.tx == tx && other.ty == ty;

  @override
  int get hashCode => Object.hash(tx, ty);

  @override
  String toString() => 'VolumePartId($tx, $ty)';
}

/// Placeholder wait: a uniform random delay in `[0, 1.5]` seconds.
const Duration kDummyVolumeContentLoadMax = Duration(milliseconds: 1500);

final math.Random _dummyLoadRandom = math.Random();

/// Mock wait for [loadVolumePartContents]: uniform in `[0, 1.5]` seconds.
Duration dummyVolumeContentLoadDelay(math.Random random) {
  final ms = (random.nextDouble() * kDummyVolumeContentLoadMax.inMilliseconds)
      .round();
  return Duration(milliseconds: ms);
}

/// Architectural hook: load every model that lives inside [part].
///
/// Mock stand-in until the real interior-model pipeline exists. Completes
/// after a random delay so the ceiling can wait on a [Future].
Future<void> loadVolumePartContents(
  VolumePartId part, {
  math.Random? random,
}) async {
  final delay = dummyVolumeContentLoadDelay(random ?? _dummyLoadRandom);
  if (delay <= Duration.zero) return;
  await Future<void>.delayed(delay);
}

typedef VolumePartContentLoad = Future<void> Function(VolumePartId part);

const _kNeighborDeltas = <(int, int)>[
  (-1, -1),
  (0, -1),
  (1, -1),
  (-1, 0),
  (1, 0),
  (-1, 1),
  (0, 1),
  (1, 1),
];

/// Edge- and corner-adjacent volume parts, nearest [cursor] first.
List<VolumePartId> adjacentVolumeParts({
  required VolumeStore volumes,
  required VolumePartId origin,
  required Vector3 cursor,
}) {
  final parts = <VolumePartId>[];
  for (final (dx, dy) in _kNeighborDeltas) {
    final tx = origin.tx + dx;
    final ty = origin.ty + dy;
    if (volumes.volumeAt(tx, ty) == null) continue;
    parts.add(VolumePartId(tx, ty));
  }
  parts.sort((a, b) {
    final da = _xzDistance(volumes.grid.tileCenter(a.tx, a.ty), cursor);
    final db = _xzDistance(volumes.grid.tileCenter(b.tx, b.ty), cursor);
    final cmp = da.compareTo(db);
    if (cmp != 0) return cmp;
    final tx = a.tx.compareTo(b.tx);
    return tx != 0 ? tx : a.ty.compareTo(b.ty);
  });
  return parts;
}

double _xzDistance(Vector3 a, Vector3 b) {
  final dx = a.x - b.x;
  final dz = a.z - b.z;
  return dx * dx + dz * dz;
}

/// Priority queue that loads a focused part and its neighbors.
class VolumeContentLoader extends ChangeNotifier {
  VolumeContentLoader({
    VolumePartContentLoad? loadPart,
    this.maxConcurrent = 9,
  }) : _loadPart = loadPart ?? loadVolumePartContents;

  final VolumePartContentLoad _loadPart;
  final int maxConcurrent;

  final Set<VolumePartId> _loaded = {};
  final Set<VolumePartId> _loading = {};
  final List<VolumePartId> _queue = [];
  int _inFlight = 0;

  bool isLoaded(VolumePartId part) => _loaded.contains(part);
  bool isLoading(VolumePartId part) => _loading.contains(part);
  bool isQueued(VolumePartId part) => _queue.contains(part);

  List<VolumePartId> get queued => List<VolumePartId>.unmodifiable(_queue);

  /// Enqueue [focus] first, then [neighbors] (already distance-sorted).
  void request({
    required VolumePartId focus,
    required List<VolumePartId> neighbors,
  }) {
    _enqueue(focus, toFront: true);
    for (final neighbor in neighbors) {
      _enqueue(neighbor, toFront: false);
    }
    _pump();
  }

  void _enqueue(VolumePartId part, {required bool toFront}) {
    if (_loaded.contains(part) || _loading.contains(part)) return;
    _queue.remove(part);
    if (toFront) {
      _queue.insert(0, part);
    } else {
      _queue.add(part);
    }
  }

  void _pump() {
    while (_inFlight < maxConcurrent && _queue.isNotEmpty) {
      final part = _queue.removeAt(0);
      _loading.add(part);
      _inFlight++;
      unawaited(_run(part));
    }
  }

  Future<void> _run(VolumePartId part) async {
    try {
      await _loadPart(part);
      _loaded.add(part);
    } finally {
      _loading.remove(part);
      _inFlight--;
      notifyListeners();
      _pump();
    }
  }
}
