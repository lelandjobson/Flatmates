import 'dart:ui';

import 'geometry.dart';
import 'models.dart';

/// Material requirements can be added to these definitions when the paper
/// store arrives; color alone never changes bedroom eligibility or comfort.
class BedroomItemSpec {
  const BedroomItemSpec(
    this.kind,
    this.supports,
    this.minimumCoverage,
    this.maximumCoverage,
  );
  final CraftKind kind;
  final Set<CraftKind> supports;
  final double minimumCoverage, maximumCoverage;
}

const bedroomItems = <CraftKind, BedroomItemSpec>{
  CraftKind.bedFrame: BedroomItemSpec(
    CraftKind.bedFrame,
    {CraftKind.floor},
    .025,
    .65,
  ),
  CraftKind.mattress: BedroomItemSpec(
    CraftKind.mattress,
    {CraftKind.bedFrame},
    .65,
    1,
  ),
  CraftKind.pillow: BedroomItemSpec(
    CraftKind.pillow,
    {CraftKind.mattress},
    .04,
    .4,
  ),
  CraftKind.blanket: BedroomItemSpec(
    CraftKind.blanket,
    {CraftKind.mattress},
    .35,
    .85,
  ),
  CraftKind.lamp: BedroomItemSpec(
    CraftKind.lamp,
    {CraftKind.floor, CraftKind.tabletop, CraftKind.storage},
    .001,
    .3,
  ),
  CraftKind.storage: BedroomItemSpec(
    CraftKind.storage,
    {CraftKind.floor},
    .005,
    .4,
  ),
};

List<CraftKind> surfaceRecipes(CraftKind kind) => switch (kind) {
  CraftKind.wall => [CraftKind.window, CraftKind.door],
  CraftKind.bedFrame => [CraftKind.mattress],
  CraftKind.mattress => [CraftKind.pillow, CraftKind.blanket],
  CraftKind.tabletop => [CraftKind.rug, CraftKind.tabletop, CraftKind.lamp],
  CraftKind.storage => [CraftKind.lamp],
  _ => [CraftKind.rug, CraftKind.tabletop],
};

CraftGrid bedroomGrid(String planeId, Region region) {
  var box = region.bounds.deflate(region.bounds.shortestSide * .06);
  if (!region.containsRegion(
    rectangle(box.width, box.height, origin: box.topLeft),
  )) {
    box = interiorSquare(region);
  }
  final nodes = [
    for (var y = 0; y < 7; y++)
      for (var x = 0; x < 7; x++)
        Offset(box.left + box.width * x / 6, box.top + box.height * y / 6),
  ];
  final edges = <GridEdge>[];
  for (var y = 0; y < 7; y++) {
    for (var x = 0; x < 7; x++) {
      final i = y * 7 + x;
      if (x < 6) edges.add(GridEdge(i, i + 1));
      if (y < 6) edges.add(GridEdge(i, i + 7));
    }
  }
  return CraftGrid(
    id: '$planeId-bedroom',
    name: 'Bedroom',
    nodes: nodes,
    edges: edges,
    recipes: [
      CraftKind.bedFrame,
      CraftKind.lamp,
      CraftKind.storage,
      CraftKind.rug,
    ],
    examples: {
      CraftKind.bedFrame: [8, 9, 10, 17, 24, 31, 30, 29, 22, 15, 8],
      CraftKind.lamp: [12, 13, 20, 19, 12],
      CraftKind.storage: [33, 34, 41, 48, 47, 40, 33],
      CraftKind.rug: [36, 37, 38, 45, 44, 43, 36],
    },
  );
}
