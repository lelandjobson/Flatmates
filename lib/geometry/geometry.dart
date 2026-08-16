import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

class Geometry {
  factory Geometry({
    required String id,
    required String name,
    required List<Vector3> vertices,
    required List<List<int>> faces,
    int? colorSeed,
    List<Color>? faceColors,
  }) {
    if (colorSeed != null) {
      // Use provided seed for stable colors
      final uuid = _GeometryUuid.generate();
      return Geometry._(
        id: id,
        name: name,
        vertices: vertices,
        faces: faces,
        uuid: uuid,
        colorSeed: colorSeed,
        faceColors: faceColors,
      );
    }
    // Generate random identity for dynamic colors
    final identity = _GeometryUuid.generateIdentity();
    return Geometry._(
      id: id,
      name: name,
      vertices: vertices,
      faces: faces,
      uuid: identity.uuid,
      colorSeed: identity.seed,
      faceColors: faceColors,
    );
  }

  Geometry._({
    required this.id,
    required this.name,
    required this.vertices,
    required this.faces,
    required this.uuid,
    required this.colorSeed,
    this.faceColors,
  });

  final String id;
  final String name;
  final List<Vector3> vertices;
  final List<List<int>> faces;
  final String uuid;
  final int colorSeed;

  /// Optional per-face base colors (parallel to [faces]).
  /// When non-null, the renderer uses these instead of the uniform material
  /// color, allowing different faces to have distinct tints.
  final List<Color>? faceColors;

  Geometry translated(Vector3 offset) {
    if (vertices.isEmpty) {
      return this;
    }
    final delta = Vector3(offset.x, offset.y, offset.z);
    final transformed = vertices
        .map((vertex) => Vector3.copy(vertex)..add(delta))
        .toList(growable: false);
    return _copyWithVertices(transformed);
  }

  Geometry scaledVector(Vector3 scale) {
    if (vertices.isEmpty) {
      return this;
    }
    final transformed = vertices
        .map(
          (vertex) => Vector3(
            vertex.x * scale.x,
            vertex.y * scale.y,
            vertex.z * scale.z,
          ),
        )
        .toList(growable: false);
    return _copyWithVertices(transformed);
  }

  Geometry scaledUniform(double factor) {
    return scaledVector(Vector3.all(factor));
  }

  Geometry _copyWithVertices(List<Vector3> newVertices) {
    return Geometry(
      id: id,
      name: name,
      vertices: newVertices,
      faces: faces,
      colorSeed: colorSeed,
      faceColors: faceColors,
    );
  }
}

class MaterialModel {
  const MaterialModel({
    required this.color,
    this.doubleSided = false,
    this.wireframe = false,
    this.opacity = 1.0,
    List<Color>? perFaceColors,
    this.exactPerFaceColors = false,
  }) : _perFaceColors = perFaceColors;

  const MaterialModel.rainbow({bool doubleSided = false})
    : color = Colors.white,
      doubleSided = doubleSided,
      wireframe = false,
      opacity = 1.0,
      exactPerFaceColors = false,
      _perFaceColors = _defaultRainbowPalette;

  /// Uncrafted / placeholder mesh: grey fill at 50% opacity.
  const MaterialModel.ghost({bool doubleSided = true})
    : color = kGhostMaterialColor,
      doubleSided = doubleSided,
      wireframe = false,
      opacity = kGhostMaterialOpacity,
      exactPerFaceColors = false,
      _perFaceColors = null;

  final Color color;
  final bool doubleSided;

  /// When true, the mesh renders as wireframe only (edges without solid fill).
  final bool wireframe;

  /// Fill opacity (0.0 = fully transparent, 1.0 = fully opaque).
  /// Non-opaque meshes draw their edges in the material colour.
  final double opacity;
  final List<Color>? _perFaceColors;
  List<Color>? get perFaceColors => _perFaceColors;

  /// When true, [perFaceColors]\[i\] is exactly the color for face [i]
  /// (no seed-based palette rotation). Used for crafted face materials.
  final bool exactPerFaceColors;

  static const Color kGhostMaterialColor = Color(0xFF9E9E9E);
  static const double kGhostMaterialOpacity = 0.5;

  static const List<Color> _defaultRainbowPalette = <Color>[
    Color(0xFFFF0059),
    Color(0xFFFF4600),
    Color(0xFFFF7A00),
    Color(0xFFFFB000),
    Color(0xFFFFE600),
    Color(0xFFE3FF00),
    Color(0xFFB0FF00),
    Color(0xFF76FF03),
    Color(0xFF2DFF57),
    Color(0xFF00FFA8),
    Color(0xFF00FFE1),
    Color(0xFF00D5FF),
    Color(0xFF00A7FF),
    Color(0xFF0072FF),
    Color(0xFF0047FF),
    Color(0xFF3B00FF),
    Color(0xFF7200FF),
    Color(0xFFA200FF),
    Color(0xFFD100FF),
    Color(0xFFFF00F2),
    Color(0xFFFF00C8),
    Color(0xFFFF0092),
    Color(0xFFFF006E),
    Color(0xFFFF3C92),
    Color(0xFFFF5FA9),
    Color(0xFFFF83C0),
  ];

  Color colorForFace(int faceIndex, {int? seed}) {
    final palette = _perFaceColors;
    if (palette == null || palette.isEmpty) {
      return color;
    }
    if (exactPerFaceColors) {
      if (faceIndex >= 0 && faceIndex < palette.length) {
        return palette[faceIndex];
      }
      return color;
    }
    final startIndex = seed == null ? 0 : seed.abs() % palette.length;
    final paletteIndex = (startIndex + faceIndex) % palette.length;
    return palette[paletteIndex];
  }
}

class _GeometryUuid {
  _GeometryUuid._();

  static final math.Random _random = math.Random();

  static _GeometryIdentity generateIdentity() {
    final uuid = generate();
    final seed = seedFrom(uuid);
    return _GeometryIdentity(uuid, seed);
  }

  static String generate() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    return _formatBytes(bytes);
  }

  static int seedFrom(String uuid) {
    var hash = 0;
    for (final codeUnit in uuid.codeUnits) {
      hash = (hash * 31 + codeUnit) & 0x7fffffff;
    }
    return hash;
  }

  static String _formatBytes(List<int> bytes) {
    String twoHex(int value) => value.toRadixString(16).padLeft(2, '0');
    final sections = <List<int>>[
      bytes.sublist(0, 4),
      bytes.sublist(4, 6),
      bytes.sublist(6, 8),
      bytes.sublist(8, 10),
      bytes.sublist(10, 16),
    ];
    final buffer = StringBuffer();
    for (var i = 0; i < sections.length; i++) {
      if (i > 0) buffer.write('-');
      for (final byte in sections[i]) {
        buffer.write(twoHex(byte));
      }
    }
    return buffer.toString();
  }
}

class _GeometryIdentity {
  const _GeometryIdentity(this.uuid, this.seed);

  final String uuid;
  final int seed;
}

Geometry ensureOutwardFacingGeometry(Geometry geometry) {
  if (geometry.vertices.isEmpty || geometry.faces.isEmpty) {
    return geometry;
  }
  final vertices = geometry.vertices.map(Vector3.copy).toList();
  final center = Vector3.zero();
  for (final vertex in vertices) {
    center.add(vertex);
  }
  center.scale(1 / vertices.length);

  final adjustedFaces = <List<int>>[];
  for (final face in geometry.faces) {
    var indices = List<int>.from(face);
    if (indices.length >= 3) {
      final a = vertices[indices[0]];
      final b = vertices[indices[1]];
      final c = vertices[indices[2]];
      final normal = (b - a).cross(c - a);
      final faceCenter = Vector3.zero();
      for (final index in indices) {
        faceCenter.add(vertices[index]);
      }
      faceCenter.scale(1 / indices.length);
      final toFace = faceCenter - center;
      if (normal.dot(toFace) < 0) {
        indices = List<int>.from(indices.reversed);
      }
    }
    adjustedFaces.add(indices);
  }

  return Geometry(
    id: geometry.id,
    name: geometry.name,
    vertices: vertices,
    faces: adjustedFaces,
    colorSeed: geometry.colorSeed,
    faceColors: geometry.faceColors,
  );
}

/// Fix face winding order for a closed-solid mesh using edge-adjacency BFS.
///
/// For a watertight mesh, every edge is shared by exactly two faces. If both
/// faces list the edge in the same direction (A→B, A→B) one of them has
/// flipped winding. This algorithm:
///
/// 1. Builds a directed-edge → face adjacency map.
/// 2. Picks a seed face whose normal clearly points outward (away from the
///    mesh centroid).
/// 3. BFS-propagates winding: when two faces share a manifold edge, their
///    directed-edge usage must be opposite (one A→B, the other B→A). If not,
///    the unvisited face is reversed.
///
/// Returns a new [Geometry] with consistent outward-facing winding, or the
/// original if the mesh is empty / already consistent.
Geometry fixWindingOrder(Geometry geometry) {
  final faces = geometry.faces;
  final verts = geometry.vertices;
  if (faces.isEmpty || verts.isEmpty) return geometry;

  final n = faces.length;

  // Build directed-edge → face index map.
  // Key: (min(a,b), max(a,b)); Value: list of (faceIndex, isForward).
  // isForward = true means the face lists the edge as (lo→hi) in traversal.
  // (faceIndex, isForward) pairs per canonical edge.
  final edgeAdj = <(int, int), List<(int, bool)>>{};

  for (var fi = 0; fi < n; fi++) {
    final face = faces[fi];
    for (var i = 0; i < face.length; i++) {
      final a = face[i];
      final b = face[(i + 1) % face.length];
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      final key = (lo, hi);
      (edgeAdj[key] ??= []).add((fi, a == lo));
    }
  }

  // Pick seed face: the one whose centroid-based normal most clearly points
  // outward from the mesh centroid.
  final centroid = Vector3.zero();
  for (final v in verts) {
    centroid.add(v);
  }
  centroid.scale(1.0 / verts.length);

  int seedFace = 0;
  double bestDot = -double.infinity;
  for (var fi = 0; fi < n; fi++) {
    final face = faces[fi];
    if (face.length < 3) continue;
    final a = verts[face[0]], b = verts[face[1]], c = verts[face[2]];
    final normal = (b - a).cross(c - a);
    final fc = Vector3.zero();
    for (final idx in face) {
      fc.add(verts[idx]);
    }
    fc.scale(1.0 / face.length);
    final outward = fc - centroid;
    final d = normal.dot(outward);
    if (d > bestDot) {
      bestDot = d;
      seedFace = fi;
    }
  }

  // BFS propagation.
  final flipped = List<bool>.filled(n, false);
  final visited = List<bool>.filled(n, false);
  visited[seedFace] = true;
  // If the seed face's normal points inward, flip it.
  if (bestDot < 0) flipped[seedFace] = true;

  final queue = <int>[seedFace];
  while (queue.isNotEmpty) {
    final fi = queue.removeAt(0);
    final face = faces[fi];
    final fiFlipped = flipped[fi];

    for (var i = 0; i < face.length; i++) {
      final a = face[i];
      final b = face[(i + 1) % face.length];
      final lo = a < b ? a : b;
      final hi = a < b ? b : a;
      final isForward = a == lo;
      // After our flip, the effective direction inverts.
      final effectiveForward = fiFlipped ? !isForward : isForward;

      final neighbors = edgeAdj[(lo, hi)];
      if (neighbors == null) continue;
      for (final (ni, niForward) in neighbors) {
        if (visited[ni]) continue;
        visited[ni] = true;
        // For consistent winding, the neighbor must traverse this edge in
        // the opposite effective direction.
        final needsFlip = niForward == effectiveForward;
        flipped[ni] = needsFlip;
        queue.add(ni);
      }
    }
  }

  int flipCount = flipped.where((f) => f).length;
  if (flipCount == 0) return geometry;

  final newFaces = <List<int>>[];
  final newColors = geometry.faceColors != null
      ? <Color>[]
      : null;
  for (var fi = 0; fi < n; fi++) {
    if (flipped[fi]) {
      newFaces.add(List<int>.from(faces[fi].reversed));
    } else {
      newFaces.add(faces[fi]);
    }
    if (newColors != null && geometry.faceColors != null) {
      newColors.add(fi < geometry.faceColors!.length
          ? geometry.faceColors![fi]
          : Colors.white);
    }
  }

  return Geometry(
    id: geometry.id,
    name: geometry.name,
    vertices: verts,
    faces: newFaces,
    colorSeed: geometry.colorSeed,
    faceColors: newColors,
  );
}

Geometry Function(Geometry) buildNormalizationTransform(
  Geometry reference, {
  double targetSpan = 220.0,
}) {
  final bounds = geometryBounds(reference);
  if (bounds == null) {
    return (geometry) => geometry;
  }
  final translation = Vector3(
    -bounds.center.x,
    -bounds.min.y,
    -bounds.center.z,
  );
  final span = bounds.maxSpan;
  final scale = span <= 1e-6 ? 1.0 : targetSpan / span;
  return (geometry) {
    var result = geometry.translated(translation);
    if ((scale - 1.0).abs() > 1e-6) {
      result = result.scaledUniform(scale);
    }
    return result;
  };
}

GeometryBounds? geometryBounds(Geometry geometry) {
  if (geometry.vertices.isEmpty) {
    return null;
  }
  final min = Vector3.copy(geometry.vertices.first);
  final max = Vector3.copy(geometry.vertices.first);
  for (final vertex in geometry.vertices.skip(1)) {
    min.x = math.min(min.x, vertex.x);
    min.y = math.min(min.y, vertex.y);
    min.z = math.min(min.z, vertex.z);
    max.x = math.max(max.x, vertex.x);
    max.y = math.max(max.y, vertex.y);
    max.z = math.max(max.z, vertex.z);
  }
  return GeometryBounds(min, max);
}

class GeometryBounds {
  GeometryBounds(this.min, this.max);

  final Vector3 min;
  final Vector3 max;

  Vector3 get center => Vector3(
    (min.x + max.x) * 0.5,
    (min.y + max.y) * 0.5,
    (min.z + max.z) * 0.5,
  );

  Vector3 get size => Vector3(max.x - min.x, max.y - min.y, max.z - min.z);

  double get maxSpan =>
      math.max(size.x.abs(), math.max(size.y.abs(), size.z.abs()));
}
