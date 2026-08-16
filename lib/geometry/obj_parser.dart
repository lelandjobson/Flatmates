import 'package:vector_math/vector_math_64.dart';

import 'geometry.dart';

/// Lightweight Wavefront OBJ parser that produces a [Geometry] directly.
///
/// Only the vertex (`v`) and face (`f`) directives are required; all other
/// directives (normals, texture coords, groups, materials, etc.) are ignored.
/// Face indices may include texture/normal data (e.g. `f 1/2/3 4/5/6`) and
/// can use positive or negative OBJ indexing.
class ObjParser {
  const ObjParser._();

  /// Parses a Wavefront OBJ source string into a [Geometry].
  ///
  /// Duplicate vertices (within floating-point quantisation tolerance) are
  /// merged so face indices stay consistent.
  ///
  /// When [center] is true (default), the geometry is auto-centered so X/Z
  /// are centered at the origin and Y starts at 0. Set to false when loading
  /// meshes that share a world coordinate frame — the caller is then
  /// responsible for centering the combined result.
  static Geometry parse({
    required String id,
    required String name,
    required String source,
    bool center = true,
  }) {
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
      if (line.isEmpty) continue;

      final tokens = line.split(RegExp(r'\s+'));
      if (tokens.isEmpty) continue;
      final prefix = tokens.first;

      if (prefix == 'v') {
        if (tokens.length < 4) {
          throw FormatException('Malformed vertex line: "$rawLine"');
        }
        final x = _parseDouble(tokens[1], rawLine);
        final objY = _parseDouble(tokens[2], rawLine);
        final objZ = _parseDouble(tokens[3], rawLine);
        // Rhino OBJ exports use Z-up (X,Y ground, Z height); swap to
        // engine Y-up convention (X,Z ground, Y height).
        final y = objZ;
        final z = objY;
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
          if (element.isEmpty) continue;
          final vertexToken = element.split('/').first;
          if (vertexToken.isEmpty) {
            throw FormatException(
              'Face vertex is missing an index: "$rawLine"',
            );
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

    if (vertices.isEmpty) {
      throw const FormatException('OBJ source did not contain any vertices.');
    }
    if (faces.isEmpty) {
      throw const FormatException('OBJ source did not contain any faces.');
    }

    if (center) {
      _centerGeometry(vertices);
    }

    return ensureOutwardFacingGeometry(
      Geometry(id: id, name: name, vertices: vertices, faces: faces),
    );
  }

  /// Parses named `o` / `g` groups into separate geometries.
  ///
  /// Vertices stay in a shared world frame ([center] is not applied). Groups
  /// with no faces are omitted.
  static Map<String, Geometry> parseGroups({
    required String id,
    required String source,
  }) {
    final vertices = <Vector3>[];
    final vertexIndexRemap = <int>[];
    final dedupeLookup = <_VectorKey, int>{};
    final facesByGroup = <String, List<List<int>>>{};
    var currentGroup = 'default';
    final lines = source.split(RegExp(r'\r?\n'));

    for (final rawLine in lines) {
      var line = rawLine;
      final commentIndex = line.indexOf('#');
      if (commentIndex != -1) {
        line = line.substring(0, commentIndex);
      }
      line = line.trim();
      if (line.isEmpty) continue;

      final tokens = line.split(RegExp(r'\s+'));
      if (tokens.isEmpty) continue;
      final prefix = tokens.first;

      if (prefix == 'o' || prefix == 'g') {
        currentGroup = tokens.length > 1 ? tokens.sublist(1).join(' ') : prefix;
        facesByGroup.putIfAbsent(currentGroup, () => []);
        continue;
      }

      if (prefix == 'v') {
        if (tokens.length < 4) {
          throw FormatException('Malformed vertex line: "$rawLine"');
        }
        final x = _parseDouble(tokens[1], rawLine);
        final objY = _parseDouble(tokens[2], rawLine);
        final objZ = _parseDouble(tokens[3], rawLine);
        final y = objZ;
        final z = objY;
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
          if (element.isEmpty) continue;
          final vertexToken = element.split('/').first;
          if (vertexToken.isEmpty) {
            throw FormatException(
              'Face vertex is missing an index: "$rawLine"',
            );
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
        (facesByGroup[currentGroup] ??= []).add(indices);
      }
    }

    if (vertices.isEmpty) {
      throw const FormatException('OBJ source did not contain any vertices.');
    }

    final result = <String, Geometry>{};
    for (final entry in facesByGroup.entries) {
      if (entry.value.isEmpty) continue;
      result[entry.key] = _geometryFromSharedVertices(
        id: '${id}_${entry.key}',
        name: entry.key,
        vertices: vertices,
        faces: entry.value,
      );
    }
    return result;
  }

  static Geometry _geometryFromSharedVertices({
    required String id,
    required String name,
    required List<Vector3> vertices,
    required List<List<int>> faces,
  }) {
    final used = <int>{};
    for (final face in faces) {
      used.addAll(face);
    }
    final remap = <int, int>{};
    final compactVerts = <Vector3>[];
    for (final oldIndex in used.toList()..sort()) {
      remap[oldIndex] = compactVerts.length;
      compactVerts.add(vertices[oldIndex].clone());
    }
    final compactFaces = [
      for (final face in faces) [for (final i in face) remap[i]!],
    ];
    return ensureOutwardFacingGeometry(
      Geometry(id: id, name: name, vertices: compactVerts, faces: compactFaces),
    );
  }
}

void _centerGeometry(List<Vector3> vertices) {
  var minX = vertices[0].x, maxX = vertices[0].x;
  var minY = vertices[0].y, maxY = vertices[0].y;
  var minZ = vertices[0].z, maxZ = vertices[0].z;
  for (final v in vertices) {
    if (v.x < minX) minX = v.x;
    if (v.x > maxX) maxX = v.x;
    if (v.y < minY) minY = v.y;
    if (v.y > maxY) maxY = v.y;
    if (v.z < minZ) minZ = v.z;
    if (v.z > maxZ) maxZ = v.z;
  }
  final cx = (minX + maxX) / 2;
  final cz = (minZ + maxZ) / 2;
  for (final v in vertices) {
    v.x -= cx;
    v.y -= minY;
    v.z -= cz;
  }
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
