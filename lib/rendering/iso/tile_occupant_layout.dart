import 'dart:ui' show Offset;

/// A reusable, stateless layout engine that distributes entities within a tile
/// into evenly-spaced quadrant positions. Used for placing friends inside
/// structures during close-zoom, but designed to be applied to any tile type
/// (workshops, camps, gathering spots, etc.) in the future.
class TileOccupantLayout {
  const TileOccupantLayout({
    this.maxOccupants = 4,
    this.scaleFactor = 0.75,
    this.inset = 0.25,
    this.quadrants = const [
      Offset(-1, -1), // NW
      Offset(1, -1), // NE
      Offset(-1, 1), // SW
      Offset(1, 1), // SE
    ],
  });

  /// Maximum number of entities this layout can hold.
  final int maxOccupants;

  /// Scale factor applied to each occupant relative to its normal size.
  final double scaleFactor;

  /// Fractional tile offset from center per quadrant unit.
  /// An inset of 0.25 means quadrant centers are 0.25 tile-widths from center.
  final double inset;

  /// Unit direction offsets for each slot. Defaults to 4 quadrants.
  /// Can be replaced with 6, 9, or other layouts.
  final List<Offset> quadrants;

  /// Returns the fractional tile offset for the [index]-th occupant (0-based).
  /// Wraps around if index exceeds the number of defined quadrants.
  Offset positionFor(int index) {
    final slot = quadrants[index % quadrants.length];
    return slot * inset;
  }

  /// Convenience: the scale to apply to each occupant.
  double get occupantScale => scaleFactor;

  /// Default layout for structures: 4 quadrants, 0.75x scale.
  static const structure = TileOccupantLayout();
}
