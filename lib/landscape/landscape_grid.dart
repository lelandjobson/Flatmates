import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'landscape_generator.dart';
import 'landscape_material.dart';

/// Empty cell sentinel — not a [LandscapeMaterial] index.
const int kLandscapeEmpty = -1;

/// Background / erased pixel color (matches plane BG).
const Color kLandscapeEmptyColor = Color(0xFF101418);

/// Editable material-pixel buffer for erase + CA.
class LandscapeGrid {
  LandscapeGrid._({
    required this.side,
    required this.materials,
    required this.colorT,
  });

  factory LandscapeGrid.fromGenerator(LandscapeGenerator gen) {
    final side = gen.params.clamped().worldPixelsSide;
    final materials = Int8List(side * side);
    final colorT = Float32List(side * side);
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        final i = y * side + x;
        final m = gen.materialAt(x, y);
        materials[i] = m.index;
        colorT[i] = gen.gaussianUnit(x, y, m.index);
      }
    }
    return LandscapeGrid._(side: side, materials: materials, colorT: colorT);
  }

  final int side;
  final Int8List materials;
  final Float32List colorT;

  int index(int x, int y) => y * side + x;

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < side && y < side;

  bool isEmpty(int x, int y) => materials[index(x, y)] == kLandscapeEmpty;

  LandscapeMaterial? materialAt(int x, int y) {
    final id = materials[index(x, y)];
    if (id < 0) return null;
    return LandscapeMaterial.values[id];
  }

  /// Erase a material pixel (shows as background black).
  bool erase(int x, int y) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (materials[i] == kLandscapeEmpty) return false;
    materials[i] = kLandscapeEmpty;
    colorT[i] = 0;
    return true;
  }

  /// Erase a square brush of [size]×[size] material pixels centered on (cx, cy).
  /// [size] is clamped to ≥1. Returns true if any cell changed.
  bool eraseBrush(int cx, int cy, int size) {
    final s = size < 1 ? 1 : size;
    final half = s ~/ 2;
    // For even sizes, bias toward -half .. +half-1 so the square is contiguous.
    final x0 = cx - half;
    final y0 = cy - half;
    var changed = false;
    for (var y = y0; y < y0 + s; y++) {
      for (var x = x0; x < x0 + s; x++) {
        if (erase(x, y)) changed = true;
      }
    }
    return changed;
  }

  void setMaterial(int x, int y, LandscapeMaterial material, double t) {
    final i = index(x, y);
    materials[i] = material.index;
    colorT[i] = t;
  }

  Color colorAt(int x, int y, LandscapeGenParams params) {
    final id = materials[index(x, y)];
    if (id < 0) return kLandscapeEmptyColor;
    final material = LandscapeMaterial.values[id];
    return params.gradients[material]!.sample(colorT[index(x, y)]);
  }

  int get emptyCount {
    var n = 0;
    for (final m in materials) {
      if (m == kLandscapeEmpty) n++;
    }
    return n;
  }
}
