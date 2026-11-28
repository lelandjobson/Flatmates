import 'package:flatmates/protoplane/controller.dart';
import 'surface_construction_test.dart' show loop;

ProtoplaneController surfaceRoomWorld() {
  final c = ProtoplaneController();
  if (!c.applyVolumeStroke(c.startingTile, loop(0, 0))) {
    throw StateError(c.error!);
  }
  return c;
}
