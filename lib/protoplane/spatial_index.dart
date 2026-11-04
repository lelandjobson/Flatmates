import 'package:vector_math/vector_math_64.dart';

import '../rendering/map/map_aabb.dart';

export '../rendering/map/map_aabb.dart';

/// Immutable, median-split BVH. Each entry occurs once, including flat or long
/// surfaces which would be duplicated across many octree cells. Queries are
/// broad phase only: callers still test actual geometry.
class CraftSpatialIndex<T> {
  CraftSpatialIndex(Map<T, MapAabb> bounds)
    : _root = bounds.isEmpty ? null : _Node.build(bounds.entries.toList());

  final _Node<T>? _root;

  Iterable<T> query(MapAabb bounds) sync* {
    final pending = <_Node<T>>[if (_root != null) _root];
    while (pending.isNotEmpty) {
      final node = pending.removeLast();
      if (!node.bounds.intersects(bounds)) continue;
      if (node.left != null) {
        pending.add(node.left!);
        pending.add(node.right!);
      } else {
        for (final entry in node.entries) {
          if (entry.value.intersects(bounds)) yield entry.key;
        }
      }
    }
  }
}

MapAabb craftBounds(Iterable<Vector3> points, {double padding = 0}) {
  final iterator = points.iterator;
  if (!iterator.moveNext()) throw ArgumentError('Bounds need a point');
  final min = iterator.current.clone(), max = iterator.current.clone();
  while (iterator.moveNext()) {
    Vector3.min(min, iterator.current, min);
    Vector3.max(max, iterator.current, max);
  }
  final margin = Vector3.all(padding);
  return MapAabb(min - margin, max + margin);
}

class _Node<T> {
  _Node(this.bounds, this.entries, [this.left, this.right]);

  static _Node<T> build<T>(List<MapEntry<T, MapAabb>> entries) {
    final bounds = craftBounds(
      entries.expand((e) => [e.value.min, e.value.max]),
    );
    if (entries.length <= 8) return _Node(bounds, entries);
    final extent = bounds.extent;
    final axis = extent.x >= extent.y && extent.x >= extent.z
        ? 0
        : extent.y >= extent.z
        ? 1
        : 2;
    entries.sort(
      (a, b) => (a.value.min[axis] + a.value.max[axis]).compareTo(
        b.value.min[axis] + b.value.max[axis],
      ),
    );
    final middle = entries.length ~/ 2;
    return _Node(
      bounds,
      const [],
      build(entries.sublist(0, middle)),
      build(entries.sublist(middle)),
    );
  }

  final MapAabb bounds;
  final List<MapEntry<T, MapAabb>> entries;
  final _Node<T>? left, right;
}
