import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Abstract base
// ---------------------------------------------------------------------------

/// Base class for tile restoration animations.
///
/// Subclass to create different visual effects per material type.
/// The painter calls [draw] every frame while the tile is on cooldown.
abstract class TileRestorationAnimation {
  /// Draw the restoration effect onto the tile area.
  ///
  /// * [canvas]        – the drawing canvas (already clipped / translated by caller).
  /// * [tilePath]      – diamond-shaped path of the tile (for clipping).
  /// * [diamondPoints] – the 4 corner offsets of the diamond (top, right, bottom, left).
  /// * [progress]      – normalised 0.0 (just gathered) to 1.0 (fully restored).
  /// * [tileColor]     – the intended final colour of the tile.
  void draw(
    Canvas canvas,
    Path tilePath,
    List<Offset> diamondPoints,
    double progress,
    Color tileColor,
  );
}

// ---------------------------------------------------------------------------
// 4x4 grid-fill implementation
// ---------------------------------------------------------------------------

/// A 4x4 grid of parallelogram cells that fill row-by-row with the tile
/// colour. The background is transparent so the tile appears to fade in
/// from nothing against the scene background.
class GridFillRestorationAnimation extends TileRestorationAnimation {
  /// Number of cells per side (4 -> 16 total cells).
  static const int gridSize = 4;
  static const int _totalCells = gridSize * gridSize;

  /// Progress threshold above which a solid tile fill is drawn behind the
  /// grid cells to prevent aliasing gaps from causing a flash on completion.
  static const double _solidBackdropThreshold = 0.95;

  // Shared paints to avoid per-frame allocation.
  static final Paint _solidPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _cellPaint = Paint()..style = PaintingStyle.fill;
  static final Paint _cellStrokePaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 0.75;

  @override
  void draw(
    Canvas canvas,
    Path tilePath,
    List<Offset> diamondPoints,
    double progress,
    Color tileColor,
  ) {
    // Clip to diamond so cells don't bleed outside the tile shape.
    canvas.save();
    canvas.clipPath(tilePath);

    // When progress is near completion, draw the full tile fill behind the
    // grid cells so the transition to a normal tile is seamless (no flash).
    if (progress >= _solidBackdropThreshold) {
      _solidPaint.color = tileColor;
      canvas.drawPath(tilePath, _solidPaint);
    }

    // Compute how many cells are filled.
    // progress 0..1 maps to 0.._totalCells filled cells.
    final filledCellsFloat = progress * _totalCells;
    final fullCells = filledCellsFloat.floor().clamp(0, _totalCells);
    final partialFill =
        filledCellsFloat - fullCells; // 0..1 within the current cell

    // Diamond basis vectors.
    //   diamondPoints: [top, right, bottom, left]
    //
    //   The tile diamond can be parametrised by two axes:
    //     u : top -> right  (and  left -> bottom)
    //     v : top -> left   (and  right -> bottom)
    //
    //   A cell at grid position (col, row) occupies:
    //     u in [col/gridSize, (col+1)/gridSize]
    //     v in [row/gridSize, (row+1)/gridSize]
    //
    //   Corner of cell (u, v):
    //     P = top + u*(right - top) + v*(left - top)
    //
    final top = diamondPoints[0];
    final right = diamondPoints[1];
    // diamondPoints[2] is the bottom vertex (unused directly).
    final left = diamondPoints[3];

    final uVec = right - top; // top->right
    final vVec = left - top; // top->left

    _cellPaint.color = tileColor;
    _cellStrokePaint.color = tileColor;

    // Helper to get a point at parametric (u, v) in [0,1]^2.
    Offset pointAt(double u, double v) => top + uVec * u + vVec * v;

    final step = 1.0 / gridSize;

    for (var cellIdx = 0; cellIdx < fullCells; cellIdx++) {
      final row = cellIdx ~/ gridSize;
      final col = cellIdx % gridSize;

      final u0 = col * step;
      final v0 = row * step;
      final u1 = u0 + step;
      final v1 = v0 + step;

      final cellPath = Path()
        ..moveTo(pointAt(u0, v0).dx, pointAt(u0, v0).dy)
        ..lineTo(pointAt(u1, v0).dx, pointAt(u1, v0).dy)
        ..lineTo(pointAt(u1, v1).dx, pointAt(u1, v1).dy)
        ..lineTo(pointAt(u0, v1).dx, pointAt(u0, v1).dy)
        ..close();

      canvas.drawPath(cellPath, _cellPaint);
      // Stroke the cell border to cover sub-pixel cracks between cells.
      canvas.drawPath(cellPath, _cellStrokePaint);
    }

    // Partial fill of the next cell.
    if (fullCells < _totalCells && partialFill > 0.001) {
      final row = fullCells ~/ gridSize;
      final col = fullCells % gridSize;

      final u0 = col * step;
      final v0 = row * step;

      // Fill horizontally within the cell (left to right sweep).
      final u1 = u0 + step * partialFill;
      final v1 = v0 + step;

      final cellPath = Path()
        ..moveTo(pointAt(u0, v0).dx, pointAt(u0, v0).dy)
        ..lineTo(pointAt(u1, v0).dx, pointAt(u1, v0).dy)
        ..lineTo(pointAt(u1, v1).dx, pointAt(u1, v1).dy)
        ..lineTo(pointAt(u0, v1).dx, pointAt(u0, v1).dy)
        ..close();

      // Use partial opacity so it doesn't pop.
      final a = tileColor.a * partialFill;
      _cellPaint.color = tileColor.withValues(alpha: a);
      canvas.drawPath(cellPath, _cellPaint);
      canvas.drawPath(cellPath, _cellStrokePaint);
      _cellPaint.color = tileColor; // restore
    }

    canvas.restore();
  }
}

// ---------------------------------------------------------------------------
// Registry
// ---------------------------------------------------------------------------

/// Registry that maps material ID to a specific [TileRestorationAnimation].
///
/// By default, all materials use [GridFillRestorationAnimation]. Call
/// [register] to override a material with a different animation style.
class TileRestorationAnimations {
  TileRestorationAnimations._();

  static final Map<String, TileRestorationAnimation> _overrides = {};
  static final TileRestorationAnimation _default =
      GridFillRestorationAnimation();

  /// Get the restoration animation for the given material ID.
  static TileRestorationAnimation forMaterialId(String materialId) =>
      _overrides[materialId] ?? _default;

  /// Register a custom animation for a material type.
  static void register(String materialId, TileRestorationAnimation anim) =>
      _overrides[materialId] = anim;

  /// Remove a custom animation override (reverts to default).
  static void unregister(String materialId) => _overrides.remove(materialId);
}
