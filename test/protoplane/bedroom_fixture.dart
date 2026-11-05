import 'recipe_fixture.dart';
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
  if (plane.startsWith('ground-')) {
    c.landscape.deplete(plane, c.planes[plane]!.region);
  }
  // Legacy room coverage deliberately authors each original boundary frame.
  if (c.surfaceFusion.retired.contains(plane)) {
    c.activePlaneId = plane;
    c.editId = null;
    c.clearDraft();
  } else {
    c.enter(plane);
  }
  final source = grid == 3
      ? bedroomGrid(plane, c.activePlane!.region)
      : lattice(
          'fixture',
          c.activePlane!.region,
          count: c.paperSurface ? 5 : 3,
        );
  drawPoints(c, source.trace(path));
  if (kind != null) c.choose(kind);
  expect(c.create(), isTrue, reason: c.error);
  return c.objects.values.last;
}

class BedroomFixture {
  BedroomFixture({
    this.tile = 'ground-starter-paperWhite-0-0',
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
    final bedroom = bedroomGrid(surface, c.planes[surface]!.region);
    bed = craft(
      c,
      surface,
      bedroom.examples[CraftKind.bedFrame]!,
      grid: 3,
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
