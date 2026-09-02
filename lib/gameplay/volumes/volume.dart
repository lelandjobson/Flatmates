import 'package:vector_math/vector_math_64.dart';

/// Cardinal sides of a volume (no top/bottom).
enum VolumeSide { north, east, south, west }

extension VolumeSideX on VolumeSide {
  /// Grid step: +X is east, +Z is south.
  (int dx, int dy) get tileDelta => switch (this) {
        VolumeSide.east => (1, 0),
        VolumeSide.west => (-1, 0),
        VolumeSide.south => (0, 1),
        VolumeSide.north => (0, -1),
      };

  Vector3 get worldAxis => switch (this) {
        VolumeSide.east => Vector3(1, 0, 0),
        VolumeSide.west => Vector3(-1, 0, 0),
        VolumeSide.south => Vector3(0, 0, 1),
        VolumeSide.north => Vector3(0, 0, -1),
      };

  /// Index in [GeometryBuilders.cubeFaces]: -Z, +Z, -Y, +Y, +X, -X.
  int get cubeFaceIndex => handle.cubeFaceIndex;

  VolumeSide get opposite => switch (this) {
        VolumeSide.north => VolumeSide.south,
        VolumeSide.south => VolumeSide.north,
        VolumeSide.east => VolumeSide.west,
        VolumeSide.west => VolumeSide.east,
      };

  /// Bit used in path neighbor masks: N=1, E=2, S=4, W=8.
  int get maskBit => switch (this) {
        VolumeSide.north => 1,
        VolumeSide.east => 2,
        VolumeSide.south => 4,
        VolumeSide.west => 8,
      };
}

class VolumeGrid {
  static const int defaultSubtilesPerTile = 8;

  const VolumeGrid({
    this.tilesSide = 16,
    this.tileSize = 8,
    this.subtilesPerTile = defaultSubtilesPerTile,
  });

  final int tilesSide;
  final double tileSize;

  /// Material cells along one tile edge. Matches landscape atlas texels per tile.
  final int subtilesPerTile;

  double get mapHalf => tilesSide * tileSize * 0.5;

  /// World size of one subtile.
  double get subtileSize => tileSize / subtilesPerTile;

  bool inBounds(int tx, int ty) =>
      tx >= 0 && ty >= 0 && tx < tilesSide && ty < tilesSide;

  (int tx, int ty)? tileAtWorld(Vector3 world) {
    final tx = ((world.x + mapHalf) / tileSize).floor();
    final ty = ((world.z + mapHalf) / tileSize).floor();
    if (!inBounds(tx, ty)) return null;
    return (tx, ty);
  }

  Vector3 tileOrigin(int tx, int ty) => Vector3(
        -mapHalf + tx * tileSize,
        0,
        -mapHalf + ty * tileSize,
      );

  Vector3 tileCenter(int tx, int ty) => Vector3(
        -mapHalf + (tx + 0.5) * tileSize,
        0,
        -mapHalf + (ty + 0.5) * tileSize,
      );

  (Vector3 min, Vector3 max) tileAabb(int tx, int ty) {
    final origin = tileOrigin(tx, ty);
    return (
      origin,
      Vector3(
        origin.x + tileSize,
        BoxPrimitive.maxHeightSubtiles * subtileSize,
        origin.z + tileSize,
      ),
    );
  }
}

/// Axis-aligned box occupying a span of subtles inside one tile.
class BoxPrimitive {
  BoxPrimitive({
    this.widthSubtiles = VolumeGrid.defaultSubtilesPerTile,
    this.depthSubtiles = VolumeGrid.defaultSubtilesPerTile,
    this.heightSubtiles = maxHeightSubtiles,
    this.originXSubtiles = 0,
    this.originZSubtiles = 0,
  });

  static const int minSubtiles = 4;
  static const int maxHeightSubtiles = 6;

  int widthSubtiles;
  int depthSubtiles;
  int heightSubtiles;

  /// Subtile offset of the −X/−Z corner from the tile origin.
  int originXSubtiles;
  int originZSubtiles;

  BoxPrimitive clone() => BoxPrimitive(
        widthSubtiles: widthSubtiles,
        depthSubtiles: depthSubtiles,
        heightSubtiles: heightSubtiles,
        originXSubtiles: originXSubtiles,
        originZSubtiles: originZSubtiles,
      );

  void setFrom(BoxPrimitive other) {
    widthSubtiles = other.widthSubtiles;
    depthSubtiles = other.depthSubtiles;
    heightSubtiles = other.heightSubtiles;
    originXSubtiles = other.originXSubtiles;
    originZSubtiles = other.originZSubtiles;
  }

  bool sameAs(BoxPrimitive other) =>
      widthSubtiles == other.widthSubtiles &&
      depthSubtiles == other.depthSubtiles &&
      heightSubtiles == other.heightSubtiles &&
      originXSubtiles == other.originXSubtiles &&
      originZSubtiles == other.originZSubtiles;

  Vector3 worldMin(VolumeGrid grid, int tx, int ty) {
    final origin = grid.tileOrigin(tx, ty);
    final s = grid.subtileSize;
    return Vector3(
      origin.x + originXSubtiles * s,
      0,
      origin.z + originZSubtiles * s,
    );
  }

  Vector3 worldMax(VolumeGrid grid, int tx, int ty) {
    final origin = grid.tileOrigin(tx, ty);
    final s = grid.subtileSize;
    return Vector3(
      origin.x + (originXSubtiles + widthSubtiles) * s,
      heightSubtiles * s,
      origin.z + (originZSubtiles + depthSubtiles) * s,
    );
  }

  Vector3 worldCenter(VolumeGrid grid, int tx, int ty) {
    final min = worldMin(grid, tx, ty);
    final max = worldMax(grid, tx, ty);
    return Vector3(
      (min.x + max.x) * 0.5,
      (min.y + max.y) * 0.5,
      (min.z + max.z) * 0.5,
    );
  }

  /// Eight AABB corners in world space.
  List<Vector3> worldCorners(VolumeGrid grid, int tx, int ty) {
    final min = worldMin(grid, tx, ty);
    final max = worldMax(grid, tx, ty);
    return [
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(min.x, min.y, max.z),
      Vector3(max.x, min.y, max.z),
      Vector3(min.x, max.y, min.z),
      Vector3(max.x, max.y, min.z),
      Vector3(min.x, max.y, max.z),
      Vector3(max.x, max.y, max.z),
    ];
  }

  Vector3 faceCenter(VolumeGrid grid, int tx, int ty, VolumeHandle handle) {
    final min = worldMin(grid, tx, ty);
    final max = worldMax(grid, tx, ty);
    final midY = (min.y + max.y) * 0.5;
    final midX = (min.x + max.x) * 0.5;
    final midZ = (min.z + max.z) * 0.5;
    return switch (handle) {
      VolumeHandle.posX => Vector3(max.x, midY, midZ),
      VolumeHandle.negX => Vector3(min.x, midY, midZ),
      VolumeHandle.posZ => Vector3(midX, midY, max.z),
      VolumeHandle.negZ => Vector3(midX, midY, min.z),
      VolumeHandle.posY => Vector3(midX, max.y, midZ),
    };
  }

  Vector3 sideFaceCenter(VolumeGrid grid, int tx, int ty, VolumeSide side) {
    return faceCenter(grid, tx, ty, side.handle);
  }

  /// True when this box's face is flush with that edge of the tile.
  bool touchesTileEdge(VolumeSide side, int subtilesPerTile) {
    return switch (side) {
      VolumeSide.west => originXSubtiles == 0,
      VolumeSide.east => originXSubtiles + widthSubtiles == subtilesPerTile,
      VolumeSide.north => originZSubtiles == 0,
      VolumeSide.south => originZSubtiles + depthSubtiles == subtilesPerTile,
    };
  }

  /// Move [handle]'s face by [delta] world units, snapping to whole subtles.
  /// The opposite face stays fixed.
  void applyHandleDelta({
    required VolumeGrid grid,
    required int tx,
    required int ty,
    required VolumeHandle handle,
    required double delta,
  }) {
    final steps = (delta / grid.subtileSize).round();
    final n = grid.subtilesPerTile;
    switch (handle) {
      case VolumeHandle.posX:
        widthSubtiles =
            (widthSubtiles + steps).clamp(minSubtiles, n - originXSubtiles).toInt();
      case VolumeHandle.negX:
        final maxX = originXSubtiles + widthSubtiles;
        originXSubtiles =
            (originXSubtiles - steps).clamp(0, maxX - minSubtiles).toInt();
        widthSubtiles = maxX - originXSubtiles;
      case VolumeHandle.posZ:
        depthSubtiles =
            (depthSubtiles + steps).clamp(minSubtiles, n - originZSubtiles).toInt();
      case VolumeHandle.negZ:
        final maxZ = originZSubtiles + depthSubtiles;
        originZSubtiles =
            (originZSubtiles - steps).clamp(0, maxZ - minSubtiles).toInt();
        depthSubtiles = maxZ - originZSubtiles;
      case VolumeHandle.posY:
        heightSubtiles = (heightSubtiles + steps)
            .clamp(minSubtiles, maxHeightSubtiles)
            .toInt();
    }
  }
}

enum VolumeHandle { posX, negX, posZ, negZ, posY }

extension VolumeHandleX on VolumeHandle {
  Vector3 get axis => switch (this) {
        VolumeHandle.posX => Vector3(1, 0, 0),
        VolumeHandle.negX => Vector3(-1, 0, 0),
        VolumeHandle.posZ => Vector3(0, 0, 1),
        VolumeHandle.negZ => Vector3(0, 0, -1),
        VolumeHandle.posY => Vector3(0, 1, 0),
      };

  bool get isHeight => this == VolumeHandle.posY;

  /// Tile step for a horizontal face, or null for height.
  (int dx, int dy)? get tileDelta => switch (this) {
        VolumeHandle.posX => (1, 0),
        VolumeHandle.negX => (-1, 0),
        VolumeHandle.posZ => (0, 1),
        VolumeHandle.negZ => (0, -1),
        VolumeHandle.posY => null,
      };

  /// Index in [GeometryBuilders.cubeFaces]: -Z, +Z, -Y, +Y, +X, -X.
  int get cubeFaceIndex => switch (this) {
        VolumeHandle.negZ => 0,
        VolumeHandle.posZ => 1,
        VolumeHandle.posY => 3,
        VolumeHandle.posX => 4,
        VolumeHandle.negX => 5,
      };
}

extension VolumeSideHandle on VolumeSide {
  VolumeHandle get handle => switch (this) {
        VolumeSide.east => VolumeHandle.posX,
        VolumeSide.west => VolumeHandle.negX,
        VolumeSide.south => VolumeHandle.posZ,
        VolumeSide.north => VolumeHandle.negZ,
      };
}

class VolumeCell {
  VolumeCell({
    required this.tx,
    required this.ty,
    required this.box,
    Set<VolumeSide>? accessibleSides,
    Map<VolumeSide, int>? doorOrigins,
  })  : accessibleSides = accessibleSides ?? <VolumeSide>{},
        doorOrigins = doorOrigins ?? <VolumeSide, int>{};

  final int tx;
  final int ty;
  final BoxPrimitive box;

  /// Exterior sides on this cell that have a door. A cell may have several.
  final Set<VolumeSide> accessibleSides;

  /// Subtile originU of a placed 2×4 door paper. Missing sides use centering.
  final Map<VolumeSide, int> doorOrigins;

  VolumeCell clone() => VolumeCell(
        tx: tx,
        ty: ty,
        box: box.clone(),
        accessibleSides: Set<VolumeSide>.from(accessibleSides),
        doorOrigins: Map<VolumeSide, int>.from(doorOrigins),
      );
}

class Volume {
  Volume({
    required this.id,
    List<VolumeCell>? cells,
  }) : cells = cells ?? [];

  final int id;
  final List<VolumeCell> cells;

  /// Every accessible side on every cell. Volumes may have many doors.
  Set<VolumeSide> get accessibleSides => {
        for (final cell in cells) ...cell.accessibleSides,
      };

  bool get isMerged => cells.length > 1;

  VolumeCell? cellAt(int tx, int ty) {
    for (final cell in cells) {
      if (cell.tx == tx && cell.ty == ty) return cell;
    }
    return null;
  }

  Volume clone() => Volume(
        id: id,
        cells: [for (final cell in cells) cell.clone()],
      );

  /// Push-pull faces that are not shared with another cell of this mass.
  List<VolumeFacet> exteriorFacets() {
    final out = <VolumeFacet>[];
    for (final cell in cells) {
      for (final handle in VolumeHandle.values) {
        if (hasNeighborOn(cell, handle)) continue;
        out.add(VolumeFacet(cell: cell, handle: handle));
      }
    }
    return out;
  }

  /// True when another cell of this mass occupies the tile past [handle].
  bool hasNeighborOn(VolumeCell cell, VolumeHandle handle) {
    final delta = handle.tileDelta;
    if (delta == null) return false;
    return cellAt(cell.tx + delta.$1, cell.ty + delta.$2) != null;
  }
}

class VolumeFacet {
  const VolumeFacet({required this.cell, required this.handle});

  final VolumeCell cell;
  final VolumeHandle handle;
}

class VolumeGrowCandidate {
  const VolumeGrowCandidate({
    required this.volume,
    required this.source,
    required this.side,
    required this.tx,
    required this.ty,
  });

  final Volume volume;
  final VolumeCell source;
  final VolumeSide side;
  final int tx;
  final int ty;
}
