import 'dart:collection';

import 'package:vector_math/vector_math_64.dart';

import '../viewers/world_plane.dart';
import 'volume.dart';

/// How a remaining wall fragment sits relative to the mass enclosure.
enum VolumeEnclosure { outer, courtyard }

enum VolumeSurfaceKind { wall, floor, roof }

/// Integer rectangle on a face, in cell-local subtles. Half-open `[u0,u1)×[v0,v1)`.
class VolumeFaceRect {
  const VolumeFaceRect(this.u0, this.v0, this.u1, this.v1);

  final int u0;
  final int v0;
  final int u1;
  final int v1;

  int get width => u1 - u0;
  int get height => v1 - v0;
  bool get isEmpty => width <= 0 || height <= 0;

  int get area => isEmpty ? 0 : width * height;

  bool sameAs(VolumeFaceRect other) =>
      u0 == other.u0 && v0 == other.v0 && u1 == other.u1 && v1 == other.v1;

  bool containsUv(double u, double v, {double eps = 1e-6}) =>
      u >= u0 - eps && u < u1 + eps && v >= v0 - eps && v < v1 + eps;

  VolumeFaceRect? intersection(VolumeFaceRect other) {
    final nu0 = u0 > other.u0 ? u0 : other.u0;
    final nv0 = v0 > other.v0 ? v0 : other.v0;
    final nu1 = u1 < other.u1 ? u1 : other.u1;
    final nv1 = v1 < other.v1 ? v1 : other.v1;
    if (nu1 <= nu0 || nv1 <= nv0) return null;
    return VolumeFaceRect(nu0, nv0, nu1, nv1);
  }

  @override
  bool operator ==(Object other) =>
      other is VolumeFaceRect && sameAs(other);

  @override
  int get hashCode => Object.hash(u0, v0, u1, v1);
}

/// One remaining exterior face of a resolved solid, still keyed to its box.
class VolumeSurface {
  const VolumeSurface({
    required this.tx,
    required this.ty,
    required this.handle,
    required this.face,
    required this.kind,
    required this.enclosure,
    required this.fullRect,
    required this.fragments,
  });

  final int tx;
  final int ty;
  final VolumeHandle handle;
  final VolumeFace face;
  final VolumeSurfaceKind kind;
  final VolumeEnclosure enclosure;
  final VolumeFaceRect fullRect;
  final List<VolumeFaceRect> fragments;

  bool get isComplete =>
      fragments.length == 1 && fragments.single.sameAs(fullRect);

  int get remainingArea {
    var area = 0;
    for (final fragment in fragments) {
      area += fragment.area;
    }
    return area;
  }
}

/// Derived AABB-union of a volume's editable boxes.
class VolumeSolid {
  const VolumeSolid({
    required this.volumeId,
    required this.surfaces,
    required this.indoorTiles,
    required this.holeTiles,
  });

  final int volumeId;
  final List<VolumeSurface> surfaces;
  final Set<(int, int)> indoorTiles;
  final Set<(int, int)> holeTiles;

  VolumeSurface? surfaceAt(int tx, int ty, VolumeHandle handle) {
    for (final surface in surfaces) {
      if (surface.tx == tx && surface.ty == ty && surface.handle == handle) {
        return surface;
      }
    }
    return null;
  }

  VolumeSurface? surfaceForFace(int tx, int ty, VolumeFace face) {
    for (final surface in surfaces) {
      if (surface.tx == tx && surface.ty == ty && surface.face == face) {
        return surface;
      }
    }
    return null;
  }

  bool isHandleFullyInternal(int tx, int ty, VolumeHandle handle) =>
      surfaceAt(tx, ty, handle) == null;

  bool isFaceFullyInternal(int tx, int ty, VolumeFace face) {
    if (face == VolumeFace.negY) return false;
    final handle = handleForFace(face);
    if (handle == null) return false;
    return isHandleFullyInternal(tx, ty, handle);
  }

  Iterable<VolumeSurface> courtyardWalls() => surfaces.where(
        (s) => s.kind == VolumeSurfaceKind.wall &&
            s.enclosure == VolumeEnclosure.courtyard,
      );

  /// True when [world] lands on remaining solid area of [face], not a
  /// swallowed interior patch of the original box.
  bool containsFaceHit({
    required VolumeCell cell,
    required VolumeFace face,
    required VolumeGrid grid,
    required Vector3 world,
  }) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    if (!face.liesOnFace(world, min, max)) return false;
    if (face == VolumeFace.negY) return true;
    final surface = surfaceForFace(cell.tx, cell.ty, face);
    if (surface == null) return false;
    final uv = faceUvAt(world: world, grid: grid, cell: cell, face: face);
    if (uv == null) return false;
    for (final fragment in surface.fragments) {
      if (fragment.containsUv(uv.$1, uv.$2)) return true;
    }
    return false;
  }

  List<List<Vector3>> faceWorldQuads({
    required VolumeCell cell,
    required VolumeFace face,
    required VolumeGrid grid,
  }) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    if (face == VolumeFace.negY) {
      return [
        [
          Vector3(min.x, min.y, min.z),
          Vector3(min.x, min.y, max.z),
          Vector3(max.x, min.y, max.z),
          Vector3(max.x, min.y, min.z),
        ],
      ];
    }
    final surface = surfaceForFace(cell.tx, cell.ty, face);
    if (surface == null) return const [];
    final s = grid.subtileSize;
    return [
      for (final fragment in surface.fragments)
        volumeFaceFragmentQuad(
          min: min,
          max: max,
          handle: surface.handle,
          fragment: fragment,
          subtileSize: s,
        ),
    ];
  }

  Vector3 handleCenter({
    required VolumeCell cell,
    required VolumeHandle handle,
    required VolumeGrid grid,
  }) {
    final surface = surfaceAt(cell.tx, cell.ty, handle);
    if (surface == null || surface.fragments.isEmpty) {
      return cell.box.faceCenter(grid, cell.tx, cell.ty, handle);
    }
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    var x = 0.0;
    var y = 0.0;
    var z = 0.0;
    var n = 0;
    for (final fragment in surface.fragments) {
      final quad = volumeFaceFragmentQuad(
        min: min,
        max: max,
        handle: handle,
        fragment: fragment,
        subtileSize: grid.subtileSize,
      );
      for (final p in quad) {
        x += p.x;
        y += p.y;
        z += p.z;
        n++;
      }
    }
    if (n == 0) return cell.box.faceCenter(grid, cell.tx, cell.ty, handle);
    return Vector3(x / n, y / n, z / n);
  }
}

(double, double)? faceUvAt({
  required Vector3 world,
  required VolumeGrid grid,
  required VolumeCell cell,
  required VolumeFace face,
}) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final s = grid.subtileSize;
  if (s <= 1e-8) return null;
  final box = cell.box;
  late final double u;
  late final double v;
  late final int uMax;
  late final int vMax;
  switch (face) {
    case VolumeFace.posY:
    case VolumeFace.negY:
      u = (world.x - min.x) / s;
      v = (world.z - min.z) / s;
      uMax = box.widthSubtiles;
      vMax = box.depthSubtiles;
    case VolumeFace.posX:
    case VolumeFace.negX:
      u = (world.z - min.z) / s;
      v = (world.y - min.y) / s;
      uMax = box.depthSubtiles;
      vMax = box.heightSubtiles;
    case VolumeFace.posZ:
    case VolumeFace.negZ:
      u = (world.x - min.x) / s;
      v = (world.y - min.y) / s;
      uMax = box.widthSubtiles;
      vMax = box.heightSubtiles;
  }
  if (u < -1e-4 || v < -1e-4 || u > uMax + 1e-4 || v > vMax + 1e-4) {
    return null;
  }
  return (u, v);
}

List<Vector3> volumeFaceFragmentQuad({
  required Vector3 min,
  required Vector3 max,
  required VolumeHandle handle,
  required VolumeFaceRect fragment,
  required double subtileSize,
}) {
  final s = subtileSize;
  final u0 = fragment.u0 * s;
  final u1 = fragment.u1 * s;
  final v0 = fragment.v0 * s;
  final v1 = fragment.v1 * s;
  return switch (handle) {
    VolumeHandle.posX => [
        Vector3(max.x, min.y + v0, min.z + u0),
        Vector3(max.x, min.y + v1, min.z + u0),
        Vector3(max.x, min.y + v1, min.z + u1),
        Vector3(max.x, min.y + v0, min.z + u1),
      ],
    VolumeHandle.negX => [
        Vector3(min.x, min.y + v0, min.z + u0),
        Vector3(min.x, min.y + v0, min.z + u1),
        Vector3(min.x, min.y + v1, min.z + u1),
        Vector3(min.x, min.y + v1, min.z + u0),
      ],
    VolumeHandle.posZ => [
        Vector3(min.x + u0, min.y + v0, max.z),
        Vector3(min.x + u1, min.y + v0, max.z),
        Vector3(min.x + u1, min.y + v1, max.z),
        Vector3(min.x + u0, min.y + v1, max.z),
      ],
    VolumeHandle.negZ => [
        Vector3(min.x + u0, min.y + v0, min.z),
        Vector3(min.x + u0, min.y + v1, min.z),
        Vector3(min.x + u1, min.y + v1, min.z),
        Vector3(min.x + u1, min.y + v0, min.z),
      ],
    VolumeHandle.posY => [
        Vector3(min.x + u0, max.y, min.z + v0),
        Vector3(min.x + u0, max.y, min.z + v1),
        Vector3(min.x + u1, max.y, min.z + v1),
        Vector3(min.x + u1, max.y, min.z + v0),
      ],
  };
}

VolumeHandle? handleForFace(VolumeFace face) => switch (face) {
      VolumeFace.posX => VolumeHandle.posX,
      VolumeFace.negX => VolumeHandle.negX,
      VolumeFace.posY => VolumeHandle.posY,
      VolumeFace.posZ => VolumeHandle.posZ,
      VolumeFace.negZ => VolumeHandle.negZ,
      VolumeFace.negY => null,
    };

VolumeFace faceForHandle(VolumeHandle handle) => switch (handle) {
      VolumeHandle.posX => VolumeFace.posX,
      VolumeHandle.negX => VolumeFace.negX,
      VolumeHandle.posY => VolumeFace.posY,
      VolumeHandle.posZ => VolumeFace.posZ,
      VolumeHandle.negZ => VolumeFace.negZ,
    };

VolumeSurfaceKind kindForHandle(VolumeHandle handle) => switch (handle) {
      VolumeHandle.posY => VolumeSurfaceKind.roof,
      VolumeHandle.posX ||
      VolumeHandle.negX ||
      VolumeHandle.posZ ||
      VolumeHandle.negZ =>
        VolumeSurfaceKind.wall,
    };

VolumeFaceRect faceFullRect(BoxPrimitive box, VolumeHandle handle) {
  return switch (handle) {
    VolumeHandle.posX || VolumeHandle.negX => VolumeFaceRect(
        0,
        0,
        box.depthSubtiles,
        box.heightSubtiles,
      ),
    VolumeHandle.posZ || VolumeHandle.negZ => VolumeFaceRect(
        0,
        0,
        box.widthSubtiles,
        box.heightSubtiles,
      ),
    VolumeHandle.posY => VolumeFaceRect(
        0,
        0,
        box.widthSubtiles,
        box.depthSubtiles,
      ),
  };
}

/// Union the [volume] boxes into a solid: drop fully shared faces, keep
/// leftover strips, and mark courtyard walls that face enclosed holes.
VolumeSolid resolveVolumeSolid(Volume volume, VolumeGrid grid) {
  final indoor = <(int, int)>{
    for (final cell in volume.cells) (cell.tx, cell.ty),
  };
  final holes = _enclosedHoles(grid, indoor);
  final boxes = [
    for (final cell in volume.cells) _CellAabb.from(cell, grid),
  ];

  final surfaces = <VolumeSurface>[];
  for (final box in boxes) {
    for (final handle in VolumeHandle.values) {
      final full = faceFullRect(box.cell.box, handle);
      final cuts = <VolumeFaceRect>[];
      if (handle != VolumeHandle.posY) {
        for (final other in boxes) {
          if (identical(other, box)) continue;
          final cut = _contactOnFace(box, other, handle);
          if (cut != null) cuts.add(cut);
        }
      }
      final fragments = _subtractAll(full, cuts);
      if (fragments.isEmpty) continue;
      final kind = kindForHandle(handle);
      final enclosure = kind == VolumeSurfaceKind.wall
          ? _classifyWall(box, handle, fragments, grid, holes)
          : VolumeEnclosure.outer;
      surfaces.add(
        VolumeSurface(
          tx: box.cell.tx,
          ty: box.cell.ty,
          handle: handle,
          face: faceForHandle(handle),
          kind: kind,
          enclosure: enclosure,
          fullRect: full,
          fragments: fragments,
        ),
      );
    }
  }

  return VolumeSolid(
    volumeId: volume.id,
    surfaces: surfaces,
    indoorTiles: indoor,
    holeTiles: holes,
  );
}

class _CellAabb {
  _CellAabb({
    required this.cell,
    required this.sx0,
    required this.sy0,
    required this.sz0,
    required this.sx1,
    required this.sy1,
    required this.sz1,
  });

  factory _CellAabb.from(VolumeCell cell, VolumeGrid grid) {
    final n = grid.subtilesPerTile;
    final sx0 = cell.tx * n + cell.box.originXSubtiles;
    final sz0 = cell.ty * n + cell.box.originZSubtiles;
    return _CellAabb(
      cell: cell,
      sx0: sx0,
      sy0: 0,
      sz0: sz0,
      sx1: sx0 + cell.box.widthSubtiles,
      sy1: cell.box.heightSubtiles,
      sz1: sz0 + cell.box.depthSubtiles,
    );
  }

  final VolumeCell cell;
  final int sx0;
  final int sy0;
  final int sz0;
  final int sx1;
  final int sy1;
  final int sz1;
}

VolumeFaceRect? _contactOnFace(
  _CellAabb a,
  _CellAabb b,
  VolumeHandle handle,
) {
  final touches = switch (handle) {
    VolumeHandle.posX => b.sx0 == a.sx1,
    VolumeHandle.negX => b.sx1 == a.sx0,
    VolumeHandle.posZ => b.sz0 == a.sz1,
    VolumeHandle.negZ => b.sz1 == a.sz0,
    VolumeHandle.posY => false,
  };
  if (!touches) return null;

  late final int au0;
  late final int av0;
  late final int au1;
  late final int av1;
  late final int bu0;
  late final int bv0;
  late final int bu1;
  late final int bv1;
  switch (handle) {
    case VolumeHandle.posX:
    case VolumeHandle.negX:
      au0 = a.sz0;
      au1 = a.sz1;
      av0 = a.sy0;
      av1 = a.sy1;
      bu0 = b.sz0;
      bu1 = b.sz1;
      bv0 = b.sy0;
      bv1 = b.sy1;
    case VolumeHandle.posZ:
    case VolumeHandle.negZ:
      au0 = a.sx0;
      au1 = a.sx1;
      av0 = a.sy0;
      av1 = a.sy1;
      bu0 = b.sx0;
      bu1 = b.sx1;
      bv0 = b.sy0;
      bv1 = b.sy1;
    case VolumeHandle.posY:
      return null;
  }
  final iu0 = au0 > bu0 ? au0 : bu0;
  final iv0 = av0 > bv0 ? av0 : bv0;
  final iu1 = au1 < bu1 ? au1 : bu1;
  final iv1 = av1 < bv1 ? av1 : bv1;
  if (iu1 <= iu0 || iv1 <= iv0) return null;
  return VolumeFaceRect(iu0 - au0, iv0 - av0, iu1 - au0, iv1 - av0);
}

List<VolumeFaceRect> _subtractAll(
  VolumeFaceRect start,
  List<VolumeFaceRect> cuts,
) {
  var current = [start];
  for (final cut in cuts) {
    final next = <VolumeFaceRect>[];
    for (final rect in current) {
      next.addAll(_subtractRect(rect, cut));
    }
    current = next;
  }
  return current;
}

List<VolumeFaceRect> _subtractRect(VolumeFaceRect a, VolumeFaceRect b) {
  final overlap = a.intersection(b);
  if (overlap == null) return [a];
  final out = <VolumeFaceRect>[];
  if (a.u0 < overlap.u0) {
    out.add(VolumeFaceRect(a.u0, a.v0, overlap.u0, a.v1));
  }
  if (overlap.u1 < a.u1) {
    out.add(VolumeFaceRect(overlap.u1, a.v0, a.u1, a.v1));
  }
  if (a.v0 < overlap.v0) {
    out.add(VolumeFaceRect(overlap.u0, a.v0, overlap.u1, overlap.v0));
  }
  if (overlap.v1 < a.v1) {
    out.add(VolumeFaceRect(overlap.u0, overlap.v1, overlap.u1, a.v1));
  }
  return [for (final rect in out) if (!rect.isEmpty) rect];
}

Set<(int, int)> _enclosedHoles(VolumeGrid grid, Set<(int, int)> indoor) {
  final outdoor = <(int, int)>{};
  final queue = Queue<(int, int)>();

  void seed(int tx, int ty) {
    if (!grid.inBounds(tx, ty)) return;
    if (indoor.contains((tx, ty))) return;
    if (outdoor.add((tx, ty))) queue.add((tx, ty));
  }

  final last = grid.tilesSide - 1;
  for (var i = 0; i < grid.tilesSide; i++) {
    seed(i, 0);
    seed(i, last);
    seed(0, i);
    seed(last, i);
  }

  while (queue.isNotEmpty) {
    final (tx, ty) = queue.removeFirst();
    seed(tx + 1, ty);
    seed(tx - 1, ty);
    seed(tx, ty + 1);
    seed(tx, ty - 1);
  }

  final holes = <(int, int)>{};
  for (var ty = 0; ty < grid.tilesSide; ty++) {
    for (var tx = 0; tx < grid.tilesSide; tx++) {
      final tile = (tx, ty);
      if (indoor.contains(tile) || outdoor.contains(tile)) continue;
      holes.add(tile);
    }
  }
  return holes;
}

VolumeEnclosure _classifyWall(
  _CellAabb box,
  VolumeHandle handle,
  List<VolumeFaceRect> fragments,
  VolumeGrid grid,
  Set<(int, int)> holes,
) {
  var courtyardArea = 0;
  var outerArea = 0;
  for (final fragment in fragments) {
    final tile = _tileJustOutside(box, handle, fragment, grid);
    if (tile != null && holes.contains(tile)) {
      courtyardArea += fragment.area;
    } else {
      outerArea += fragment.area;
    }
  }
  if (courtyardArea > outerArea) return VolumeEnclosure.courtyard;
  return VolumeEnclosure.outer;
}

(int, int)? _tileJustOutside(
  _CellAabb box,
  VolumeHandle handle,
  VolumeFaceRect fragment,
  VolumeGrid grid,
) {
  final n = grid.subtilesPerTile;
  late final int sx;
  late final int sy;
  late final int sz;
  final um = fragment.u0 + fragment.width * 0.5;
  final vm = fragment.v0 + fragment.height * 0.5;
  switch (handle) {
    case VolumeHandle.posX:
      sx = box.sx1;
      sy = (box.sy0 + vm).floor();
      sz = (box.sz0 + um).floor();
    case VolumeHandle.negX:
      sx = box.sx0 - 1;
      sy = (box.sy0 + vm).floor();
      sz = (box.sz0 + um).floor();
    case VolumeHandle.posZ:
      sx = (box.sx0 + um).floor();
      sy = (box.sy0 + vm).floor();
      sz = box.sz1;
    case VolumeHandle.negZ:
      sx = (box.sx0 + um).floor();
      sy = (box.sy0 + vm).floor();
      sz = box.sz0 - 1;
    case VolumeHandle.posY:
      return null;
  }
  final tx = sx >= 0 ? sx ~/ n : -1;
  final ty = sz >= 0 ? sz ~/ n : -1;
  if (!grid.inBounds(tx, ty)) return null;
  return (tx, ty);
}

/// Remove door flags whose sides were swallowed by the solid.
void clearInternalDoors(Volume volume, VolumeSolid solid) {
  for (final cell in volume.cells) {
    cell.accessibleSides.removeWhere((side) {
      return solid.isHandleFullyInternal(cell.tx, cell.ty, side.handle);
    });
    cell.doorOrigins.removeWhere(
      (side, _) => !cell.accessibleSides.contains(side),
    );
  }
}
