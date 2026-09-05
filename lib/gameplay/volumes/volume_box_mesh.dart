import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../geometry/geometry.dart';
import '../../geometry/geometries.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../../theme/world_theme.dart';
import '../viewers/world_plane.dart';
import 'volume.dart';
import 'volume_content_loader.dart';
import 'volume_door.dart';
import 'volume_solid.dart';
import 'volume_store.dart';

const kInteriorGroundMeshId = 'interior_ground';

String volumeMeshId(int volumeId, int tx, int ty) => 'volume_${volumeId}_${tx}_$ty';

Geometry volumeBoxGeometry({
  required Vector3 min,
  required Vector3 max,
  required String id,
  List<VolumeDoor> doors = const [],
  double subtileSize = 1,
  Set<VolumeHandle> omitHandles = const {},
  bool hideFloor = false,
}) {
  bool omit(VolumeHandle handle) => omitHandles.contains(handle);
  bool omitSide(VolumeSide side) => omit(side.handle);

  if (doors.isEmpty && omitHandles.isEmpty && !hideFloor) {
    return Geometry(
      id: id,
      name: 'VolumeBox',
      vertices: [
        Vector3(min.x, min.y, min.z),
        Vector3(max.x, min.y, min.z),
        Vector3(max.x, max.y, min.z),
        Vector3(min.x, max.y, min.z),
        Vector3(min.x, min.y, max.z),
        Vector3(max.x, min.y, max.z),
        Vector3(max.x, max.y, max.z),
        Vector3(min.x, max.y, max.z),
      ],
      faces: GeometryBuilders.cubeFaces,
    );
  }

  final vertices = <Vector3>[
    Vector3(min.x, min.y, min.z),
    Vector3(max.x, min.y, min.z),
    Vector3(max.x, max.y, min.z),
    Vector3(min.x, max.y, min.z),
    Vector3(min.x, min.y, max.z),
    Vector3(max.x, min.y, max.z),
    Vector3(max.x, max.y, max.z),
    Vector3(min.x, max.y, max.z),
  ];
  final faces = <List<int>>[];
  final holed = {for (final door in doors) door.side};

  if (!holed.contains(VolumeSide.north) && !omitSide(VolumeSide.north)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[0]));
  }
  if (!holed.contains(VolumeSide.south) && !omitSide(VolumeSide.south)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[1]));
  }
  if (!hideFloor) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[2])); // -Y floor
  }
  if (!omit(VolumeHandle.posY)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[3])); // +Y
  }
  if (!holed.contains(VolumeSide.east) && !omitSide(VolumeSide.east)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[4]));
  }
  if (!holed.contains(VolumeSide.west) && !omitSide(VolumeSide.west)) {
    faces.add(List<int>.from(GeometryBuilders.cubeFaces[5]));
  }

  void poly(List<Vector3> pts) {
    final cleaned = <Vector3>[];
    for (final p in pts) {
      if (cleaned.isEmpty || cleaned.last.distanceTo(p) > 1e-8) {
        cleaned.add(p);
      }
    }
    if (cleaned.length >= 2 &&
        cleaned.first.distanceTo(cleaned.last) <= 1e-8) {
      cleaned.removeLast();
    }
    if (cleaned.length < 3) return;
    final i = vertices.length;
    vertices.addAll(cleaned);
    faces.add([for (var k = 0; k < cleaned.length; k++) i + k]);
  }

  for (final door in doors) {
    if (omitSide(door.side)) continue;
    final s = subtileSize;
    final yD0 = min.y + door.originY * s;
    final yD1 = yD0 + door.height * s;
    switch (door.side) {
      case VolumeSide.east:
        {
          final x = max.x;
          final zD0 = min.z + door.originU * s;
          final zD1 = zD0 + door.width * s;
          poly([
            Vector3(x, min.y, min.z),
            Vector3(x, max.y, min.z),
            Vector3(x, max.y, max.z),
            Vector3(x, min.y, max.z),
            Vector3(x, min.y, zD1),
            Vector3(x, yD1, zD1),
            Vector3(x, yD1, zD0),
            Vector3(x, min.y, zD0),
          ]);
        }
      case VolumeSide.west:
        {
          final x = min.x;
          final zD0 = min.z + door.originU * s;
          final zD1 = zD0 + door.width * s;
          poly([
            Vector3(x, min.y, max.z),
            Vector3(x, max.y, max.z),
            Vector3(x, max.y, min.z),
            Vector3(x, min.y, min.z),
            Vector3(x, min.y, zD0),
            Vector3(x, yD1, zD0),
            Vector3(x, yD1, zD1),
            Vector3(x, min.y, zD1),
          ]);
        }
      case VolumeSide.south:
        {
          final z = max.z;
          final xD0 = min.x + door.originU * s;
          final xD1 = xD0 + door.width * s;
          poly([
            Vector3(min.x, min.y, z),
            Vector3(xD0, min.y, z),
            Vector3(xD0, yD1, z),
            Vector3(xD1, yD1, z),
            Vector3(xD1, min.y, z),
            Vector3(max.x, min.y, z),
            Vector3(max.x, max.y, z),
            Vector3(min.x, max.y, z),
          ]);
        }
      case VolumeSide.north:
        {
          final z = min.z;
          final xD0 = min.x + door.originU * s;
          final xD1 = xD0 + door.width * s;
          poly([
            Vector3(min.x, min.y, z),
            Vector3(min.x, max.y, z),
            Vector3(max.x, max.y, z),
            Vector3(max.x, min.y, z),
            Vector3(xD1, min.y, z),
            Vector3(xD1, yD1, z),
            Vector3(xD0, yD1, z),
            Vector3(xD0, min.y, z),
          ]);
        }
    }
  }

  return Geometry(
    id: id,
    name: 'VolumeBox',
    vertices: vertices,
    faces: faces,
  );
}

const double kVolumeCeilingHiddenOpacity = 0.02;

/// Default interior floor so the ground reads against paper walls.
const Color kVolumeFloorColor = Color(0xFF2A2A2E);

/// Faces whose vertices all sit on [plane] along [axis] (0=X, 1=Y, 2=Z).
List<int> volumePlanarFaceIndices(
  Geometry geometry,
  double plane, {
  int axis = 1,
}) {
  final out = <int>[];
  for (var i = 0; i < geometry.faces.length; i++) {
    final face = geometry.faces[i];
    if (face.isEmpty) continue;
    if (face.every((vi) {
      final v = geometry.vertices[vi];
      final coord = axis == 0
          ? v.x
          : axis == 2
              ? v.z
              : v.y;
      return (coord - plane).abs() < 1e-4;
    })) {
      out.add(i);
    }
  }
  return out;
}

/// Wall faces of [geometry] whose vertices sit on [face]'s outward plane.
List<int> volumeWallFaceIndices(
  Geometry geometry, {
  required VolumeFace face,
  required Vector3 min,
  required Vector3 max,
}) {
  return switch (face) {
    VolumeFace.posX => volumePlanarFaceIndices(geometry, max.x, axis: 0),
    VolumeFace.negX => volumePlanarFaceIndices(geometry, min.x, axis: 0),
    VolumeFace.posZ => volumePlanarFaceIndices(geometry, max.z, axis: 2),
    VolumeFace.negZ => volumePlanarFaceIndices(geometry, min.z, axis: 2),
    VolumeFace.posY || VolumeFace.negY => const [],
  };
}

/// Roof faces of [geometry] (every vertex sits on [roofY]).
List<int> volumeRoofFaceIndices(Geometry geometry, double roofY) =>
    volumePlanarFaceIndices(geometry, roofY);

/// Floor faces of [geometry] (every vertex sits on [floorY]).
List<int> volumeFloorFaceIndices(Geometry geometry, double floorY) =>
    volumePlanarFaceIndices(geometry, floorY);

/// Per-face colors: dark floor, optional faded roof / camera-cutaway walls.
List<Color>? volumeCellFaceColors({
  required Geometry geometry,
  required Color color,
  required double floorY,
  required double roofY,
  required double ceilingOpacity,
  Vector3? min,
  Vector3? max,
  Map<VolumeFace, double> wallOpacityByFace = const {},
}) {
  if (geometry.faces.isEmpty) return null;
  final floors = volumeFloorFaceIndices(geometry, floorY).toSet();
  final roofs = volumeRoofFaceIndices(geometry, roofY).toSet();
  final fadeRoof = ceilingOpacity > kVolumeCeilingHiddenOpacity &&
      ceilingOpacity < 0.999;
  final wallFaces = <int, double>{};
  if (min != null && max != null) {
    for (final face in const [
      VolumeFace.posX,
      VolumeFace.negX,
      VolumeFace.posZ,
      VolumeFace.negZ,
    ]) {
      final opacity = wallOpacityByFace[face] ?? 1;
      if (opacity >= 0.999) continue;
      for (final i in volumeWallFaceIndices(
        geometry,
        face: face,
        min: min,
        max: max,
      )) {
        wallFaces[i] = opacity;
      }
    }
  }
  if (floors.isEmpty && !fadeRoof && wallFaces.isEmpty) return null;
  final fadedRoof = fadeRoof ? color.withValues(alpha: ceilingOpacity) : color;
  return [
    for (var i = 0; i < geometry.faces.length; i++)
      if (floors.contains(i))
        kVolumeFloorColor
      else if (fadeRoof && roofs.contains(i))
        fadedRoof
      else if (wallFaces[i] case final opacity?)
        color.withValues(alpha: opacity)
      else
        color,
  ];
}

/// Syncs wireframe box meshes on [scene] to match [store].
void syncVolumeMeshes(
  Scene scene,
  VolumeStore store, {
  Color? committed,
  Color? draftColor,
  Set<int> hideCeilingVolumeIds = const {},
  Set<int> hiddenByDatumVolumeIds = const {},
  Set<int> inwardWallsOnlyVolumeIds = const {},
  Map<VolumePartId, double> ceilingOpacityByPart = const {},
  double Function(int tx, int ty, VolumeFace face)? wallOpacityForFace,
}) {
  final wanted = <String>{};
  final draft = store.draftVolume;

  for (final volume in store.visibleVolumes) {
    if (hiddenByDatumVolumeIds.contains(volume.id)) continue;
    final solid = resolveVolumeSolid(volume, store.grid);
    final hideVolumeCeiling = hideCeilingVolumeIds.contains(volume.id);
    final inwardOnly = inwardWallsOnlyVolumeIds.contains(volume.id);
    final isDraftVolume = identical(volume, draft);
    for (final cell in volume.cells) {
      final id = volumeMeshId(volume.id, cell.tx, cell.ty);
      wanted.add(id);
      final partOpacity =
          ceilingOpacityByPart[VolumePartId(cell.tx, cell.ty)] ?? 1.0;
      final ceilingOpacity = hideVolumeCeiling ? 0.0 : partOpacity;
      final hideCeiling = ceilingOpacity <= kVolumeCeilingHiddenOpacity;
      final hideFloor = ceilingOpacity >= 0.999;
      final wallOpacity = <VolumeFace, double>{
        for (final face in const [
          VolumeFace.posX,
          VolumeFace.negX,
          VolumeFace.posZ,
          VolumeFace.negZ,
        ])
          face: wallOpacityForFace?.call(cell.tx, cell.ty, face) ?? 1,
      };
      final omitWalls = <VolumeHandle>{
        for (final handle in const [
          VolumeHandle.posX,
          VolumeHandle.negX,
          VolumeHandle.posZ,
          VolumeHandle.negZ,
        ])
          if ((wallOpacity[faceForHandle(handle)] ?? 1) <=
              kVolumeCeilingHiddenOpacity)
            handle,
      };
      final geometry = volumeSolidCellGeometry(
        cell: cell,
        solid: solid,
        grid: store.grid,
        id: id,
        hideCeiling: hideCeiling,
        hideFloor: hideFloor,
        inwardWallsOnly: inwardOnly,
        omitWalls: omitWalls,
      );
      final highlightDraftCell =
          store.isEditing &&
          isDraftVolume &&
          store.draftCell?.tx == cell.tx &&
          store.draftCell?.ty == cell.ty;
      final color = highlightDraftCell
          ? (draftColor ?? committed ?? WorldTheme.paperDiorama.volume)
          : (committed ?? WorldTheme.paperDiorama.volume);
      final min = cell.box.worldMin(store.grid, cell.tx, cell.ty);
      final max = cell.box.worldMax(store.grid, cell.tx, cell.ty);
      final faceColors = volumeCellFaceColors(
        geometry: geometry,
        color: color,
        floorY: min.y,
        roofY: max.y,
        ceilingOpacity: ceilingOpacity,
        min: min,
        max: max,
        wallOpacityByFace: wallOpacity,
      );
      final existing = scene.meshById(id);
      final material = MaterialModel(
        color: color,
        wireframe: false,
        strokeEdges: false,
        doubleSided: !inwardOnly,
        perFaceColors: faceColors,
        exactPerFaceColors: faceColors != null,
      );
      if (existing == null) {
        scene.addMesh(
          Mesh(
            id: id,
            name: 'Volume',
            geometry: geometry,
            material: material,
          ),
        );
      } else {
        existing.geometry = geometry;
        existing.material = material;
      }
    }
  }

  for (final mesh in List<Mesh>.from(scene.meshes)) {
    if (mesh.id.startsWith('volume_') && !wanted.contains(mesh.id)) {
      scene.removeMeshById(mesh.id);
    }
  }
  scene.markNeedsPaint();
}

/// Near-black ground used while a volume is in interior view.
void syncInteriorGround(
  Scene scene, {
  required bool enabled,
  required VolumeGrid grid,
}) {
  if (!enabled) {
    scene.removeMeshById(kInteriorGroundMeshId);
    scene.markNeedsPaint();
    return;
  }
  final half = grid.mapHalf * 4;
  final geometry = Geometry(
    id: kInteriorGroundMeshId,
    name: 'InteriorGround',
    vertices: [
      Vector3(-half, -0.02, -half),
      Vector3(half, -0.02, -half),
      Vector3(half, -0.02, half),
      Vector3(-half, -0.02, half),
    ],
    faces: const [
      [0, 1, 2, 3],
    ],
  );
  final material = const MaterialModel(
    color: Color(0xFF050508),
    doubleSided: true,
    wireframe: false,
    strokeEdges: false,
  );
  final existing = scene.meshById(kInteriorGroundMeshId);
  if (existing == null) {
    scene.addMesh(
      Mesh(
        id: kInteriorGroundMeshId,
        name: 'InteriorGround',
        geometry: geometry,
        material: material,
      ),
    );
  } else {
    existing.geometry = geometry;
    existing.material = material;
  }
  scene.markNeedsPaint();
}

Geometry volumeSolidCellGeometry({
  required VolumeCell cell,
  required VolumeSolid solid,
  required VolumeGrid grid,
  required String id,
  List<VolumeDoor> doors = const [],
  bool hideCeiling = false,
  bool hideFloor = false,
  bool inwardWallsOnly = false,
  Set<VolumeHandle> omitWalls = const {},
}) {
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  final s = grid.subtileSize;
  final omitHandles = <VolumeHandle>{
    for (final handle in VolumeHandle.values)
      if (solid.isHandleFullyInternal(cell.tx, cell.ty, handle) ||
          (hideCeiling && handle == VolumeHandle.posY) ||
          omitWalls.contains(handle))
        handle,
  };

  final completeDoors = [
    for (final door in doors)
      if (solid.surfaceAt(cell.tx, cell.ty, door.side.handle)?.isComplete ??
          false)
        door,
  ];
  final allComplete = VolumeHandle.values.every((handle) {
    if (omitHandles.contains(handle)) return true;
    if (handle == VolumeHandle.posY && hideCeiling) return true;
    return solid.surfaceAt(cell.tx, cell.ty, handle)?.isComplete ?? false;
  });
  if (allComplete && !inwardWallsOnly) {
    return volumeBoxGeometry(
      min: min,
      max: max,
      id: id,
      doors: completeDoors,
      subtileSize: s,
      omitHandles: omitHandles,
      hideFloor: hideFloor,
    );
  }

  final vertices = <Vector3>[];
  final faces = <List<int>>[];

  void addQuad(List<Vector3> pts, {required bool inward}) {
    final ordered = inward ? pts.reversed.toList() : pts;
    final i = vertices.length;
    vertices.addAll(ordered);
    faces.add([i, i + 1, i + 2, i + 3]);
  }

  if (!hideFloor) {
    addQuad([
      Vector3(min.x, min.y, min.z),
      Vector3(max.x, min.y, min.z),
      Vector3(max.x, min.y, max.z),
      Vector3(min.x, min.y, max.z),
    ], inward: false);
  }

  for (final handle in VolumeHandle.values) {
    if (omitHandles.contains(handle)) continue;
    final surface = solid.surfaceAt(cell.tx, cell.ty, handle);
    if (surface == null) continue;
    final door = completeDoors
        .where((d) => d.side.handle == handle)
        .firstOrNull;
    if (door != null && surface.isComplete && !inwardWallsOnly) {
      final holed = volumeBoxGeometry(
        min: min,
        max: max,
        id: '${id}_door',
        doors: [door],
        subtileSize: s,
        omitHandles: {
          for (final other in VolumeHandle.values)
            if (other != handle) other,
        },
        hideFloor: true,
      );
      final base = vertices.length;
      vertices.addAll(holed.vertices);
      for (final face in holed.faces) {
        faces.add([for (final i in face) i + base]);
      }
      continue;
    }
    final inward = inwardWallsOnly && surface.kind == VolumeSurfaceKind.wall;
    for (final fragment in surface.fragments) {
      addQuad(
        volumeFaceFragmentQuad(
          min: min,
          max: max,
          handle: handle,
          fragment: fragment,
          subtileSize: s,
        ),
        inward: inward,
      );
    }
  }

  return Geometry(
    id: id,
    name: 'VolumeBox',
    vertices: vertices,
    faces: faces,
  );
}

