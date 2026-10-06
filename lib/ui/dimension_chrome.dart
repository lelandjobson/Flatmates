import 'package:flutter/painting.dart';

import '../gridcraft/dimension_measure.dart';

/// Thickness of each ruler's touch band, in logical pixels.
const double kDimensionBand = 28;

/// Gap that keeps the left and bottom rulers from meeting in the corner.
const double kDimensionCornerGap = 16;

/// Screen placement of the two dimension rulers.
///
/// The left track stops a gap above the bottom band. The bottom track starts
/// a gap to the right of the left band. That corner is theirs alone.
class DimensionChrome {
  const DimensionChrome({required this.horizontal, required this.vertical});

  final DimensionTrack horizontal;
  final DimensionTrack vertical;

  static DimensionChrome layout({
    required Size viewport,
    required EdgeInsets safe,
  }) {
    final band = kDimensionBand;
    final gap = kDimensionCornerGap;
    final verticalX = safe.left + band / 2;
    final verticalTop = safe.top + band / 2;
    final bottomBandTop = viewport.height - safe.bottom - band;
    var verticalBottom = bottomBandTop - gap;
    if (verticalBottom < verticalTop) verticalBottom = verticalTop;

    final horizontalY = viewport.height - safe.bottom - band / 2;
    final horizontalLeft = safe.left + band + gap;
    var horizontalRight = viewport.width - safe.right - band / 2;
    if (horizontalRight < horizontalLeft) horizontalRight = horizontalLeft;

    return DimensionChrome(
      vertical: DimensionTrack(
        axis: DimensionAxis.vertical,
        start: Offset(verticalX, verticalTop),
        end: Offset(verticalX, verticalBottom),
      ),
      horizontal: DimensionTrack(
        axis: DimensionAxis.horizontal,
        start: Offset(horizontalLeft, horizontalY),
        end: Offset(horizontalRight, horizontalY),
      ),
    );
  }
}
