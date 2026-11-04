import 'construction_fixture.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';

List<int> rectanglePath(int n, int left, int top, int right, int bottom) => [
  for (var x = left; x <= right; x++) top * n + x,
  for (var y = top + 1; y <= bottom; y++) y * n + right,
  for (var x = right - 1; x >= left; x--) bottom * n + x,
  for (var y = bottom - 1; y >= top; y--) y * n + left,
];

CraftObject craft(
  ProtoplaneController c,
  String plane,
  List<int> path, {
  int grid = 0,
  CraftKind? kind,
}) {
  c.enter(plane);
  c.selectGrid(grid);
  c.beginGesture();
  for (final node in path) {
    expect(c.appendNode(node), isTrue, reason: '$node: ${c.error}');
  }
  c.finishGesture();
  if (kind != null) c.choose(kind);
  expect(c.create(), isTrue, reason: c.error);
  return c.objects.values.last;
}

class BedroomFixture {
  BedroomFixture({
    this.tile = 'ground-4-4',
    ProtoplaneController? controller,
    bool walls = true,
    bool door = true,
    bool mattress = true,
  }) : c = controller ?? constructionWorld() {
    floor = craft(c, tile, rectanglePath(3, 0, 0, 2, 2));
    if (walls) {
      for (var i = 0; i < 4; i++) {
        final wall = craft(
          c,
          'wall-${floor.id}-$i',
          rectanglePath(3, 0, 0, 2, 2),
        );
        wallIds.add(wall.id);
      }
      if (door) {
        craft(c, 'surface-${wallIds.first}', rectanglePath(5, 1, 0, 3, 2));
      }
    }
    final surface = 'surface-${floor.id}';
    final index = c.planes[surface]!.grids.indexWhere(
      (g) => g.name == 'Bedroom',
    );
    bed = craft(
      c,
      surface,
      c.planes[surface]!.grids[index].examples[CraftKind.bedFrame]!,
      grid: index,
      kind: CraftKind.bedFrame,
    );
    if (mattress) {
      this.mattress = craft(
        c,
        'surface-${bed.id}',
        rectanglePath(5, 0, 0, 4, 4),
      );
    }
  }
  final String tile;
  final ProtoplaneController c;
  late final CraftObject floor, bed;
  CraftObject? mattress;
  final List<String> wallIds = [];
}
