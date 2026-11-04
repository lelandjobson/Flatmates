import 'package:flatmates/protoplane/controller.dart';

/// Construction regressions start after resource collection, with enough paper
/// for their multi-story fixtures. Harvest tests use fresh worlds directly.
ProtoplaneController constructionWorld() {
  final model = ProtoplaneController();
  for (final plane in model.planes.values) {
    model.landscape.deplete(plane.id, plane.region);
  }
  for (final color in model.balances.keys) {
    model.balances[color] = 12800;
  }
  return model;
}
