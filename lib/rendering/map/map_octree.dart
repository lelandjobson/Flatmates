import 'package:vector_math/vector_math_64.dart';

import 'map_aabb.dart';

/// Tile-aligned octree. Leaves stop near [minLeafSize] (typically one tile).
class MapOctree {
  MapOctree({required MapAabb bounds, required this.minLeafSize})
      : _root = _OctreeNode(bounds);

  final double minLeafSize;
  final _OctreeNode _root;
  final Map<int, MapAabb> _boundsById = {};

  int get count => _boundsById.length;

  void insert(int id, MapAabb bounds) {
    remove(id);
    _boundsById[id] = bounds;
    _insert(_root, id, bounds);
  }

  void remove(int id) {
    final bounds = _boundsById.remove(id);
    if (bounds == null) return;
    _remove(_root, id, bounds);
  }

  List<int> query(MapAabb region) {
    final out = <int>{};
    _query(_root, region, out);
    return out.toList(growable: false);
  }

  void _insert(_OctreeNode node, int id, MapAabb bounds) {
    if (node.children != null) {
      for (final child in node.children!) {
        if (child.bounds.intersects(bounds)) {
          _insert(child, id, bounds);
        }
      }
      return;
    }
    node.items.add((id, bounds));
    if (node.items.length > _OctreeNode.capacity &&
        node.bounds.longest > minLeafSize * 1.5) {
      _subdivide(node);
    }
  }

  void _subdivide(_OctreeNode node) {
    final c = node.bounds.center;
    final min = node.bounds.min;
    final max = node.bounds.max;
    node.children = [
      _OctreeNode(MapAabb(min, c)),
      _OctreeNode(MapAabb(Vector3(c.x, min.y, min.z), Vector3(max.x, c.y, c.z))),
      _OctreeNode(MapAabb(Vector3(min.x, c.y, min.z), Vector3(c.x, max.y, c.z))),
      _OctreeNode(MapAabb(Vector3(c.x, c.y, min.z), Vector3(max.x, max.y, c.z))),
      _OctreeNode(MapAabb(Vector3(min.x, min.y, c.z), Vector3(c.x, c.y, max.z))),
      _OctreeNode(MapAabb(Vector3(c.x, min.y, c.z), Vector3(max.x, c.y, max.z))),
      _OctreeNode(MapAabb(Vector3(min.x, c.y, c.z), Vector3(c.x, max.y, max.z))),
      _OctreeNode(MapAabb(c, max)),
    ];
    final moving = List<(int, MapAabb)>.from(node.items);
    node.items.clear();
    for (final item in moving) {
      _insert(node, item.$1, item.$2);
    }
  }

  bool _remove(_OctreeNode node, int id, MapAabb bounds) {
    if (!node.bounds.intersects(bounds)) return false;
    var removed = false;
    if (node.children != null) {
      for (final child in node.children!) {
        removed = _remove(child, id, bounds) || removed;
      }
      return removed;
    }
    final before = node.items.length;
    node.items.removeWhere((item) => item.$1 == id);
    return node.items.length != before;
  }

  void _query(_OctreeNode node, MapAabb region, Set<int> out) {
    if (!node.bounds.intersects(region)) return;
    if (node.children != null) {
      for (final child in node.children!) {
        _query(child, region, out);
      }
      return;
    }
    for (final item in node.items) {
      if (item.$2.intersects(region)) out.add(item.$1);
    }
  }
}

class _OctreeNode {
  _OctreeNode(this.bounds);

  static const int capacity = 4;

  final MapAabb bounds;
  final List<(int, MapAabb)> items = [];
  List<_OctreeNode>? children;
}
