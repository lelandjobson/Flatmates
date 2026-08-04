import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../geometry/geometry_slicer.dart';
import 'iso_projection.dart';

/// A 5x5 grid of pre-rendered sprite cell pictures for a single view.
///
/// Each cell corresponds to a vertical column of the structure's geometry on
/// the tile XZ footprint. At draw time the grid is split into "behind" and
/// "in-front" sets relative to the tile center (where friends walk) based on
/// the current camera view angle.
///
/// Depth ordering uses the same [IsoProjection.depthForAngle] formula as tile
/// ordering: cells with higher depth (closer to camera) are "foreground" and
/// cells with lower depth (further from camera) are "background".
class IsoSpriteGrid {
  IsoSpriteGrid({
    required this.cells,
    required this.combined,
    required this.size,
  })  : assert(cells.length == kSpriteGridSize),
        _sortedCells = List.generate(IsoProjection.viewCount, (_) => <_CellEntry>[]),
        _bgCells = List.generate(IsoProjection.viewCount, (_) => <_CellEntry>[]),
        _fgCells = List.generate(IsoProjection.viewCount, (_) => <_CellEntry>[]) {
    _precomputeDepthOrder();
  }

  /// 5x5 grid of rendered cell pictures. Null = no geometry in that cell.
  final List<List<ui.Picture?>> cells;

  /// Full composite picture (all cells drawn together with correct global
  /// depth sort). Used when no friend-occlusion split is needed.
  final ui.Picture combined;

  /// Authoring size shared by all cell pictures.
  final Size size;

  /// Per-view depth-sorted cell list (all populated cells, ascending depth).
  /// Used by [drawInterleaved] for per-cell friend interleaving.
  final List<List<_CellEntry>> _sortedCells;

  /// Per-view background cells (depth < 0, further from camera).
  /// Sorted ascending by depth (furthest drawn first).
  final List<List<_CellEntry>> _bgCells;

  /// Per-view foreground cells (depth >= 0, closer to camera).
  /// Sorted ascending by depth.
  final List<List<_CellEntry>> _fgCells;

  void _precomputeDepthOrder() {
    for (int v = 0; v < IsoProjection.viewCount; v++) {
      final angle = IsoProjection.angleForView(v);
      final entries = <_CellEntry>[];

      for (int r = 0; r < kSpriteGridSize; r++) {
        for (int c = 0; c < kSpriteGridSize; c++) {
          if (cells[r][c] == null) continue;
          final depth = IsoProjection.depthForAngle(
            c - kSpriteGridSize ~/ 2,
            r - kSpriteGridSize ~/ 2,
            angle,
          );
          entries.add(_CellEntry(r, c, depth));
        }
      }

      entries.sort((a, b) => a.depth.compareTo(b.depth));
      _sortedCells[v] = entries;

      for (final e in entries) {
        if (e.depth >= 0) {
          _fgCells[v].add(e);
        } else {
          _bgCells[v].add(e);
        }
      }
    }
  }

  /// Whether any cells have geometry.
  bool get isEmpty {
    for (final row in cells) {
      for (final cell in row) {
        if (cell != null) return false;
      }
    }
    return true;
  }

  /// Number of non-null cells.
  int get populatedCellCount {
    int count = 0;
    for (final row in cells) {
      for (final cell in row) {
        if (cell != null) count++;
      }
    }
    return count;
  }

  // Shared paint to avoid per-draw allocation for opacity.
  static final Paint _opacityPaint = Paint();
  static final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;

  /// Pre-rasterized image of the combined picture.
  ui.Image? _combinedRaster;

  /// Pre-rasterized images of individual cell pictures.
  List<List<ui.Image?>>? _cellRasters;

  void _ensureCombinedRaster() {
    _combinedRaster ??= combined.toImageSync(
      size.width.ceil(),
      size.height.ceil(),
    );
  }

  void _ensureCellRasters() {
    if (_cellRasters != null) return;
    _cellRasters = List.generate(kSpriteGridSize, (row) {
      return List.generate(kSpriteGridSize, (col) {
        final pic = cells[row][col];
        if (pic == null) return null;
        return pic.toImageSync(size.width.ceil(), size.height.ceil());
      });
    });
  }

  /// Draw all cells using a pre-rasterized image (fast path).
  void drawAll(Canvas canvas, Rect destination, Paint? paint) {
    _ensureCombinedRaster();
    _drawImage(canvas, destination, paint, _combinedRaster!);
  }

  /// Draw only the "behind" cells for [viewIndex] (further from camera,
  /// drawn before friends).
  void drawBehind(Canvas canvas, Rect destination, Paint? paint,
      {required int viewIndex}) {
    _ensureCellRasters();
    final idx = viewIndex % IsoProjection.viewCount;
    for (final e in _bgCells[idx]) {
      final img = _cellRasters![e.row][e.col];
      if (img != null) _drawImage(canvas, destination, paint, img);
    }
  }

  /// Draw only the "in-front" cells for [viewIndex] (closer to camera,
  /// drawn after friends).
  void drawInFront(Canvas canvas, Rect destination, Paint? paint,
      {required int viewIndex}) {
    _ensureCellRasters();
    final idx = viewIndex % IsoProjection.viewCount;
    for (final e in _fgCells[idx]) {
      final img = _cellRasters![e.row][e.col];
      if (img != null) _drawImage(canvas, destination, paint, img);
    }
  }

  /// Draw grid cells interleaved with a single friend based on depth.
  ///
  /// Cells with depth < [friendDepth] are drawn first, then [drawFriend] is
  /// called, then remaining cells. This produces correct painter-order
  /// occlusion for a friend walking through the structure.
  void drawInterleavedSingle(
    Canvas canvas, Rect destination, Paint? paint,
    double friendDepth, int viewIndex,
    void Function() drawFriend,
  ) {
    _ensureCellRasters();
    final sorted = _sortedCells[viewIndex % IsoProjection.viewCount];
    bool friendDrawn = false;
    for (final e in sorted) {
      if (!friendDrawn && e.depth >= friendDepth) {
        drawFriend();
        friendDrawn = true;
      }
      final img = _cellRasters![e.row][e.col];
      if (img != null) _drawImage(canvas, destination, paint, img);
    }
    if (!friendDrawn) drawFriend();
  }

  /// Draw grid cells interleaved with multiple friends sorted by depth.
  ///
  /// [friends] must be pre-sorted ascending by depth. Each entry is a depth
  /// value and a draw callback. Cells and friends are merged in a single
  /// O(N+F) pass with no allocation.
  void drawInterleaved(
    Canvas canvas, Rect destination, Paint? paint,
    List<(double, VoidCallback)> friends,
    int viewIndex,
  ) {
    _ensureCellRasters();
    final sorted = _sortedCells[viewIndex % IsoProjection.viewCount];
    int fi = 0;
    for (final e in sorted) {
      while (fi < friends.length && friends[fi].$1 < e.depth) {
        friends[fi].$2();
        fi++;
      }
      final img = _cellRasters![e.row][e.col];
      if (img != null) _drawImage(canvas, destination, paint, img);
    }
    while (fi < friends.length) {
      friends[fi].$2();
      fi++;
    }
  }

  void _drawImage(
      Canvas canvas, Rect destination, Paint? paint, ui.Image img) {
    final alpha = paint?.color.a ?? 1.0;
    final hasOpacity = alpha < 1.0;
    final hasColorFilter = paint?.colorFilter != null;
    final src = Rect.fromLTWH(
        0, 0, img.width.toDouble(), img.height.toDouble());

    if (hasOpacity || hasColorFilter) {
      _imagePaint.color = Color.fromRGBO(0, 0, 0, alpha);
      _imagePaint.colorFilter = paint?.colorFilter;
      canvas.drawImageRect(img, src, destination, _imagePaint);
      _imagePaint.color = const Color(0xFFFFFFFF);
      _imagePaint.colorFilter = null;
    } else {
      canvas.drawImageRect(img, src, destination, _imagePaint);
    }
  }

  void _drawPicture(
      Canvas canvas, Rect destination, Paint? paint, ui.Picture pic) {
    final scaleX = destination.width / size.width;
    final scaleY = destination.height / size.height;

    final alpha = paint?.color.a ?? 1.0;
    final hasOpacity = alpha < 1.0;
    final hasColorFilter = paint?.colorFilter != null;

    if (hasOpacity || hasColorFilter) {
      _opacityPaint.color = Color.fromRGBO(0, 0, 0, alpha);
      _opacityPaint.colorFilter = paint?.colorFilter;
      canvas.saveLayer(destination, _opacityPaint);
    } else {
      canvas.save();
    }

    canvas.translate(destination.left, destination.top);
    canvas.scale(scaleX, scaleY);
    canvas.drawPicture(pic);
    canvas.restore();

    if (hasColorFilter) {
      _opacityPaint.colorFilter = null;
    }
  }

  /// The number of background cells for a given view.
  int backgroundCellCount(int viewIndex) =>
      _bgCells[viewIndex % IsoProjection.viewCount].length;

  /// The number of foreground cells for a given view.
  int foregroundCellCount(int viewIndex) =>
      _fgCells[viewIndex % IsoProjection.viewCount].length;

  /// Number of populated cells for a given view's sorted list.
  int sortedCellCount(int viewIndex) =>
      _sortedCells[viewIndex % IsoProjection.viewCount].length;

  /// Spectral gradient: red (0) -> orange -> yellow -> green -> blue (1).
  static Color spectralColor(double t) {
    t = t.clamp(0.0, 1.0);
    if (t < 0.25) {
      return Color.lerp(
          const Color(0xFFFF0000), const Color(0xFFFF8800), t / 0.25)!;
    } else if (t < 0.5) {
      return Color.lerp(const Color(0xFFFF8800), const Color(0xFFFFFF00),
          (t - 0.25) / 0.25)!;
    } else if (t < 0.75) {
      return Color.lerp(const Color(0xFFFFFF00), const Color(0xFF00CC00),
          (t - 0.5) / 0.25)!;
    } else {
      return Color.lerp(const Color(0xFF00CC00), const Color(0xFF0044FF),
          (t - 0.75) / 0.25)!;
    }
  }

  static final Paint _tintOverlay = Paint();
  static final Paint _layerPaint = Paint();

  /// Draw a cell then overlay a semi-transparent spectral tint using srcATop
  /// (only tints opaque pixels, so the color is visible regardless of the
  /// cell's brightness).
  void _drawCellTinted(
      Canvas canvas, Rect destination, ui.Picture pic, Color tint) {
    // Cell pictures can project well above the destination rect (tall
    // structures), so inflate the layer bounds to avoid clipping.
    final layerBounds = destination.inflate(destination.height);
    canvas.saveLayer(layerBounds, _layerPaint);
    _drawPicture(canvas, destination, null, pic);
    _tintOverlay
      ..color = tint.withValues(alpha: 0.55)
      ..blendMode = BlendMode.srcATop;
    canvas.drawRect(layerBounds, _tintOverlay);
    canvas.restore();
  }

  /// Draw all cells with per-cell colors from a [kSpriteGridSize]x[kSpriteGridSize]
  /// color grid. Each cell at `[row][col]` is tinted with the corresponding
  /// color from [cellColors].
  void drawAllWithTheme(
      Canvas canvas, Rect destination, List<List<Color>> cellColors, int viewIndex) {
    final sorted = _sortedCells[viewIndex % IsoProjection.viewCount];
    for (final e in sorted) {
      final color = cellColors[e.row][e.col];
      _drawCellTinted(canvas, destination, cells[e.row][e.col]!, color);
    }
  }

  /// Draw grid cells interleaved with friends, applying per-cell colors
  /// from a theme grid. Friends are drawn without tinting.
  void drawInterleavedWithTheme(
    Canvas canvas, Rect destination,
    List<List<Color>> cellColors,
    List<(double, VoidCallback)> friends,
    int viewIndex,
  ) {
    final sorted = _sortedCells[viewIndex % IsoProjection.viewCount];
    int fi = 0;
    for (final e in sorted) {
      while (fi < friends.length && friends[fi].$1 < e.depth) {
        friends[fi].$2();
        fi++;
      }
      _drawCellTinted(
          canvas, destination, cells[e.row][e.col]!, cellColors[e.row][e.col]);
    }
    while (fi < friends.length) {
      friends[fi].$2();
      fi++;
    }
  }

  /// Draw all cells individually with a spectral gradient tint based on
  /// their depth-sorted draw order.
  void drawAllTinted(Canvas canvas, Rect destination, int viewIndex) {
    final sorted = _sortedCells[viewIndex % IsoProjection.viewCount];
    final total = sorted.length;
    for (int i = 0; i < total; i++) {
      final e = sorted[i];
      final t = total > 1 ? i / (total - 1) : 0.5;
      _drawCellTinted(
          canvas, destination, cells[e.row][e.col]!, spectralColor(t));
    }
  }

  /// Draw cells interleaved with friends, applying spectral tints.
  ///
  /// Each cell and friend receives a tint based on its position in the merged
  /// draw sequence. Friend callbacks receive the [Color] to use for their
  /// own tint indicator.
  void drawInterleavedTinted(
    Canvas canvas, Rect destination,
    List<(double, void Function(Color))> friends,
    int viewIndex,
  ) {
    final sorted = _sortedCells[viewIndex % IsoProjection.viewCount];
    final totalItems = sorted.length + friends.length;
    final maxIdx = (totalItems - 1).clamp(1, totalItems);
    int fi = 0;
    int drawIdx = 0;
    for (final e in sorted) {
      while (fi < friends.length && friends[fi].$1 < e.depth) {
        friends[fi].$2(spectralColor(drawIdx / maxIdx));
        fi++;
        drawIdx++;
      }
      _drawCellTinted(canvas, destination, cells[e.row][e.col]!,
          spectralColor(drawIdx / maxIdx));
      drawIdx++;
    }
    while (fi < friends.length) {
      friends[fi].$2(spectralColor(drawIdx / maxIdx));
      fi++;
      drawIdx++;
    }
  }

  /// Depth value for cell (row, col) at a given view angle.
  static double cellDepth(int row, int col, double angleRad) {
    return IsoProjection.depthForAngle(
      col - kSpriteGridSize ~/ 2,
      row - kSpriteGridSize ~/ 2,
      angleRad,
    );
  }

  /// Disposes only the per-cell pictures. The [combined] picture is NOT
  /// disposed here because it is shared with (and owned by) the parent
  /// [VectorIsoSprite.picture].
  void dispose() {
    for (final row in cells) {
      for (final cell in row) {
        cell?.dispose();
      }
    }
  }
}

class _CellEntry {
  const _CellEntry(this.row, this.col, this.depth);
  final int row;
  final int col;
  final double depth;
}
