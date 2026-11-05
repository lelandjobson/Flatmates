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
  CraftKind.floor => [
    CraftKind.rug,
    CraftKind.tabletop,
    CraftKind.bench,
    CraftKind.planter,
    CraftKind.screen,
    CraftKind.bedFrame,
    CraftKind.lamp,
    CraftKind.storage,
  ],
  CraftKind.wall => [CraftKind.window, CraftKind.door],
  CraftKind.bedFrame => [CraftKind.mattress],
  CraftKind.mattress => [CraftKind.pillow, CraftKind.blanket],
  CraftKind.tabletop => [CraftKind.rug, CraftKind.tabletop, CraftKind.lamp],
  CraftKind.storage => [CraftKind.lamp],
  _ => [CraftKind.rug, CraftKind.tabletop],
};
