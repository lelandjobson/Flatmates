import 'dart:ui';

import 'blueprint.dart';

/// Two 3×2 L outlines on one sheet. Spacing is 1. The paper is 2 units
/// outside the bounding box of the outlines.
GridBlueprint twinLsBlueprint() {
  return GridBlueprint(
    id: 'twin-ls',
    name: 'Two Ls',
    steps: [
      GridStep(
        id: 'ls',
        label: 'Two Ls',
        paperMargin: 2,
        polygons: const [
          [
            Offset(0, 0),
            Offset(3, 0),
            Offset(3, 1),
            Offset(1, 1),
            Offset(1, 2),
            Offset(0, 2),
          ],
          [
            Offset(4, 0),
            Offset(7, 0),
            Offset(7, 1),
            Offset(5, 1),
            Offset(5, 2),
            Offset(4, 2),
          ],
        ],
      ),
    ],
  );
}
