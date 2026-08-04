import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart';

import 'geometry.dart';
import '../rendering/iso/iso_projection.dart';

/// Grid dimension for structure sprite slicing.
const int kSpriteGridSize = 5;

/// Slices a [Geometry] into a [kSpriteGridSize]x[kSpriteGridSize] grid of
/// sub-geometries by clipping faces against axis-aligned vertical planes on
/// the XZ ground plane.
///
/// The grid covers the tile footprint (±halfTile on X and Z), where each cell
/// is [cellSize] × [cellSize] world units. Faces that span multiple cells are
/// clipped at cell boundaries using Sutherland-Hodgman against the 4
/// axis-aligned bounding planes of each cell.
///
/// Returns `result[row][col]` where row maps to the Z axis and col to X.
/// Null entries mean no geometry intersects that cell.
class GeometrySlicer {
  const GeometrySlicer._();

  static final double _halfTile = IsoProjection.worldUnitsPerTile / 2;
  static final double _cellSize = IsoProjection.worldUnitsPerTile / kSpriteGridSize;

  /// Returns the column index (0-based) for a world-space X coordinate.
  static int colForX(double x) =>
      ((x + _halfTile) / _cellSize).floor().clamp(0, kSpriteGridSize - 1);

  /// Returns the row index (0-based) for a world-space Z coordinate.
  static int rowForZ(double z) =>
      ((z + _halfTile) / _cellSize).floor().clamp(0, kSpriteGridSize - 1);

  /// Slice [geometry] into a [kSpriteGridSize]x[kSpriteGridSize] grid.
  static List<List<Geometry?>> slice(Geometry geometry) {
    final cellVerts = List.generate(
      kSpriteGridSize,
      (_) => List.generate(kSpriteGridSize, (_) => <Vector3>[]),
    );
    final cellFaces = List.generate(
      kSpriteGridSize,
      (_) => List.generate(kSpriteGridSize, (_) => <List<int>>[]),
    );
    final hasFaceColors = geometry.faceColors != null;
    final cellColors = hasFaceColors
        ? List.generate(
            kSpriteGridSize,
            (_) => List.generate(kSpriteGridSize, (_) => <Color>[]),
          )
        : null;

    for (var fi = 0; fi < geometry.faces.length; fi++) {
      final face = geometry.faces[fi];
      if (face.length < 3) continue;

      final verts = [
        for (final idx in face) Vector3.copy(geometry.vertices[idx]),
      ];
      final color = geometry.faceColors != null && fi < geometry.faceColors!.length
          ? geometry.faceColors![fi]
          : null;

      double minX = verts[0].x, maxX = verts[0].x;
      double minZ = verts[0].z, maxZ = verts[0].z;
      for (final v in verts) {
        minX = math.min(minX, v.x);
        maxX = math.max(maxX, v.x);
        minZ = math.min(minZ, v.z);
        maxZ = math.max(maxZ, v.z);
      }

      final cMin = colForX(minX);
      final cMax = colForX(maxX);
      final rMin = rowForZ(minZ);
      final rMax = rowForZ(maxZ);

      if (cMin == cMax && rMin == rMax) {
        _addFace(cellVerts, cellFaces, cellColors, rMin, cMin, verts, color);
        continue;
      }

      for (int r = rMin; r <= rMax; r++) {
        for (int c = cMin; c <= cMax; c++) {
          final xLo = -_halfTile + c * _cellSize;
          final xHi = -_halfTile + (c + 1) * _cellSize;
          final zLo = -_halfTile + r * _cellSize;
          final zHi = -_halfTile + (r + 1) * _cellSize;

          var clipped = verts;
          clipped = _clipAxis(clipped, 0, xLo, true);
          if (clipped.length < 3) continue;
          clipped = _clipAxis(clipped, 0, xHi, false);
          if (clipped.length < 3) continue;
          clipped = _clipAxis(clipped, 2, zLo, true);
          if (clipped.length < 3) continue;
          clipped = _clipAxis(clipped, 2, zHi, false);
          if (clipped.length < 3) continue;

          _addFace(cellVerts, cellFaces, cellColors, r, c, clipped, color);
        }
      }
    }

    return List.generate(kSpriteGridSize, (r) {
      return List.generate(kSpriteGridSize, (c) {
        if (cellFaces[r][c].isEmpty) return null;
        return Geometry(
          id: '${geometry.id}_${r}_$c',
          name: '${geometry.name}[$r,$c]',
          vertices: cellVerts[r][c],
          faces: cellFaces[r][c],
          colorSeed: geometry.colorSeed,
          faceColors: cellColors?[r][c],
        );
      });
    });
  }

  static void _addFace(
    List<List<List<Vector3>>> verts,
    List<List<List<List<int>>>> faces,
    List<List<List<Color>>>? colors,
    int r,
    int c,
    List<Vector3> faceVerts,
    Color? color,
  ) {
    final base = verts[r][c].length;
    verts[r][c].addAll(faceVerts);
    faces[r][c].add([for (int k = 0; k < faceVerts.length; k++) base + k]);
    if (colors != null && color != null) {
      colors[r][c].add(color);
    }
  }

  /// Sutherland-Hodgman clip of a 3D polygon against an axis-aligned plane.
  ///
  /// [axis] 0 = X, 1 = Y, 2 = Z.
  /// When [keepGreater] is true, keeps the half-space >= [boundary].
  static List<Vector3> _clipAxis(
    List<Vector3> vertices,
    int axis,
    double boundary,
    bool keepGreater,
  ) {
    if (vertices.length < 3) return vertices;
    final out = <Vector3>[];
    final n = vertices.length;

    for (int i = 0; i < n; i++) {
      final cur = vertices[i];
      final prev = vertices[(i + n - 1) % n];
      final cVal = _ax(cur, axis);
      final pVal = _ax(prev, axis);
      final cIn = keepGreater ? cVal >= boundary - 1e-9 : cVal <= boundary + 1e-9;
      final pIn = keepGreater ? pVal >= boundary - 1e-9 : pVal <= boundary + 1e-9;

      if (cIn) {
        if (!pIn) out.add(_intersect(prev, cur, axis, boundary));
        out.add(Vector3.copy(cur));
      } else if (pIn) {
        out.add(_intersect(prev, cur, axis, boundary));
      }
    }
    return out;
  }

  static double _ax(Vector3 v, int axis) {
    if (axis == 0) return v.x;
    if (axis == 1) return v.y;
    return v.z;
  }

  static Vector3 _intersect(Vector3 a, Vector3 b, int axis, double boundary) {
    final aV = _ax(a, axis);
    final bV = _ax(b, axis);
    final d = bV - aV;
    if (d.abs() < 1e-12) return Vector3.copy(a);
    final t = (boundary - aV) / d;
    return Vector3(
      a.x + t * (b.x - a.x),
      a.y + t * (b.y - a.y),
      a.z + t * (b.z - a.z),
    );
  }
}
