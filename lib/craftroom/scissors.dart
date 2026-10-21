import 'dart:math' as math;
import 'dart:ui';

/// Grid squares one snip of the scissors cuts.
const int kScissorSquares = 3;

/// A drag shorter than this share of a grid square picks no direction yet.
const double _kScissorDeadZone = 0.3;

/// One of the 8 grid directions [drag] points closest to, as whole grid
/// steps: (1, 0), (1, 1), (0, 1), and on round. Null for a drag too short to
/// read.
(int, int)? scissorDirection(Offset drag, {double spacing = 1}) {
  if (drag.distance < spacing * _kScissorDeadZone) return null;
  final octant = (math.atan2(drag.dy, drag.dx) / (math.pi / 4)).round() % 8;
  const steps = [
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-1, 0),
    (-1, -1),
    (0, -1),
    (1, -1),
  ];
  return steps[octant];
}

/// The snip from [start] toward [drag]: [squares] grid squares along one of
/// the 8 grid directions. A diagonal snip ends [squares] across and
/// [squares] down. Null until the drag picks a direction.
(Offset, Offset)? scissorCut(
  Offset start,
  Offset drag, {
  double spacing = 1,
  int squares = kScissorSquares,
}) {
  final direction = scissorDirection(drag, spacing: spacing);
  if (direction == null) return null;
  final reach = spacing * squares;
  return (start, start + Offset(direction.$1 * reach, direction.$2 * reach));
}
