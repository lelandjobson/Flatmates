import 'package:vector_math/vector_math_64.dart';

/// Axis-aligned box used by [MapOctree] queries.
class MapAabb {
  const MapAabb(this.min, this.max);

  final Vector3 min;
  final Vector3 max;

  bool intersects(MapAabb other) {
    return min.x <= other.max.x &&
        max.x >= other.min.x &&
        min.y <= other.max.y &&
        max.y >= other.min.y &&
        min.z <= other.max.z &&
        max.z >= other.min.z;
  }

  Vector3 get center => Vector3(
        (min.x + max.x) * 0.5,
        (min.y + max.y) * 0.5,
        (min.z + max.z) * 0.5,
      );

  Vector3 get extent => max - min;

  double get longest {
    final e = extent;
    final a = e.x.abs();
    final b = e.y.abs();
    final c = e.z.abs();
    return a > b ? (a > c ? a : c) : (b > c ? b : c);
  }

  /// Ground tile box: XZ from map origin, Y from 0 to [height].
  static MapAabb tile({
    required int tx,
    required int ty,
    required double tileSize,
    required double mapHalf,
    double height = 20,
  }) {
    final x0 = -mapHalf + tx * tileSize;
    final z0 = -mapHalf + ty * tileSize;
    return MapAabb(
      Vector3(x0, 0, z0),
      Vector3(x0 + tileSize, height, z0 + tileSize),
    );
  }

  static MapAabb tiles({
    required int tx0,
    required int ty0,
    required int tx1,
    required int ty1,
    required double tileSize,
    required double mapHalf,
    double height = 20,
  }) {
    final x0 = -mapHalf + tx0 * tileSize;
    final z0 = -mapHalf + ty0 * tileSize;
    final x1 = -mapHalf + (tx1 + 1) * tileSize;
    final z1 = -mapHalf + (ty1 + 1) * tileSize;
    return MapAabb(Vector3(x0, 0, z0), Vector3(x1, height, z1));
  }
}
