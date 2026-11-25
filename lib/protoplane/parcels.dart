import 'dart:ui';
import 'layered_terrain.dart';

/// Parcel coordinates remain stable when the devtools side length changes.
class ParcelId {
  const ParcelId(this.x, this.y);
  final int x, y;
  String get key => '$x,$y';
  @override
  bool operator ==(Object other) =>
      other is ParcelId && x == other.x && y == other.y;
  @override
  int get hashCode => Object.hash(x, y);
}

class WorldParcels {
  WorldParcels({this.size = 3, Iterable<ParcelId> purchased = const []})
    : purchased = {const ParcelId(0, 0), ...purchased} {
    if (size < 1 || size > 12) {
      throw const FormatException('Invalid parcel size');
    }
  }
  final int size;
  final Set<ParcelId> purchased;
  int get price => size * size * 100;
  int get origin => -(size ~/ 2);
  ParcelId at(Offset point) => ParcelId(
    ((point.dx - origin) / size).floor(),
    ((point.dy - origin) / size).floor(),
  );
  Rect bounds(ParcelId id) => Rect.fromLTWH(
    (origin + id.x * size).toDouble(),
    (origin + id.y * size).toDouble(),
    size.toDouble(),
    size.toDouble(),
  );
  bool owns(Offset point) => purchased.contains(at(point));
  LayeredTerrain? _terrain;
  Set<ParcelId> _available = {};
  Set<ParcelId> available(LayeredTerrain terrain) {
    if (!identical(_terrain, terrain)) {
      _terrain = terrain;
      _available = Set.unmodifiable({
        for (final tile in terrain.tiles.values)
          at(tile.origin + const Offset(.5, .5)),
      });
    }
    return _available;
  }

  bool isAdjacent(ParcelId id) =>
      purchased.contains(ParcelId(id.x - 1, id.y)) ||
      purchased.contains(ParcelId(id.x + 1, id.y)) ||
      purchased.contains(ParcelId(id.x, id.y - 1)) ||
      purchased.contains(ParcelId(id.x, id.y + 1));

  Set<ParcelId> visible(LayeredTerrain terrain) => {
    for (final id in available(terrain))
      if (purchased.contains(id) || isAdjacent(id)) id,
  };

  bool buy(ParcelId id, LayeredTerrain terrain) =>
      available(terrain).contains(id) && isAdjacent(id) && purchased.add(id);
  WorldParcels resized(int side) =>
      WorldParcels(size: side, purchased: purchased);
  Map<String, dynamic> toJson() => {
    'size': size,
    'purchased': [
      for (final id in purchased) [id.x, id.y],
    ],
  };
  factory WorldParcels.fromJson(dynamic json) {
    if (json == null) return WorldParcels();
    if (json is! Map || json['size'] is! int || json['purchased'] is! List) {
      throw const FormatException('Invalid parcels');
    }
    final ids = <ParcelId>{};
    for (final value in json['purchased']) {
      if (value is! List ||
          value.length != 2 ||
          value[0] is! int ||
          value[1] is! int ||
          (value[0] as int).abs() > 10000 ||
          (value[1] as int).abs() > 10000 ||
          !ids.add(ParcelId(value[0], value[1]))) {
        throw const FormatException('Invalid purchased parcel');
      }
    }
    if (!ids.contains(const ParcelId(0, 0))) {
      throw const FormatException('Missing starting parcel');
    }
    return WorldParcels(size: json['size'], purchased: ids);
  }
}
