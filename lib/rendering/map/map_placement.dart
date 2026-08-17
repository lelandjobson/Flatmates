import 'package:vector_math/vector_math_64.dart';

/// A craft instance sitting on one map tile, whether or not it is drawn.
class MapPlacement {
  const MapPlacement({
    required this.id,
    required this.tx,
    required this.ty,
    required this.craftName,
    required this.origin,
  });

  final int id;
  final int tx;
  final int ty;
  final String craftName;
  final Vector3 origin;
}
