import 'line_puzzle_models.dart';

/// Two L outlines. Each loop closes on a double dot.
///
/// Trace the left L, leave through the bottom edge, switch tools, then
/// trace the right L.
final LinePuzzle twoLsLinePuzzle = LinePuzzle(
  id: 'line-two-ls',
  title: 'Two Ls',
  blurb: 'Trace both outlines. Leave the paper to switch tools.',
  regions: [
    LineRegion(
      ring: const [
        LinePoint(0, 0),
        LinePoint(3, 0),
        LinePoint(3, 1),
        LinePoint(1, 1),
        LinePoint(1, 2),
        LinePoint(0, 2),
      ],
      coverBorder: true,
    ),
    LineRegion(
      ring: const [
        LinePoint(4, 0),
        LinePoint(7, 0),
        LinePoint(7, 1),
        LinePoint(5, 1),
        LinePoint(5, 2),
        LinePoint(4, 2),
      ],
      coverBorder: true,
    ),
  ],
  doubles: {const LinePoint(0, 0), const LinePoint(4, 0)},
  missing: {
    const LinePoint(2, 3),
    const LinePoint(6, 3),
    const LinePoint(8, 1),
  },
);

/// Three blocks that must be touched as 1, then 2, then 3.
final LinePuzzle orderLinePuzzle = LinePuzzle(
  id: 'line-order',
  title: 'Order',
  blurb: 'Pass through the numbers in order.',
  regions: [
    LineRegion(ring: lineRect(0, 0, 2, 2), order: 1),
    LineRegion(ring: lineRect(3, 0, 5, 2), order: 2),
    LineRegion(ring: lineRect(6, 0, 8, 2), order: 3),
  ],
  missing: {
    const LinePoint(4, 3),
    const LinePoint(4, -1),
    const LinePoint(7, 3),
  },
);

/// Two outlines. The paper has to match the icon before the border closes.
final LinePuzzle colorLinePuzzle = LinePuzzle(
  id: 'line-color',
  title: 'Color',
  blurb: 'Cross a color square, then trace the matching piece.',
  regions: [
    LineRegion(ring: lineRect(0, 0, 3, 2), color: 0),
    LineRegion(ring: lineRect(5, 0, 8, 2), color: 1),
  ],
  doubles: {const LinePoint(0, 0), const LinePoint(5, 0)},
  flippers: const [
    LineFlipper(at: LinePoint(-1, 0), color: 0),
    LineFlipper(at: LinePoint(5, -1), color: 1),
  ],
);

final List<LinePuzzle> kLinePuzzles = [
  twoLsLinePuzzle,
  orderLinePuzzle,
  colorLinePuzzle,
];
