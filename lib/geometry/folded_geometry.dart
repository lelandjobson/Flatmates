import 'dart:collection';
import 'dart:math' as math;

import 'package:vector_math/vector_math_64.dart';

import 'geometry.dart';

class FoldedGeometry {
  FoldedGeometry({
    required this.id,
    required this.name,
    required this.root,
    this.fold = 1.0,
  });

  final String id;
  final String name;
  final FoldFace root;
  double fold;

  /// Builds a folded geometry from a Wavefront OBJ string.
  ///
  /// Only the vertex (`v`) and face (`f`) directives are required; any other
  /// directives are ignored. Face indices may include texture/normal data
  /// (e.g. `f 1/2/3 4/5/6`) and can be specified using positive or negative
  /// OBJ indexing. The `rootFaceIndex` defaults to the first parsed face.
  factory FoldedGeometry.fromString({
    required String id,
    required String name,
    required String objSource,
    int rootFaceIndex = 0,
  }) {
    final parsed = _parseObjString(objSource);
    if (parsed.faces.isEmpty) {
      throw const FormatException('OBJ source did not contain any faces.');
    }
    if (parsed.vertices.isEmpty) {
      throw const FormatException('OBJ source did not contain any vertices.');
    }
    final mergedFaces = _mergeCoplanarFaces(
      vertices: parsed.vertices,
      faces: parsed.faces,
    );
    if (mergedFaces.isEmpty) {
      throw const FormatException('OBJ merging removed all faces.');
    }
    if (rootFaceIndex < 0 || rootFaceIndex >= mergedFaces.length) {
      throw RangeError.range(
        rootFaceIndex,
        0,
        mergedFaces.length - 1,
        'rootFaceIndex',
        'Must point to a parsed OBJ face.',
      );
    }

    return _buildFoldedGeometryFromPolyhedron(
      id: id,
      name: name,
      vertices: parsed.vertices,
      faces: mergedFaces,
      rootFaceIndex: rootFaceIndex,
    );
  }

  factory FoldedGeometry.fromPolyhedron({
    required String id,
    required String name,
    required List<Vector3> vertices,
    required List<List<int>> faces,
    int rootFaceIndex = 0,
  }) {
    return _buildFoldedGeometryFromPolyhedron(
      id: id,
      name: name,
      vertices: vertices,
      faces: faces,
      rootFaceIndex: rootFaceIndex,
    );
  }

  /// Returns the original face indices in the order they appear in the
  /// geometry produced by [toGeometry]. Useful for mapping unfolded face
  /// indices back to the source geometry when built from a polyhedron.
  List<int> faceTraversalOrder() {
    final order = <int>[];
    _collectFaceOrder(root, order);
    return order;
  }

  static void _collectFaceOrder(FoldFace face, List<int> out) {
    out.add(face.originalFaceIndex ?? out.length);
    for (final attachment in face.children) {
      _collectFaceOrder(attachment.child, out);
    }
  }

  Geometry toGeometry({double? foldValue}) {
    final resolvedFold = (foldValue ?? fold).clamp(0.0, 1.0).toDouble();
    final vertices = <Vector3>[];
    final faces = <List<int>>[];

    _processFace(
      face: root,
      transform: Matrix4.identity(),
      foldValue: resolvedFold,
      verticesOut: vertices,
      facesOut: faces,
    );

    return Geometry(id: id, name: name, vertices: vertices, faces: faces);
  }

  void _processFace({
    required FoldFace face,
    required Matrix4 transform,
    required double foldValue,
    required List<Vector3> verticesOut,
    required List<List<int>> facesOut,
  }) {
    final transformedVertices = face.vertices.map((vertex) {
      final world = Vector3.copy(vertex);
      transform.transform3(world);
      return world;
    }).toList();

    final indices = <int>[];
    for (final vertex in transformedVertices) {
      verticesOut.add(Vector3.copy(vertex));
      indices.add(verticesOut.length - 1);
    }
    facesOut.add(indices);

    if (face.children.isEmpty) {
      return;
    }

    final placement = _FacePlacement(
      transform: transform,
      worldVertices: transformedVertices,
    );

    for (final attachment in face.children) {
      final childTransform = _childTransform(
        placement: placement,
        attachment: attachment,
        foldValue: foldValue,
      );
      _processFace(
        face: attachment.child,
        transform: childTransform,
        foldValue: foldValue,
        verticesOut: verticesOut,
        facesOut: facesOut,
      );
    }
  }

  Matrix4 _childTransform({
    required _FacePlacement placement,
    required FoldAttachment attachment,
    required double foldValue,
  }) {
    final baseTransform = Matrix4.copy(placement.transform);
    final start = placement.worldVertices[attachment.parentEdgeStart];
    final end = placement.worldVertices[attachment.parentEdgeEnd];
    final axis = end - start;
    if (axis.length2 <= 1e-8) {
      return baseTransform;
    }
    axis.normalize();

    final parentNormal = _faceNormal(placement.worldVertices);
    if (parentNormal.length2 <= 1e-8) {
      return baseTransform;
    }
    parentNormal.normalize();

    final targetAngle = attachment.foldAngleRadians;
    if (targetAngle.abs() <= 1e-6) {
      return baseTransform;
    }

    final angle = targetAngle * foldValue;

    final rotation = Matrix4.identity()
      ..translate(Vector3(start.x, start.y, start.z))
      ..rotate(axis, angle)
      ..translate(Vector3(-start.x, -start.y, -start.z));

    return rotation..multiply(baseTransform);
  }
}

class _ObjParseResult {
  _ObjParseResult({required this.vertices, required this.faces});

  final List<Vector3> vertices;
  final List<List<int>> faces;
}

_ObjParseResult _parseObjString(String source) {
  final vertices = <Vector3>[];
  final vertexIndexRemap = <int>[];
  final dedupeLookup = <_VectorKey, int>{};
  final faces = <List<int>>[];
  final lines = source.split(RegExp(r'\r?\n'));

  for (final rawLine in lines) {
    var line = rawLine;
    final commentIndex = line.indexOf('#');
    if (commentIndex != -1) {
      line = line.substring(0, commentIndex);
    }
    line = line.trim();
    if (line.isEmpty) {
      continue;
    }

    final tokens = line.split(RegExp(r'\s+'));
    if (tokens.isEmpty) {
      continue;
    }
    final prefix = tokens.first;

    if (prefix == 'v') {
      if (tokens.length < 4) {
        throw FormatException('Malformed vertex line: "$rawLine"');
      }
      final x = _parseDouble(tokens[1], rawLine);
      final y = _parseDouble(tokens[2], rawLine);
      final z = _parseDouble(tokens[3], rawLine);
      final key = _VectorKey(x, y, z);
      final existing = dedupeLookup[key];
      if (existing != null) {
        vertexIndexRemap.add(existing);
      } else {
        final index = vertices.length;
        vertices.add(Vector3(x, y, z));
        dedupeLookup[key] = index;
        vertexIndexRemap.add(index);
      }
      continue;
    }

    if (prefix == 'f') {
      if (tokens.length < 4) {
        throw FormatException(
          'Face must have at least three vertices: "$rawLine"',
        );
      }
      final indices = <int>[];
      for (var i = 1; i < tokens.length; i++) {
        final element = tokens[i];
        if (element.isEmpty) {
          continue;
        }
        final vertexToken = element.split('/').first;
        if (vertexToken.isEmpty) {
          throw FormatException('Face vertex is missing an index: "$rawLine"');
        }
        indices.add(
          _resolveObjIndex(
            token: vertexToken,
            remap: vertexIndexRemap,
            line: rawLine,
          ),
        );
      }
      if (indices.length < 3) {
        throw FormatException(
          'Face must reference at least 3 vertices: "$rawLine"',
        );
      }
      faces.add(indices);
      continue;
    }
  }

  return _ObjParseResult(vertices: vertices, faces: faces);
}

List<List<int>> _mergeCoplanarFaces({
  required List<Vector3> vertices,
  required List<List<int>> faces,
  double normalTolerance = 1e-4,
  double planeTolerance = 1e-3,
}) {
  if (faces.length <= 1) {
    return faces
        .map((face) => List<int>.from(face, growable: false))
        .toList(growable: false);
  }

  final faceData = List<_FaceMergeData>.generate(
    faces.length,
    (index) =>
        _FaceMergeData.fromFace(indices: faces[index], vertices: vertices),
  );

  final adjacency = _buildFaceAdjacency(faces);
  final neighbors = List<List<int>>.generate(
    faces.length,
    (faceIndex) => adjacency[faceIndex]
        .map((neighbor) => neighbor.faceIndex)
        .toList(growable: false),
    growable: false,
  );

  final visited = List<bool>.filled(faces.length, false);
  final mergedFaces = <List<int>>[];

  for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
    if (visited[faceIndex]) {
      continue;
    }
    final group = <int>[];
    final queue = Queue<int>()..add(faceIndex);
    while (queue.isNotEmpty) {
      final current = queue.removeFirst();
      if (visited[current]) {
        continue;
      }
      visited[current] = true;
      group.add(current);
      for (final neighbor in neighbors[current]) {
        if (visited[neighbor]) {
          continue;
        }
        if (_facesAreCoplanar(
          faceData[current],
          faceData[neighbor],
          normalTolerance: normalTolerance,
          planeTolerance: planeTolerance,
        )) {
          queue.add(neighbor);
        }
      }
    }

    if (group.length == 1 || !_groupEligibleForMerge(group, faceData)) {
      mergedFaces.add(faceData[group.first].indices);
      continue;
    }

    final merged = _mergeFaceGroupToNgons(
      groupIndices: group,
      faceData: faceData,
      vertices: vertices,
    );

    if (merged == null || merged.isEmpty) {
      for (final index in group) {
        mergedFaces.add(faceData[index].indices);
      }
    } else {
      mergedFaces.addAll(merged);
    }
  }

  return mergedFaces;
}

double _parseDouble(String token, String line) {
  final value = double.tryParse(token);
  if (value == null) {
    throw FormatException('Invalid float "$token" in line: "$line"');
  }
  return value;
}

int _resolveObjIndex({
  required String token,
  required List<int> remap,
  required String line,
}) {
  final parsed = int.tryParse(token);
  if (parsed == null || parsed == 0) {
    throw FormatException('Invalid vertex index "$token" in line: "$line"');
  }

  final vertexCount = remap.length;
  final rawIndex = parsed > 0 ? parsed - 1 : vertexCount + parsed;
  if (rawIndex < 0 || rawIndex >= vertexCount) {
    throw FormatException(
      'Vertex index "$token" is out of bounds for line: "$line"',
    );
  }
  return remap[rawIndex];
}

class _VectorKey {
  _VectorKey(double x, double y, double z)
    : _x = _quantize(x),
      _y = _quantize(y),
      _z = _quantize(z);

  final int _x;
  final int _y;
  final int _z;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _VectorKey &&
        other._x == _x &&
        other._y == _y &&
        other._z == _z;
  }

  @override
  int get hashCode => Object.hash(_x, _y, _z);
}

int _quantize(double value) => (value * 1e6).round();

class _FaceMergeData {
  _FaceMergeData({
    required this.indices,
    required this.normal,
    required this.planeConstant,
    required this.degenerate,
  });

  factory _FaceMergeData.fromFace({
    required List<int> indices,
    required List<Vector3> vertices,
  }) {
    final normal = _indexedFaceNormal(indices, vertices);
    final degenerate = normal.length2 <= 1e-10;
    final planeConstant = degenerate
        ? 0.0
        : normal.dot(vertices[indices.first]);
    return _FaceMergeData(
      indices: List<int>.from(indices, growable: false),
      normal: normal,
      planeConstant: planeConstant,
      degenerate: degenerate,
    );
  }

  final List<int> indices;
  final Vector3 normal;
  final double planeConstant;
  final bool degenerate;
}

bool _facesAreCoplanar(
  _FaceMergeData a,
  _FaceMergeData b, {
  required double normalTolerance,
  required double planeTolerance,
}) {
  if (a.degenerate || b.degenerate) {
    return false;
  }
  final alignment = a.normal.dot(b.normal).clamp(-1.0, 1.0);
  if (alignment < 1.0 - normalTolerance) {
    return false;
  }
  return (a.planeConstant - b.planeConstant).abs() <= planeTolerance;
}

bool _groupEligibleForMerge(List<int> group, List<_FaceMergeData> faceData) {
  for (final index in group) {
    if (faceData[index].degenerate) {
      return false;
    }
  }
  return true;
}

List<List<int>>? _mergeFaceGroupToNgons({
  required List<int> groupIndices,
  required List<_FaceMergeData> faceData,
  required List<Vector3> vertices,
}) {
  final edgeUsage = <_UndirectedEdge, int>{};
  for (final faceIndex in groupIndices) {
    final face = faceData[faceIndex].indices;
    for (var i = 0; i < face.length; i++) {
      final start = face[i];
      final end = face[(i + 1) % face.length];
      final key = _UndirectedEdge(start, end);
      edgeUsage[key] = (edgeUsage[key] ?? 0) + 1;
    }
  }

  final adjacency = <int, List<int>>{};
  var boundaryEdgeCount = 0;
  for (final faceIndex in groupIndices) {
    final face = faceData[faceIndex].indices;
    for (var i = 0; i < face.length; i++) {
      final start = face[i];
      final end = face[(i + 1) % face.length];
      final key = _UndirectedEdge(start, end);
      if (edgeUsage[key] == 1) {
        adjacency.putIfAbsent(start, () => <int>[]).add(end);
        boundaryEdgeCount++;
      }
    }
  }

  if (boundaryEdgeCount == 0) {
    return null;
  }

  final loops = <List<int>>[];
  while (adjacency.isNotEmpty) {
    final loop = _extractBoundaryLoop(adjacency, boundaryEdgeCount);
    if (loop == null || loop.length < 3) {
      return null;
    }
    loops.add(loop);
  }

  if (loops.isEmpty) {
    return null;
  }

  final referenceNormal = faceData[groupIndices.first].normal;
  final adjustedLoops = <List<int>>[];
  for (final loop in loops) {
    final normal = _indexedFaceNormal(loop, vertices);
    if (normal.length2 == 0) {
      continue;
    }
    if (normal.dot(referenceNormal) < 0) {
      adjustedLoops.add(loop.reversed.toList());
    } else {
      adjustedLoops.add(loop);
    }
  }

  return adjustedLoops.isEmpty ? null : adjustedLoops;
}

List<int>? _extractBoundaryLoop(Map<int, List<int>> adjacency, int maxSteps) {
  final start = adjacency.keys.first;
  var current = _takeNextEdge(adjacency, start);
  if (current == null) {
    return null;
  }
  final loop = <int>[start];
  var steps = 0;
  while (current != start) {
    loop.add(current!);
    current = _takeNextEdge(adjacency, current);
    if (current == null) {
      return null;
    }
    steps++;
    if (steps > maxSteps + 2) {
      return null;
    }
  }
  return loop;
}

int? _takeNextEdge(Map<int, List<int>> adjacency, int start) {
  final list = adjacency[start];
  if (list == null || list.isEmpty) {
    adjacency.remove(start);
    return null;
  }
  final next = list.removeLast();
  if (list.isEmpty) {
    adjacency.remove(start);
  }
  return next;
}

class FoldFace {
  FoldFace({
    required this.id,
    required List<Vector3> vertices,
    this.originalFaceIndex,
  }) : vertices = vertices.map(Vector3.copy).toList();

  final String id;
  final List<Vector3> vertices;
  final List<FoldAttachment> children = [];

  /// When built from a polyhedron, this stores the index of the face in the
  /// original [Geometry.faces] list so callers can map traversal-order faces
  /// back to their source geometry.
  final int? originalFaceIndex;

  void addChild(FoldAttachment attachment) {
    children.add(attachment);
  }
}

class FoldAttachment {
  FoldAttachment({
    required this.child,
    required this.parentEdgeStart,
    required this.parentEdgeEnd,
    required this.foldAngleRadians,
  });

  final FoldFace child;
  final int parentEdgeStart;
  final int parentEdgeEnd;
  final double foldAngleRadians;
}

class _FacePlacement {
  _FacePlacement({required this.transform, required this.worldVertices});

  final Matrix4 transform;
  final List<Vector3> worldVertices;
}

FoldedGeometry _buildFoldedGeometryFromPolyhedron({
  required String id,
  required String name,
  required List<Vector3> vertices,
  required List<List<int>> faces,
  required int rootFaceIndex,
}) {
  final adjacency = _buildFaceAdjacency(faces);
  final faceNormals = List<Vector3>.generate(
    faces.length,
    (faceIndex) => _indexedFaceNormal(faces[faceIndex], vertices),
  );

  final flattenTransforms = List<Matrix4?>.filled(faces.length, null);
  final foldFaces = List<FoldFace?>.filled(faces.length, null);

  final rootTransform = _createRootFlattenTransform(
    vertices,
    faces[rootFaceIndex],
  );
  flattenTransforms[rootFaceIndex] = rootTransform;
  foldFaces[rootFaceIndex] = _foldFaceFromTransform(
    id: 'poly-face-$rootFaceIndex',
    faceIndices: faces[rootFaceIndex],
    vertices: vertices,
    transform: rootTransform,
    originalFaceIndex: rootFaceIndex,
  );

  final visited = <int>{rootFaceIndex};
  final queue = Queue<int>()..add(rootFaceIndex);

  while (queue.isNotEmpty) {
    final parentIndex = queue.removeFirst();
    final parentTransform = flattenTransforms[parentIndex]!;
    final parentFoldFace = foldFaces[parentIndex]!;
    final parentFlatVertices = _applyFaceTransform(
      indices: faces[parentIndex],
      vertices: vertices,
      transform: parentTransform,
    );
    final parentNormal = _faceNormal(parentFlatVertices);

    for (final neighbor in adjacency[parentIndex]) {
      final childIndex = neighbor.faceIndex;
      if (visited.contains(childIndex)) continue;

      final childTransform = _flattenChildTransform(
        vertices: vertices,
        parentFace: faces[parentIndex],
        childFace: faces[childIndex],
        parentEdgeStart: neighbor.parentEdgeStart,
        parentEdgeEnd: neighbor.parentEdgeEnd,
        parentTransform: parentTransform,
        parentNormal: parentNormal,
      );

      flattenTransforms[childIndex] = childTransform;
      final childFoldFace = _foldFaceFromTransform(
        id: 'poly-face-$childIndex',
        faceIndices: faces[childIndex],
        vertices: vertices,
        transform: childTransform,
        originalFaceIndex: childIndex,
      );
      foldFaces[childIndex] = childFoldFace;

      parentFoldFace.addChild(
        FoldAttachment(
          child: childFoldFace,
          parentEdgeStart: neighbor.parentEdgeStart,
          parentEdgeEnd: neighbor.parentEdgeEnd,
          foldAngleRadians: _dihedralAngle(
            vertices: vertices,
            parentFace: faces[parentIndex],
            childFace: faces[childIndex],
            parentNormal: faceNormals[parentIndex],
            childNormal: faceNormals[childIndex],
            parentEdgeStart: neighbor.parentEdgeStart,
            parentEdgeEnd: neighbor.parentEdgeEnd,
          ),
        ),
      );

      visited.add(childIndex);
      queue.add(childIndex);
    }
  }

  return FoldedGeometry(id: id, name: name, root: foldFaces[rootFaceIndex]!);
}

List<List<_FaceNeighbor>> _buildFaceAdjacency(List<List<int>> faces) {
  final edgeMap = <_UndirectedEdge, _EdgeOccurrences>{};
  for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
    final face = faces[faceIndex];
    for (var i = 0; i < face.length; i++) {
      final a = face[i];
      final b = face[(i + 1) % face.length];
      final key = _UndirectedEdge(a, b);
      edgeMap
          .putIfAbsent(key, () => _EdgeOccurrences())
          .entries
          .add(
            _EdgeReference(
              faceIndex: faceIndex,
              localStart: i,
              localEnd: (i + 1) % face.length,
            ),
          );
    }
  }

  return List<List<_FaceNeighbor>>.generate(
    faces.length,
    (faceIndex) => _buildNeighborsForFace(faceIndex, faces, edgeMap),
  );
}

List<_FaceNeighbor> _buildNeighborsForFace(
  int faceIndex,
  List<List<int>> faces,
  Map<_UndirectedEdge, _EdgeOccurrences> edgeMap,
) {
  final neighbors = <_FaceNeighbor>[];
  final face = faces[faceIndex];
  for (var i = 0; i < face.length; i++) {
    final a = face[i];
    final b = face[(i + 1) % face.length];
    final key = _UndirectedEdge(a, b);
    final occurrence = edgeMap[key];
    if (occurrence == null || occurrence.entries.length != 2) continue;
    final other = occurrence.entries.firstWhere(
      (entry) => entry.faceIndex != faceIndex,
      orElse: () => _EdgeReference(faceIndex: -1, localStart: 0, localEnd: 0),
    );
    if (other.faceIndex == -1) continue;
    neighbors.add(
      _FaceNeighbor(
        faceIndex: other.faceIndex,
        parentEdgeStart: i,
        parentEdgeEnd: (i + 1) % face.length,
      ),
    );
  }
  return neighbors;
}

Matrix4 _createRootFlattenTransform(List<Vector3> vertices, List<int> face) {
  final points = face
      .map((index) => Vector3.copy(vertices[index]))
      .toList(growable: false);
  final centroid = _faceCentroid(points);
  final translation = Matrix4.identity()
    ..translate(Vector3(-centroid.x, -centroid.y, -centroid.z));
  final normal = _faceNormal(points);
  final targetNormal = Vector3(0, 1, 0);
  final rotation = _rotationBetween(normal, targetNormal);
  final baseTransform = Matrix4.identity()
    ..multiply(rotation)
    ..multiply(translation);

  final transformedPoints = points.map((vertex) {
    final copy = Vector3.copy(vertex);
    baseTransform.transform3(copy);
    return copy;
  }).toList();
  final avgY =
      transformedPoints.fold<double>(0, (sum, value) => sum + value.y) /
      transformedPoints.length;

  return Matrix4.identity()
    ..translate(Vector3(0, -avgY, 0))
    ..multiply(baseTransform);
}

FoldFace _foldFaceFromTransform({
  required String id,
  required List<int> faceIndices,
  required List<Vector3> vertices,
  required Matrix4 transform,
  int? originalFaceIndex,
}) {
  final transformed = faceIndices.map((index) {
    final copy = Vector3.copy(vertices[index]);
    transform.transform3(copy);
    return copy;
  }).toList();
  return FoldFace(
    id: id,
    vertices: transformed,
    originalFaceIndex: originalFaceIndex,
  );
}

List<Vector3> _applyFaceTransform({
  required List<int> indices,
  required List<Vector3> vertices,
  required Matrix4 transform,
}) {
  return indices.map((index) {
    final copy = Vector3.copy(vertices[index]);
    transform.transform3(copy);
    return copy;
  }).toList();
}

Matrix4 _flattenChildTransform({
  required List<Vector3> vertices,
  required List<int> parentFace,
  required List<int> childFace,
  required int parentEdgeStart,
  required int parentEdgeEnd,
  required Matrix4 parentTransform,
  required Vector3 parentNormal,
}) {
  final startVertex = Vector3.copy(vertices[parentFace[parentEdgeStart]]);
  final endVertex = Vector3.copy(vertices[parentFace[parentEdgeEnd]]);
  parentTransform.transform3(startVertex);
  parentTransform.transform3(endVertex);
  final axis = endVertex - startVertex;
  if (axis.length2 <= 1e-8) {
    return Matrix4.copy(parentTransform);
  }
  axis.normalize();

  final transformedChild = childFace.map((index) {
    final copy = Vector3.copy(vertices[index]);
    parentTransform.transform3(copy);
    return copy;
  }).toList();
  final childNormal = _faceNormal(transformedChild);
  if (childNormal.length2 <= 1e-8) {
    return Matrix4.copy(parentTransform);
  }

  final angle = _signedAngleAroundAxis(
    from: childNormal,
    to: Vector3(0, 1, 0),
    axis: axis,
  );

  final rotation = Matrix4.identity()
    ..translate(Vector3(startVertex.x, startVertex.y, startVertex.z))
    ..rotate(axis, angle)
    ..translate(Vector3(-startVertex.x, -startVertex.y, -startVertex.z));

  return rotation..multiply(parentTransform);
}

Vector3 _faceCentroid(List<Vector3> vertices) {
  final centroid = Vector3.zero();
  for (final vertex in vertices) {
    centroid.add(vertex);
  }
  centroid.scale(1 / vertices.length);
  return centroid;
}

Matrix4 _rotationBetween(Vector3 from, Vector3 to) {
  final fromNorm = from.length2 == 0
      ? Vector3(0, 1, 0)
      : Vector3.copy(from).normalized();
  final toNorm = to.length2 == 0
      ? Vector3(0, 1, 0)
      : Vector3.copy(to).normalized();
  final dot = fromNorm.dot(toNorm).clamp(-1.0, 1.0);
  if (dot > 0.9999) {
    return Matrix4.identity();
  }
  if (dot < -0.9999) {
    final axis = _orthogonalVector(fromNorm);
    axis.normalize();
    return Matrix4.identity()..rotate(axis, math.pi);
  }
  final axis = fromNorm.cross(toNorm)..normalize();
  final angle = math.acos(dot);
  return Matrix4.identity()..rotate(axis, angle);
}

Vector3 _orthogonalVector(Vector3 vector) {
  if (vector.x.abs() < 0.1 && vector.z.abs() < 0.1) {
    return Vector3(1, 0, 0).cross(vector);
  }
  return Vector3(0, 1, 0).cross(vector);
}

double _signedAngleAroundAxis({
  required Vector3 from,
  required Vector3 to,
  required Vector3 axis,
}) {
  final fromNorm = from.length2 == 0
      ? Vector3(0, 1, 0)
      : Vector3.copy(from).normalized();
  final toNorm = to.length2 == 0
      ? Vector3(0, 1, 0)
      : Vector3.copy(to).normalized();
  final axisNorm = axis.length2 == 0
      ? Vector3(0, 1, 0)
      : Vector3.copy(axis).normalized();
  final dot = fromNorm.dot(toNorm).clamp(-1.0, 1.0);
  final angle = math.acos(dot);
  final cross = fromNorm.cross(toNorm);
  final sign = cross.dot(axisNorm) < 0 ? -1.0 : 1.0;
  return angle * sign;
}

Vector3 _indexedFaceNormal(List<int> indices, List<Vector3> vertices) {
  if (indices.length < 3) {
    return Vector3.zero();
  }
  final a = vertices[indices[0]];
  final b = vertices[indices[1]];
  final c = vertices[indices[2]];
  final edge1 = Vector3.copy(b)..sub(a);
  final edge2 = Vector3.copy(c)..sub(a);
  final normal = edge1.cross(edge2);
  if (normal.length2 == 0) {
    return Vector3.zero();
  }
  return normal.normalized();
}

double _dihedralAngle({
  required List<Vector3> vertices,
  required List<int> parentFace,
  required List<int> childFace,
  required Vector3 parentNormal,
  required Vector3 childNormal,
  required int parentEdgeStart,
  required int parentEdgeEnd,
}) {
  final axis = _edgeDirection(
    vertices: vertices,
    face: parentFace,
    startIndex: parentEdgeStart,
    endIndex: parentEdgeEnd,
  );
  var angle = _signedAngleAroundAxis(
    from: parentNormal,
    to: childNormal,
    axis: axis,
  );
  angle = _ensureAngleDirection(
    parentNormal: parentNormal,
    childNormal: childNormal,
    axis: axis,
    angle: angle,
  );
  return angle;
}

Vector3 _edgeDirection({
  required List<Vector3> vertices,
  required List<int> face,
  required int startIndex,
  required int endIndex,
}) {
  final start = vertices[face[startIndex]];
  final end = vertices[face[endIndex]];
  final direction = Vector3.copy(end)..sub(start);
  if (direction.length2 == 0) {
    return Vector3(1, 0, 0);
  }
  return direction.normalized();
}

double _ensureAngleDirection({
  required Vector3 parentNormal,
  required Vector3 childNormal,
  required Vector3 axis,
  required double angle,
}) {
  if (angle.abs() <= 1e-6) {
    return 0;
  }
  final rotated = _rotateVectorAroundAxis(parentNormal, axis, angle);
  if (rotated.dot(childNormal) < 0.999) {
    return -angle;
  }
  return angle;
}

Vector3 _rotateVectorAroundAxis(Vector3 vector, Vector3 axis, double angle) {
  final quaternion = Quaternion.axisAngle(axis, angle);
  final result = Vector3.copy(vector);
  quaternion.rotate(result);
  return result;
}

class _FaceNeighbor {
  const _FaceNeighbor({
    required this.faceIndex,
    required this.parentEdgeStart,
    required this.parentEdgeEnd,
  });

  final int faceIndex;
  final int parentEdgeStart;
  final int parentEdgeEnd;
}

class _EdgeReference {
  const _EdgeReference({
    required this.faceIndex,
    required this.localStart,
    required this.localEnd,
  });

  final int faceIndex;
  final int localStart;
  final int localEnd;
}

class _EdgeOccurrences {
  _EdgeOccurrences();

  final List<_EdgeReference> entries = [];
}

class _UndirectedEdge {
  _UndirectedEdge(int a, int b)
    : first = math.min(a, b),
      second = math.max(a, b);

  final int first;
  final int second;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _UndirectedEdge &&
          other.first == first &&
          other.second == second;

  @override
  int get hashCode => Object.hash(first, second);
}

Vector3 _faceNormal(List<Vector3> vertices) {
  if (vertices.length < 3) {
    return Vector3.zero();
  }
  final a = vertices[0];
  final b = vertices[1];
  final c = vertices[2];
  final normal = (b - a).cross(c - a);
  if (normal.length2 == 0) {
    return Vector3.zero();
  }
  return normal.normalized();
}
