import 'dart:math' as math;
import 'dart:ui' show Color;

import 'package:vector_math/vector_math_64.dart';

import '../geometry.dart';
import '../svg_path_parser.dart';
import '../../tiles/tiles.dart';

/// Available geometry prefabs that can be instantiated in the scene
enum GeometryPrefabs { house, cube, tallHouse, frog, cone, tree }

/// Base sizes of geometry prefabs at scale 1.0
/// These define the largest dimension (width or diameter) of each geometry
const Map<GeometryPrefabs, double> geometryBaseSizes = {
  GeometryPrefabs.cube: 120.0, // 120 units wide
  GeometryPrefabs.frog: 160.0, // 160 units diameter (2 * 80 radius)
  GeometryPrefabs.cone: 160.0, // 160 units diameter (2 * 80 radius)
  GeometryPrefabs.house: 512.0, // 512 units (512x512 base)
  GeometryPrefabs.tallHouse: 512.0, // 512 units (512x512 base, twice as tall)
  GeometryPrefabs.tree: 512.0, // 512 units, matches house scale
};

/// Calculate the scale factor for a geometry to fit a desired size
///
/// [geometryType] - The type of geometry to scale
/// [desiredSize] - The desired size in world units
/// [tileSize] - Optional tile size for relative scaling (e.g., 0.5 for half a tile)
///
/// Example: To make a cube half the size of a 220-unit tile:
///   `calculateGeometryScale(GeometryPrefabs.cube, 110)` or
///   `calculateGeometryScale(GeometryPrefabs.cube, 0.5, tileSize: 220)`
double calculateGeometryScale(
  GeometryPrefabs geometryType,
  double desiredSize, {
  double? tileSize,
}) {
  final targetSize = tileSize != null ? desiredSize * tileSize : desiredSize;
  final baseSize = geometryBaseSizes[geometryType] ?? 120.0;
  return targetSize / baseSize;
}

Geometry buildGeometry(
  GeometryFeature feature, {
  int? colorSeed,
  bool triangulate = false,
}) {
  switch (feature.geometry) {
    case GeometryPrefabs.house:
      return _buildHouseGeometry(feature.scale, colorSeed: colorSeed);
    case GeometryPrefabs.tallHouse:
      return _buildTallHouseGeometry(feature.scale, colorSeed: colorSeed);
    case GeometryPrefabs.cube:
      return _buildCubeGeometry(feature.scale, colorSeed: colorSeed);
    case GeometryPrefabs.frog:
      return _buildFrogGeometry(feature.scale, colorSeed: colorSeed);
    case GeometryPrefabs.cone:
      return _buildConeGeometry(feature.scale, colorSeed: colorSeed);
    case GeometryPrefabs.tree:
      return _buildTreeGeometry(
        feature.scale,
        colorSeed: colorSeed,
        triangulate: triangulate,
      );
  }
}

Geometry _buildCubeGeometry(double scale, {int? colorSeed}) {
  final size = 120 * scale;
  final half = size / 2;
  // Centered cube: all axes from -half to +half
  // This ensures the cube is centered at the origin in world coordinates,
  // which makes it centered on the tile when rendered isometrically
  final vertices = <Vector3>[
    Vector3(-half, -half, -half), // bottom vertices
    Vector3(half, -half, -half),
    Vector3(half, -half, half),
    Vector3(-half, -half, half),
    Vector3(-half, half, -half), // top vertices
    Vector3(half, half, -half),
    Vector3(half, half, half),
    Vector3(-half, half, half),
  ];
  const faces = _cubeFaces;
  final geometry = Geometry(
    id: 'geometryCube',
    name: 'Cube Geometry',
    vertices: vertices,
    faces: faces,
    colorSeed: colorSeed,
  );
  return ensureOutwardFacingGeometry(geometry);
}

Geometry _buildHouseGeometry(double scale, {int? colorSeed}) {
  final width = 512 * scale;
  final depth = 512 * scale;
  final wallHeight = 320 * scale;
  final roofPeak = 200 * scale;
  final halfWidth = width / 2;
  final halfDepth = depth / 2;

  final front = [
    Vector3(-halfWidth, 0, -halfDepth),
    Vector3(halfWidth, 0, -halfDepth),
    Vector3(halfWidth, wallHeight, -halfDepth),
    Vector3(0, wallHeight + roofPeak, -halfDepth),
    Vector3(-halfWidth, wallHeight, -halfDepth),
  ];
  final back = front
      .map((vertex) => Vector3(vertex.x, vertex.y, halfDepth))
      .toList();

  final vertices = <Vector3>[...front, ...back];

  final faces = <List<int>>[
    [0, 1, 2, 3, 4],
    [9, 8, 7, 6, 5],
    [0, 1, 6, 5],
    [1, 2, 7, 6],
    [2, 3, 8, 7],
    [3, 4, 9, 8],
    [4, 0, 5, 9],
  ];

  final geometry = Geometry(
    id: 'geometryHouse',
    name: 'House Geometry',
    vertices: vertices,
    faces: faces,
    colorSeed: colorSeed,
  );
  return ensureOutwardFacingGeometry(geometry);
}

Geometry _buildTallHouseGeometry(double scale, {int? colorSeed}) {
  final width = 512 * scale;
  final depth = 512 * scale;
  final wallHeight = 320 * scale;
  final roofPeak = 200 * scale;
  final halfWidth = width / 2;
  final halfDepth = depth / 2;

  // Extend walls upward by one tile edge length (512 units) to make it twice as tall
  final extraHeight = 512 * scale;
  final tallWallHeight = wallHeight + extraHeight;

  final front = [
    Vector3(-halfWidth, 0, -halfDepth), // Base stays at ground level (y=0)
    Vector3(halfWidth, 0, -halfDepth),
    Vector3(halfWidth, tallWallHeight, -halfDepth), // Walls extend up
    Vector3(0, tallWallHeight + roofPeak, -halfDepth), // Roof peak also higher
    Vector3(-halfWidth, tallWallHeight, -halfDepth),
  ];
  final back = front
      .map((vertex) => Vector3(vertex.x, vertex.y, halfDepth))
      .toList();

  final vertices = <Vector3>[...front, ...back];

  final faces = <List<int>>[
    [0, 1, 2, 3, 4],
    [9, 8, 7, 6, 5],
    [0, 1, 6, 5],
    [1, 2, 7, 6],
    [2, 3, 8, 7],
    [3, 4, 9, 8],
    [4, 0, 5, 9],
  ];

  final geometry = Geometry(
    id: 'geometryTallHouse',
    name: 'Tall House Geometry',
    vertices: vertices,
    faces: faces,
    colorSeed: colorSeed,
  );
  return ensureOutwardFacingGeometry(geometry);
}

Geometry _buildFrogGeometry(double scale, {int? colorSeed}) {
  final radius = 80 * scale;
  final height = 160 * scale;

  Vector3 baseVertex(double angle) =>
      Vector3(radius * math.cos(angle), 0, radius * math.sin(angle));
  Vector3 topVertex(double angle) =>
      Vector3(radius * math.cos(angle), height, radius * math.sin(angle));

  final angles = List.generate(6, (i) => (math.pi / 6) + i * math.pi / 3);
  final vertices = <Vector3>[
    ...angles.map(baseVertex),
    ...angles.map(topVertex),
  ];

  final faces = <List<int>>[
    [0, 1, 2, 3, 4, 5],
    [11, 10, 9, 8, 7, 6],
    [0, 6, 7, 1],
    [1, 7, 8, 2],
    [2, 8, 9, 3],
    [3, 9, 10, 4],
    [4, 10, 11, 5],
    [5, 11, 6, 0],
  ];

  final geometry = Geometry(
    id: 'geometryFrog',
    name: 'Frog Geometry',
    vertices: vertices,
    faces: faces,
    colorSeed: colorSeed,
  );
  return ensureOutwardFacingGeometry(geometry);
}

Geometry _buildConeGeometry(double scale, {int? colorSeed}) {
  final radius = 80 * scale;
  final height = 160 * scale;
  const sides = 12;

  // Base vertices (circle at y=0)
  final baseVertices = List.generate(sides, (i) {
    final angle = i * 2 * math.pi / sides;
    return Vector3(radius * math.cos(angle), 0, radius * math.sin(angle));
  });

  // Apex vertex at top
  final apex = Vector3(0, height, 0);

  final vertices = <Vector3>[...baseVertices, apex];
  final apexIndex = sides;

  // Faces: base polygon + triangle side faces
  final faces = <List<int>>[
    // Base (reversed winding for outward-facing downward normal)
    List.generate(sides, (i) => sides - 1 - i),
    // Side triangles
    for (var i = 0; i < sides; i++) [i, (i + 1) % sides, apexIndex],
  ];

  final geometry = Geometry(
    id: 'geometryCone',
    name: 'Cone Geometry',
    vertices: vertices,
    faces: faces,
    colorSeed: colorSeed,
  );
  return ensureOutwardFacingGeometry(geometry);
}

/// Tree silhouette SVG path (100x100 viewbox, trunk at bottom, round canopy).
/// Styled after a typical NounProject tree icon (ID 1857613).
const String _treeSvgPath =
    'M 45,100 L 45,68 '
    'C 20,65 5,45 15,28 '
    'C 22,14 38,5 50,5 '
    'C 62,5 78,14 85,28 '
    'C 95,45 80,65 55,68 '
    'L 55,100 Z';

/// Splits a closed polygon outline along x=0 into two sub-polygons (x≤0 and
/// x≥0). Edge intersections with the axis are interpolated so both halves form
/// valid closed polygons. Vertices exactly on the axis appear in both halves.
///
/// Used for perpendicular-plane geometries (two intersecting SVG silhouettes)
/// so the painter's algorithm can depth-sort the resulting non-intersecting
/// half-planes instead of struggling with coplanar intersections.
(List<Vector3>, List<Vector3>) splitOutlineAtXZero(List<Vector3> outline) {
  final left = <Vector3>[];
  final right = <Vector3>[];
  final n = outline.length;

  for (var i = 0; i < n; i++) {
    final curr = outline[i];
    final next = outline[(i + 1) % n];

    if (curr.x <= 0) left.add(curr);
    if (curr.x >= 0) right.add(curr);

    final crosses =
        (curr.x < 0 && next.x > 0) || (curr.x > 0 && next.x < 0);
    if (crosses) {
      final t = -curr.x / (next.x - curr.x);
      final ix = Vector3(
        0,
        curr.y + t * (next.y - curr.y),
        curr.z + t * (next.z - curr.z),
      );
      left.add(ix);
      right.add(ix);
    }
  }

  return (left, right);
}

Geometry _buildTreeGeometry(
  double scale, {
  int? colorSeed,
  bool triangulate = false,
}) {
  final parser = SvgPathParser(curveTolerance: 2.0);
  final outline = parser.parse(_treeSvgPath, targetSize: 512.0 * scale);
  if (outline.isEmpty) {
    return _buildConeGeometry(scale, colorSeed: colorSeed);
  }

  // Split the outline at x=0 so each intersecting plane becomes two
  // non-overlapping half-planes that the painter's algorithm can sort.
  final (leftHalf, rightHalf) = splitOutlineAtXZero(outline);

  final vertices = <Vector3>[];
  final faces = <List<int>>[];

  void addHalf(List<Vector3> half, Vector3 Function(Vector3 v) transform) {
    if (half.length < 3) return;
    final offset = vertices.length;
    for (final v in half) {
      vertices.add(transform(v));
    }
    if (triangulate) {
      final tris = triangulatePolygon(half);
      for (final tri in tris) {
        faces.add([tri[0] + offset, tri[1] + offset, tri[2] + offset]);
      }
    } else {
      faces.add(List.generate(half.length, (i) => i + offset));
    }
  }

  // Plane 1 (XY, z=0): left and right halves
  addHalf(leftHalf, (v) => Vector3(v.x, v.y, 0));
  addHalf(rightHalf, (v) => Vector3(v.x, v.y, 0));

  // Plane 2 (YZ, x=0): same halves rotated 90° around Y
  addHalf(leftHalf, (v) => Vector3(0, v.y, v.x));
  addHalf(rightHalf, (v) => Vector3(0, v.y, v.x));

  // Assign slightly different base colors to the two perpendicular planes so
  // the tree reads as two distinct cross-sections rather than a flat shape.
  // Plane 1 faces get a warm-shifted white; Plane 2 gets a cool-shifted white.
  // Actual hue comes from the tint applied at instance level.
  final faceColors = <Color>[
    for (var i = 0; i < faces.length; i++)
      i < 2
          ? const Color(0xFFFFFFFF)  // Plane 1: neutral
          : const Color(0xFFE8E8F0), // Plane 2: slightly cool / darker
  ];

  final geometry = Geometry(
    id: 'geometryTree',
    name: 'Tree Geometry',
    vertices: vertices,
    faces: faces,
    colorSeed: colorSeed,
    faceColors: faceColors,
  );
  return ensureOutwardFacingGeometry(geometry);
}

const List<List<int>> _cubeFaces = <List<int>>[
  [0, 3, 2, 1],
  [4, 5, 6, 7],
  [0, 1, 5, 4],
  [3, 7, 6, 2],
  [1, 2, 6, 5],
  [0, 4, 7, 3],
];
