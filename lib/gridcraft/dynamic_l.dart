import 'dart:ui';

import 'blueprint.dart';

/// One L, 6 wide by 4 tall: three 2×2 blocks along the bottom and one stacked
/// on the left. The sheet margin is 2, so the paper fits under 12 cells.
GridBlueprint dynamicLBlueprint() {
  return const GridBlueprint(
    id: 'dynamic-l',
    name: 'L',
    steps: [
      GridStep(
        id: 'l',
        label: 'L',
        paperMargin: 2,
        polygons: [
          [
            Offset(0, 0),
            Offset(6, 0),
            Offset(6, 2),
            Offset(2, 2),
            Offset(2, 4),
            Offset(0, 4),
          ],
        ],
      ),
    ],
  );
}
