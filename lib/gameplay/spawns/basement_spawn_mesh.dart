import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../rendering/ground_occlusion.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/camera.dart';
import '../../rendering/scene/scene.dart';
import '../../theme/world_theme.dart';
import '../outlines/outline_edges.dart';
import '../paths/path_shape.dart';
import '../viewers/world_plane.dart';
import '../volumes/volume.dart';
import '../volumes/volume_box_mesh.dart';
import '../volumes/volume_door.dart';
import 'basement_spawn.dart';

const kBasementSpawnDeckId = 'basement_spawn_deck';
const kBasementSpawnPathId = 'basement_spawn_path';
const kBasementSpawnCutId = 'basement_spawn_cut';
const kBasementSpawnDoorId = 'basement_spawn_door';

const _kPathLift = 0.02;

/// Sloped tiles plus a 4-subtile path along the punched ramp.
void syncBasementSpawnMeshes(
  Scene scene,
  VolumeGrid grid, {
  Color? pathColor,
  Color? wallColor,
}) {
  final occlusion = basementGroundOcclusion(grid);
  final pathX = basementRampPathX(grid);
  final path = Mesh(
    id: kBasementSpawnPathId,
    name: 'BasementSpawnPath',
    geometry: _slopedStripGeometry(
      grid,
      id: kBasementSpawnPathId,
      name: 'BasementSpawnPath',
      x0: pathX.x0,
      x1: pathX.x1,
      yLift: _kPathLift,
    ),
    material: MaterialModel(
      color: pathColor ?? WorldTheme.paperDiorama.path,
      doubleSided: true,
      strokeEdges: false,
      surfaceGrid: false,
    ),
    groundPlane: true,
    groundOcclusion: occlusion,
  );
  _upsert(scene, path);
  final door = basementCutDoorWall(
    grid,
    color: wallColor ?? WorldTheme.paperDiorama.volume,
  );
  _upsert(
    scene,
    Mesh(
      id: kBasementSpawnDoorId,
      name: 'BasementSpawnDoor',
      geometry: basementDoorWallFillGeometry(grid),
      material: MaterialModel(
        color: door.color,
        doubleSided: true,
        strokeEdges: false,
        wireframe: false,
      ),
      groundOcclusion: GroundOcclusion(
        holeTiles: BasementSpawn.cutTileSet,
        tileSize: grid.tileSize,
        groundHole: GroundHoleRect.fromTiles(
          BasementSpawn.cutTileSet,
          grid.tileSize,
        ),
      ),
    ),
  );
  scene.removeMeshById(kBasementSpawnDeckId);
  scene.removeMeshById(kBasementSpawnCutId);
  scene.markNeedsPaint();
}

void _upsert(Scene scene, Mesh mesh) {
  final existing = scene.meshById(mesh.id);
  if (existing == null) {
    scene.addMesh(mesh);
    return;
  }
  existing.geometry = mesh.geometry;
  existing.material = mesh.material;
  existing.groundPlane = mesh.groundPlane;
  existing.groundOcclusion = mesh.groundOcclusion;
}

/// Centered 4-subtile corridor, same inset as [pathFootprints].
({double x0, double x1}) basementRampPathX(VolumeGrid grid) {
  final n = grid.subtilesPerTile;
  final wide = kPathWidthSubtiles;
  final origin = (n - wide) ~/ 2;
  final x = grid.tileOrigin(0, 1).x;
  final s = grid.subtileSize;
  return (x0: x + origin * s, x1: x + (origin + wide) * s);
}

/// Sloped path paper quads, flush with the (0,2) north stub at Y=0.
List<OutlineQuad> basementRampPathOutlineQuads(VolumeGrid grid) {
  final pathX = basementRampPathX(grid);
  final s = grid.subtileSize;
  final zSouth = grid.tileOrigin(0, 1).z + grid.tileSize;
  final zNorth = grid.tileOrigin(0, -2).z;
  final segs = ((zSouth - zNorth) / s).round().clamp(1, 128);
  final quads = <OutlineQuad>[];
  for (var i = 0; i < segs; i++) {
    final z0 = zSouth - i * s;
    final z1 = zSouth - (i + 1) * s;
    final y0 = basementRampHeight(grid, z0);
    final y1 = basementRampHeight(grid, z1);
    final a = Vector3(pathX.x0, y0, z0);
    final b = Vector3(pathX.x1, y0, z0);
    final c = Vector3(pathX.x1, y1, z1);
    final d = Vector3(pathX.x0, y1, z1);
    final n = (b - a).cross(d - a);
    quads.add(
      OutlineQuad(
        points: [a, b, c, d],
        normal: n.length2 < 1e-12 ? Vector3(0, 1, 0) : n.normalized(),
      ),
    );
  }
  return quads;
}

/// South face of [BasementSpawn.doorTile]: the (0,0)/(0,-1) seam.
class BasementDoorSpec {
  const BasementDoorSpec({
    required this.box,
    required this.door,
    required this.tx,
    required this.ty,
    required this.yLift,
    required this.min,
    required this.max,
  });

  final BoxPrimitive box;
  final VolumeDoor door;
  final int tx;
  final int ty;
  final double yLift;
  final Vector3 min;
  final Vector3 max;
}

/// Volume-sized wall on the south face of (0,-1), seated on the ramp.
BasementDoorSpec basementDoorSpec(VolumeGrid grid) {
  final z = grid.tileOrigin(0, 0).z;
  final yLift = basementRampHeight(grid, z);
  final height = math.max(
    kDoorHeightSubtiles,
    ((0 - yLift) / grid.subtileSize).round(),
  );
  const tx = 0;
  const ty = -1;
  final box = BoxPrimitive(
    widthSubtiles: grid.subtilesPerTile,
    depthSubtiles: grid.subtilesPerTile,
    heightSubtiles: height,
  );
  final door = volumeDoorForSide(box, VolumeSide.south)!;
  final min = box.worldMin(grid, tx, ty);
  final max = box.worldMax(grid, tx, ty);
  min.y += yLift;
  max.y += yLift;
  return BasementDoorSpec(
    box: box,
    door: door,
    tx: tx,
    ty: ty,
    yLift: yLift,
    min: min,
    max: max,
  );
}

/// Wall to wall, Y=0 down to the ramp. Does not rise above the plane.
({double x0, double x1, double y0, double y1, double z}) basementDoorBounds(
  VolumeGrid grid,
) {
  final spec = basementDoorSpec(grid);
  return (
    x0: spec.min.x,
    x1: spec.max.x,
    y0: spec.min.y,
    y1: spec.max.y,
    z: spec.max.z,
  );
}

/// Same holed south face [volumeBoxGeometry] uses for a volume door.
Geometry basementDoorWallGeometry(VolumeGrid grid) {
  final spec = basementDoorSpec(grid);
  return volumeBoxGeometry(
    min: spec.min,
    max: spec.max,
    id: kBasementSpawnDoorId,
    doors: [spec.door],
    subtileSize: grid.subtileSize,
    omitHandles: {
      VolumeHandle.posX,
      VolumeHandle.negX,
      VolumeHandle.negZ,
      VolumeHandle.posY,
    },
    hideFloor: true,
  );
}

/// 2×4 path paper, CCW from the hole (same as [doorWorldCorners]).
List<Vector3> basementDoorPaperCorners(VolumeGrid grid) {
  final spec = basementDoorSpec(grid);
  return [
    for (final p in doorWorldCorners(
      grid: grid,
      tx: spec.tx,
      ty: spec.ty,
      box: spec.box,
      door: spec.door,
    ))
      Vector3(p.x, p.y + spec.yLift, p.z),
  ];
}

List<OutlineEdge> basementDoorWallOutline(VolumeGrid grid) {
  final geo = basementDoorWallGeometry(grid);
  if (geo.faces.isEmpty) return const [];
  final face = geo.faces.first;
  return collectOuterEdges([
    OutlineQuad(
      points: [for (final i in face) geo.vertices[i]],
      normal: VolumeSide.south.volumeFace.worldNormal,
    ),
  ]);
}

List<OutlineEdge> basementDoorPaperOutline(VolumeGrid grid) {
  return collectOuterEdges([
    OutlineQuad(
      points: basementDoorPaperCorners(grid),
      normal: VolumeSide.south.volumeFace.worldNormal,
    ),
  ]);
}

/// Path-colored facade on the hole / bridge seam. Only the 2×4 door is open.
class BasementCutDoorWall {
  const BasementCutDoorWall({
    required this.x0,
    required this.x1,
    required this.yTop,
    required this.yFloor,
    required this.z,
    required this.doorX0,
    required this.doorX1,
    required this.doorY0,
    required this.doorY1,
    required this.color,
  });

  final double x0;
  final double x1;
  final double yTop;
  final double yFloor;
  final double z;
  final double doorX0;
  final double doorX1;
  final double doorY0;
  final double doorY1;
  final Color color;

  /// Left jamb, right jamb, then lintel. Opening stays empty.
  List<List<Vector3>> get fillQuads {
    final quads = <List<Vector3>>[
      [
        Vector3(x0, yTop, z),
        Vector3(x0, yFloor, z),
        Vector3(doorX0, yFloor, z),
        Vector3(doorX0, yTop, z),
      ],
      [
        Vector3(doorX1, yTop, z),
        Vector3(doorX1, yFloor, z),
        Vector3(x1, yFloor, z),
        Vector3(x1, yTop, z),
      ],
    ];
    if (yTop - doorY1 > 1e-6) {
      quads.add([
        Vector3(doorX0, yTop, z),
        Vector3(doorX0, doorY1, z),
        Vector3(doorX1, doorY1, z),
        Vector3(doorX1, yTop, z),
      ]);
    }
    return quads;
  }
}

BasementCutDoorWall basementCutDoorWall(
  VolumeGrid grid, {
  Color? color,
}) {
  final spec = basementDoorSpec(grid);
  final s = grid.subtileSize;
  return BasementCutDoorWall(
    x0: spec.min.x,
    x1: spec.max.x,
    yTop: spec.max.y,
    yFloor: spec.min.y,
    z: spec.max.z,
    doorX0: spec.min.x + spec.door.originU * s,
    doorX1: spec.min.x + (spec.door.originU + spec.door.width) * s,
    doorY0: spec.min.y + spec.door.originY * s,
    doorY1: spec.min.y + (spec.door.originY + spec.door.height) * s,
    color: color ?? WorldTheme.paperDiorama.volume,
  );
}

List<List<Vector3>> basementDoorWallFillQuads(VolumeGrid grid) =>
    basementCutDoorWall(grid).fillQuads;

Geometry basementDoorWallFillGeometry(VolumeGrid grid) {
  final verts = <Vector3>[];
  final faces = <List<int>>[];
  for (final quad in basementDoorWallFillQuads(grid)) {
    final i = verts.length;
    verts.addAll(quad);
    faces.add([i, i + 1, i + 2, i + 3]);
  }
  return Geometry(
    id: kBasementSpawnDoorId,
    name: 'BasementSpawnDoor',
    vertices: verts,
    faces: faces,
  );
}

WallHoleOccluder wallHoleOccluderFromDoor(BasementCutDoorWall door) {
  return WallHoleOccluder(
    z: door.z,
    x0: door.x0,
    x1: door.x1,
    y0: door.yFloor,
    y1: door.yTop,
    holeX0: door.doorX0,
    holeX1: door.doorX1,
    holeY0: door.doorY0,
    holeY1: door.doorY1,
  );
}

/// Whole facade: visible through the hole, hidden under the map. One bit.
bool basementDoorFacadeVisible(
  Camera camera,
  BasementCutDoorWall door,
  GroundOcclusion hole,
) {
  final probe = Vector3(
    (door.x0 + door.x1) * 0.5,
    (door.yTop + door.yFloor) * 0.5,
    door.z + 0.25,
  );
  return visibleThroughGround(camera, probe, hole);
}

GroundOcclusion basementGroundOcclusion(
  VolumeGrid grid, {
  bool clipPartial = true,
  bool occludeDoorWall = true,
}) {
  return GroundOcclusion(
    holeTiles: BasementSpawn.cutTileSet,
    tileSize: grid.tileSize,
    clipPartial: clipPartial,
    wallHole: occludeDoorWall
        ? wallHoleOccluderFromDoor(basementCutDoorWall(grid))
        : null,
    groundHole: GroundHoleRect.fromTiles(
      BasementSpawn.cutTileSet,
      grid.tileSize,
    ),
  );
}

/// Height of the ramp surface at world [z]. Y=0 at the south edge of (0,1).
///
/// Same slope as the original two-tile drop (half a world unit per unit of Z),
/// continued through (0,-1) and (0,-2).
double basementRampHeight(VolumeGrid grid, double z) {
  final topZ = grid.tileOrigin(0, 1).z + grid.tileSize;
  final bottomZ = grid.tileOrigin(0, -2).z;
  if (z >= topZ) return 0;
  if (z <= bottomZ) return -(topZ - bottomZ) * 0.5;
  return -(topZ - z) * 0.5;
}

/// Subtile-sized sloped quads so ground occlusion can clip a clean silhouette.
Geometry _slopedStripGeometry(
  VolumeGrid grid, {
  required String id,
  required String name,
  required double x0,
  required double x1,
  double yLift = 0,
}) {
  final s = grid.subtileSize;
  final zSouth = grid.tileOrigin(0, 1).z + grid.tileSize;
  final zNorth = grid.tileOrigin(0, -2).z;
  final zSegs = ((zSouth - zNorth) / s).round().clamp(1, 128);
  final xSegs = ((x1 - x0) / s).round().clamp(1, 32);
  final verts = <Vector3>[];
  final faces = <List<int>>[];
  for (var iz = 0; iz < zSegs; iz++) {
    final za = zSouth - iz * s;
    final zb = zSouth - (iz + 1) * s;
    final y0 = basementRampHeight(grid, za) + yLift;
    final y1 = basementRampHeight(grid, zb) + yLift;
    for (var ix = 0; ix < xSegs; ix++) {
      final xa = x0 + ix * s;
      final xb = x0 + (ix + 1) * s;
      final b = verts.length;
      verts.addAll([
        Vector3(xa, y0, za),
        Vector3(xb, y0, za),
        Vector3(xb, y1, zb),
        Vector3(xa, y1, zb),
      ]);
      faces.add([b, b + 3, b + 2, b + 1]);
    }
  }
  return Geometry(id: id, name: name, vertices: verts, faces: faces);
}
