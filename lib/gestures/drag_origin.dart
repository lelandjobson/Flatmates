import '../rendering/iso/iso_coordinate.dart';

enum DragOriginType { friend, structure, path, tile }

class DragOrigin {
  const DragOrigin({
    required this.type,
    required this.coordinate,
    this.friendId,
  });

  final DragOriginType type;
  final IsoCoordinate coordinate;
  final String? friendId;

  bool get isFriend => type == DragOriginType.friend;
}
