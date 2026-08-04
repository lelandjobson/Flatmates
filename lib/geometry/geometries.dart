import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'folded_geometry.dart';
import 'geometry.dart';

class GeometryBuilders {
  GeometryBuilders._();

  static Geometry pentagonalPrism({double radius = 60, double height = 140}) {
    final data = pentagonalPrismPolyhedron(radius: radius, height: height);
    return Geometry(
      id: 'pentPrism',
      name: 'Pentagonal Prism',
      vertices: data.vertices,
      faces: data.faces,
    );
  }

  static List<Vector3> cubeVertices(double size) => _buildCubeVertices(size);

  static const List<List<int>> cubeFaces = <List<int>>[
    [0, 3, 2, 1],
    [4, 5, 6, 7],
    [0, 1, 5, 4],
    [3, 7, 6, 2],
    [1, 2, 6, 5],
    [0, 4, 7, 3],
  ];

  static _PolyhedronData cubePolyhedron(double size) {
    return _PolyhedronData(
      vertices: _buildCubeVertices(size),
      faces: cubeFaces,
    );
  }

  static _PolyhedronData pentagonalPrismPolyhedron({
    double radius = 60,
    double height = 140,
  }) {
    return _buildPentagonalPrismData(radius: radius, height: height);
  }

  static _PolyhedronData soccerBallPolyhedron(double radius) {
    final icosahedron = _buildIcosahedronData();
    final baseVertices = icosahedron.vertices;
    final baseFaces = icosahedron.faces;
    const truncation = 1 / 3;

    final vertexCache = <_EdgeKey, int>{};
    final vertices = <Vector3>[];

    int vertexFor(int from, int to) {
      final key = _EdgeKey(from, to);
      return vertexCache.putIfAbsent(key, () {
        final start = Vector3.copy(baseVertices[from])..scale(1 - truncation);
        final end = Vector3.copy(baseVertices[to])..scale(truncation);
        final position = start..add(end);
        position.normalize();
        position.scale(radius);
        vertices.add(position);
        return vertices.length - 1;
      });
    }

    final faces = <List<int>>[];

    for (final face in baseFaces) {
      final a = face[0];
      final b = face[1];
      final c = face[2];
      faces.add([
        vertexFor(a, b),
        vertexFor(b, a),
        vertexFor(b, c),
        vertexFor(c, b),
        vertexFor(c, a),
        vertexFor(a, c),
      ]);
    }

    final neighborSets = List<Set<int>>.generate(
      baseVertices.length,
      (_) => <int>{},
    );
    for (final face in baseFaces) {
      final a = face[0];
      final b = face[1];
      final c = face[2];
      neighborSets[a]
        ..add(b)
        ..add(c);
      neighborSets[b]
        ..add(a)
        ..add(c);
      neighborSets[c]
        ..add(a)
        ..add(b);
    }

    for (var i = 0; i < baseVertices.length; i++) {
      final neighbors = _orderedNeighbors(i, neighborSets[i], baseVertices);
      faces.add([for (final neighbor in neighbors) vertexFor(i, neighbor)]);
    }

    return _PolyhedronData(vertices: vertices, faces: faces);
  }

  static List<Vector3> _buildCubeVertices(double size) {
    final half = size / 2;
    return [
      Vector3(-half, -half, -half),
      Vector3(half, -half, -half),
      Vector3(half, half, -half),
      Vector3(-half, half, -half),
      Vector3(-half, -half, half),
      Vector3(half, -half, half),
      Vector3(half, half, half),
      Vector3(-half, half, half),
    ];
  }

  static List<int> _orderedNeighbors(
    int vertexIndex,
    Set<int> neighborSet,
    List<Vector3> vertices,
  ) {
    final origin = vertices[vertexIndex];
    final normal = Vector3.copy(origin)..normalize();
    var tangent = normal.cross(Vector3(0, 1, 0));
    if (tangent.length2 == 0) {
      tangent = normal.cross(Vector3(1, 0, 0));
    }
    tangent.normalize();
    final bitangent = normal.cross(tangent)..normalize();

    final neighborAngles = <_NeighborAngle>[];
    for (final neighbor in neighborSet) {
      final direction = Vector3.copy(vertices[neighbor])..sub(origin);
      direction.normalize();
      final x = direction.dot(tangent);
      final y = direction.dot(bitangent);
      neighborAngles.add(_NeighborAngle(neighbor, math.atan2(y, x)));
    }

    neighborAngles.sort((a, b) => a.angle.compareTo(b.angle));
    return neighborAngles.map((entry) => entry.index).toList();
  }

  static _IcosahedronData _buildIcosahedronData() {
    final phi = (1 + math.sqrt(5)) / 2;
    final vertices = <Vector3>[
      Vector3(-1, phi, 0),
      Vector3(1, phi, 0),
      Vector3(-1, -phi, 0),
      Vector3(1, -phi, 0),
      Vector3(0, -1, phi),
      Vector3(0, 1, phi),
      Vector3(0, -1, -phi),
      Vector3(0, 1, -phi),
      Vector3(phi, 0, -1),
      Vector3(phi, 0, 1),
      Vector3(-phi, 0, -1),
      Vector3(-phi, 0, 1),
    ];

    for (final vertex in vertices) {
      vertex.normalize();
    }

    const faces = <List<int>>[
      [0, 11, 5],
      [0, 5, 1],
      [0, 1, 7],
      [0, 7, 10],
      [0, 10, 11],
      [1, 5, 9],
      [5, 11, 4],
      [11, 10, 2],
      [10, 7, 6],
      [7, 1, 8],
      [3, 9, 4],
      [3, 4, 2],
      [3, 2, 6],
      [3, 6, 8],
      [3, 8, 9],
      [4, 9, 5],
      [2, 4, 11],
      [6, 2, 10],
      [8, 6, 7],
      [9, 8, 1],
    ];

    return _IcosahedronData(vertices, faces);
  }
}

_PolyhedronData _buildPentagonalPrismData({
  required double radius,
  required double height,
}) {
  final vertices = <Vector3>[];
  final faces = <List<int>>[];
  final topIndices = <int>[];
  final bottomIndices = <int>[];
  final halfHeight = height / 2;

  for (var i = 0; i < 5; i++) {
    final angle = 2 * math.pi * i / 5;
    final x = radius * math.cos(angle);
    final z = radius * math.sin(angle);

    final topIndex = vertices.length;
    vertices.add(Vector3(x, halfHeight, z));
    topIndices.add(topIndex);

    final bottomIndex = vertices.length;
    vertices.add(Vector3(x, -halfHeight, z));
    bottomIndices.add(bottomIndex);
  }

  faces.add(List<int>.from(topIndices.reversed));
  faces.add(List<int>.from(bottomIndices));

  for (var i = 0; i < 5; i++) {
    final next = (i + 1) % 5;
    faces.add([
      topIndices[i],
      topIndices[next],
      bottomIndices[next],
      bottomIndices[i],
    ]);
  }

  return _PolyhedronData(vertices: vertices, faces: faces);
}

class GeodesicFoldFactories {
  GeodesicFoldFactories._();

  static FoldedGeometry cube(double size) {
    final polyhedron = GeometryBuilders.cubePolyhedron(size);
    return FoldedGeometry.fromPolyhedron(
      id: 'foldingCube',
      name: 'Folding Cube',
      vertices: polyhedron.vertices,
      faces: polyhedron.faces,
    );
  }

  static FoldedGeometry soccerBall(double radius) {
    final polyhedron = GeometryBuilders.soccerBallPolyhedron(radius);
    return FoldedGeometry.fromPolyhedron(
      id: 'foldingSoccer',
      name: 'Folding Soccer Ball',
      vertices: polyhedron.vertices,
      faces: polyhedron.faces,
    );
  }

  static FoldedGeometry pentagonalPrism({
    double radius = 60,
    double height = 140,
  }) {
    final polyhedron = GeometryBuilders.pentagonalPrismPolyhedron(
      radius: radius,
      height: height,
    );
    return FoldedGeometry.fromPolyhedron(
      id: 'foldingPentagonalPrism',
      name: 'Folding Pentagonal Prism',
      vertices: polyhedron.vertices,
      faces: polyhedron.faces,
    );
  }
}

class _IcosahedronData {
  const _IcosahedronData(this.vertices, this.faces);

  final List<Vector3> vertices;
  final List<List<int>> faces;
}

class _PolyhedronData {
  const _PolyhedronData({required this.vertices, required this.faces});

  final List<Vector3> vertices;
  final List<List<int>> faces;
}

class _EdgeKey {
  const _EdgeKey(this.from, this.to);

  final int from;
  final int to;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _EdgeKey && other.from == from && other.to == to;
  }

  @override
  int get hashCode => Object.hash(from, to);
}

class _NeighborAngle {
  const _NeighborAngle(this.index, this.angle);

  final int index;
  final double angle;
}
