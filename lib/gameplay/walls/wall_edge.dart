/// Kinds of wall that can occupy a grid edge. More types will land later.
enum WallKind {
  /// Short wooden fence.
  fence,
}

/// Undirected unit-length axis-aligned edge between two grid vertices.
///
/// Vertices sit on tile corners: vertex `(vx, vy)` is the −X/−Z corner of
/// tile `(vx, vy)` when that tile is in bounds. `+X` is east, `+Z` is south.
class WallEdge {
  WallEdge(int ax, int ay, int bx, int by, {this.kind = WallKind.fence})
      : x0 = _min(ax, ay, bx, by).$1,
        y0 = _min(ax, ay, bx, by).$2,
        x1 = _max(ax, ay, bx, by).$1,
        y1 = _max(ax, ay, bx, by).$2;

  final int x0;
  final int y0;
  final int x1;
  final int y1;
  final WallKind kind;

  static (int, int) _min(int ax, int ay, int bx, int by) =>
      (ax < bx || (ax == bx && ay <= by)) ? (ax, ay) : (bx, by);

  static (int, int) _max(int ax, int ay, int bx, int by) =>
      (ax < bx || (ax == bx && ay <= by)) ? (bx, by) : (ax, ay);

  bool get isHorizontal => y0 == y1 && x1 == x0 + 1;

  bool get isVertical => x0 == x1 && y1 == y0 + 1;

  bool get isUnitOrtho => isHorizontal || isVertical;

  /// Equality is geometric so a later wall type can replace this segment.
  @override
  bool operator ==(Object other) =>
      other is WallEdge &&
      other.x0 == x0 &&
      other.y0 == y0 &&
      other.x1 == x1 &&
      other.y1 == y1;

  @override
  int get hashCode => Object.hash(x0, y0, x1, y1);

  @override
  String toString() => 'WallEdge(($x0,$y0)-($x1,$y1), ${kind.name})';
}

WallKind wallKindFromName(String? name) {
  for (final kind in WallKind.values) {
    if (kind.name == name) return kind;
  }
  return WallKind.fence;
}
