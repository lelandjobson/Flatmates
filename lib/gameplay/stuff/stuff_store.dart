import '../volumes/volume.dart';
import 'stuff_instance.dart';

/// Session store of placed interior stuff.
class StuffStore {
  final List<StuffInstance> items = [];
  int _nextId = 1;

  StuffInstance? byId(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  String nextId() => '$_nextId';

  void add(StuffInstance instance) {
    items.add(instance);
    final parsed = int.tryParse(instance.id);
    if (parsed != null && parsed >= _nextId) _nextId = parsed + 1;
  }

  bool remove(String id) {
    final before = items.length;
    items.removeWhere((item) => item.id == id);
    return items.length != before;
  }

  void removeInVolume(int volumeId) {
    items.removeWhere((item) => item.volumeId == volumeId);
  }

  void remapVolumeTiles(Volume volume, int dtx, int dty, double tileSize) {
    if (dtx == 0 && dty == 0) return;
    for (final item in items) {
      if (item.volumeId != volume.id) continue;
      item.tx += dtx;
      item.ty += dty;
      item.origin.x += dtx * tileSize;
      item.origin.z += dty * tileSize;
    }
  }

  List<StuffInstance> inTiles(Iterable<(int, int)> tiles) {
    final set = tiles is Set<(int, int)> ? tiles : {...tiles};
    return [
      for (final item in items)
        if (set.contains((item.tx, item.ty))) item,
    ];
  }

  List<StuffInstance> inVolume(Volume volume) {
    final tiles = {for (final cell in volume.cells) (cell.tx, cell.ty)};
    return [
      for (final item in items)
        if (item.volumeId == volume.id || tiles.contains((item.tx, item.ty)))
          item,
    ];
  }

  List<StuffInstance> activeInTiles(
    Iterable<(int, int)> tiles,
    bool Function(StuffInstance item) isValid,
  ) {
    return [
      for (final item in inTiles(tiles))
        if (isValid(item)) item,
    ];
  }

  int paperCost() {
    var sum = 0;
    for (final item in items) {
      sum += item.spec?.paperCost ?? 0;
    }
    return sum;
  }

  StuffStore copy() {
    final next = StuffStore();
    next._nextId = _nextId;
    next.items.addAll([for (final item in items) item.clone()]);
    return next;
  }

  void restoreFrom(StuffStore other) {
    items
      ..clear()
      ..addAll([for (final item in other.items) item.clone()]);
    _nextId = other._nextId;
  }
}
