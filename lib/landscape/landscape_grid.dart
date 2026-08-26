import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../crafting/placed_paper.dart';
import '../theme/world_theme.dart';
import 'landscape_generator.dart';
import 'landscape_material.dart';

/// Empty cell sentinel — not a [LandscapeMaterial] index. CA may refill these.
const int kLandscapeEmpty = -1;

/// Covered / no-grow cell. Cleared by volumes and paths; CA must not refill.
const int kLandscapeVoid = -2;

/// Background / erased pixel color (matches plane BG).
const Color kLandscapeEmptyColor = Color(0xFF101418);

/// Editable material-pixel buffer for erase + CA.
class LandscapeGrid {
  LandscapeGrid._({
    required this.side,
    required this.materials,
    required this.colorT,
    required this.paintIds,
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
    return LandscapeGrid._(
      side: side,
      materials: materials,
      colorT: colorT,
      paintIds: Int8List(side * side)..fillRange(0, side * side, kNoPaint),
    );
  }

  LandscapeGrid copy() => LandscapeGrid._(
        side: side,
        materials: Int8List.fromList(materials),
        colorT: Float32List.fromList(colorT),
        paintIds: Int8List.fromList(paintIds),
      );

  void restoreFrom(LandscapeGrid other) {
    if (other.side != side) return;
    materials.setAll(0, other.materials);
    colorT.setAll(0, other.colorT);
    paintIds.setAll(0, other.paintIds);
  }

  final int side;
  final Int8List materials;
  final Float32List colorT;

  /// [PaperColor.index], or [kNoPaint] when the baked material shows through.
  final Int8List paintIds;

  static const int kNoPaint = -1;

  int index(int x, int y) => y * side + x;

  bool inBounds(int x, int y) => x >= 0 && y >= 0 && x < side && y < side;

  bool isEmpty(int x, int y) => materials[index(x, y)] == kLandscapeEmpty;

  bool isVoid(int x, int y) => materials[index(x, y)] == kLandscapeVoid;

  /// True when the cell already has paper paint or generated landscape
  /// (not an erased hole). Flood fill stops at these cells.
  bool isDrawn(int x, int y) {
    if (!inBounds(x, y)) return true;
    final i = index(x, y);
    if (paintIds[i] >= 0) return true;
    return materials[i] != kLandscapeEmpty;
  }

  /// Click on a drawn pixel → that pixel only. Click on empty → 4-connected
  /// flood of empty cells, stopped by any drawn pixel.
  bool fill(int x, int y, PaperColor color) {
    if (!inBounds(x, y)) return false;
    if (isDrawn(x, y)) return paint(x, y, color);

    var changed = false;
    final stack = <(int, int)>[(x, y)];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final (cx, cy) = stack.removeLast();
      if (!inBounds(cx, cy) || isDrawn(cx, cy)) continue;
      final i = index(cx, cy);
      if (!seen.add(i)) continue;
      if (paint(cx, cy, color)) changed = true;
      stack
        ..add((cx + 1, cy))
        ..add((cx - 1, cy))
        ..add((cx, cy + 1))
        ..add((cx, cy - 1));
    }
    return changed;
  }

  /// Flood 4-connected pixels that share [x],[y]'s landscape material.
  ///
  /// Stops at a different material, void, or when [allow] rejects a pixel.
  /// Used to fill one like-material pocket inside a walled region.
  bool fillConnectedMaterial(
    int x,
    int y,
    PaperColor color, {
    bool Function(int x, int y)? allow,
  }) {
    if (!inBounds(x, y) || isVoid(x, y)) return false;
    if (allow != null && !allow(x, y)) return false;
    final seed = materials[index(x, y)];

    bool same(int cx, int cy) {
      if (!inBounds(cx, cy) || isVoid(cx, cy)) return false;
      if (allow != null && !allow(cx, cy)) return false;
      return materials[index(cx, cy)] == seed;
    }

    var changed = false;
    final stack = <(int, int)>[(x, y)];
    final seen = <int>{};
    while (stack.isNotEmpty) {
      final (cx, cy) = stack.removeLast();
      if (!same(cx, cy)) continue;
      final i = index(cx, cy);
      if (!seen.add(i)) continue;
      if (paint(cx, cy, color)) changed = true;
      stack
        ..add((cx + 1, cy))
        ..add((cx - 1, cy))
        ..add((cx, cy + 1))
        ..add((cx, cy - 1));
    }
    return changed;
  }

  LandscapeMaterial? materialAt(int x, int y) {
    final id = materials[index(x, y)];
    if (id < 0) return null;
    return LandscapeMaterial.values[id];
  }

  /// Erase a material pixel (shows as background black). Does not touch void.
  bool erase(int x, int y) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (materials[i] == kLandscapeVoid) return false;
    if (materials[i] == kLandscapeEmpty && paintIds[i] == kNoPaint) {
      return false;
    }
    materials[i] = kLandscapeEmpty;
    colorT[i] = 0;
    paintIds[i] = kNoPaint;
    return true;
  }

  /// Mark a cell as covered void. Clears paint. CA will not refill it.
  bool cover(int x, int y) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (materials[i] == kLandscapeVoid && paintIds[i] == kNoPaint) {
      return false;
    }
    materials[i] = kLandscapeVoid;
    colorT[i] = 0;
    paintIds[i] = kNoPaint;
    return true;
  }

  /// Restore a void cell to the generated material (coverer was removed).
  bool uncover(int x, int y, LandscapeGenerator gen) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (materials[i] != kLandscapeVoid) return false;
    final m = gen.materialAt(x, y);
    materials[i] = m.index;
    colorT[i] = gen.gaussianUnit(x, y, m.index);
    paintIds[i] = kNoPaint;
    return true;
  }

  /// Cover [covered] pixels as void; uncover leftover voids back to generated.
  bool applyCoverage(Set<(int, int)> covered, LandscapeGenerator gen) {
    var changed = false;
    for (var y = 0; y < side; y++) {
      for (var x = 0; x < side; x++) {
        if (covered.contains((x, y))) {
          if (cover(x, y)) changed = true;
        } else if (isVoid(x, y)) {
          if (uncover(x, y, gen)) changed = true;
        }
      }
    }
    return changed;
  }

  /// Paint a paper color onto a cell (overrides material until erased).
  /// Void / covered cells cannot be painted.
  bool paint(int x, int y, PaperColor color) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (materials[i] == kLandscapeVoid) return false;
    if (paintIds[i] == color.index) return false;
    paintIds[i] = color.index;
    return true;
  }

  bool paintBrush(int cx, int cy, PaperColor color, {int size = 1}) {
    final s = size < 1 ? 1 : size;
    final half = s ~/ 2;
    final x0 = cx - half;
    final y0 = cy - half;
    var changed = false;
    for (var y = y0; y < y0 + s; y++) {
      for (var x = x0; x < x0 + s; x++) {
        if (paint(x, y, color)) changed = true;
      }
    }
    return changed;
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
    if (materials[i] == kLandscapeVoid) return;
    materials[i] = material.index;
    colorT[i] = t;
  }

  Color colorAt(
    int x,
    int y,
    LandscapeGenParams params, {
    WorldTheme? theme,
  }) {
    final look = theme ?? WorldTheme.paperDiorama;
    final i = index(x, y);
    final paintId = paintIds[i];
    if (paintId >= 0 && paintId < PaperColor.values.length) {
      return look.paper(PaperColor.values[paintId]);
    }
    final id = materials[i];
    if (id < 0) return look.background;
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
