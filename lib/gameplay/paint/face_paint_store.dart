import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:vector_math/vector_math_64.dart';

import '../../crafting/placed_paper.dart';
import '../viewers/world_plane.dart';
import '../volumes/volume.dart';
import '../volumes/volume_door.dart';
import '../volumes/volume_store.dart';

@immutable
class FacePaintKey {
  const FacePaintKey({
    required this.volumeId,
    required this.tx,
    required this.ty,
    required this.face,
  });

  final int volumeId;
  final int tx;
  final int ty;
  final VolumeFace face;

  @override
  bool operator ==(Object other) =>
      other is FacePaintKey &&
      other.volumeId == volumeId &&
      other.tx == tx &&
      other.ty == ty &&
      other.face == face;

  @override
  int get hashCode => Object.hash(volumeId, tx, ty, face);
}

/// Paper-color canvas on one volume AABB face.
class FaceCanvas {
  FaceCanvas({required this.width, required this.height})
      : cells = Int8List(width * height)
          ..fillRange(0, width * height, kEmpty);

  FaceCanvas.fromCells({
    required this.width,
    required this.height,
    required List<int> cells,
  }) : cells = Int8List.fromList(cells) {
    if (this.cells.length != width * height) {
      throw ArgumentError.value(
        cells.length,
        'cells.length',
        'expected ${width * height}',
      );
    }
  }

  static const int kEmpty = -1;
  static const int kVoid = -2;

  final int width;
  final int height;
  final Int8List cells;

  int index(int x, int y) => y * width + x;

  bool inBounds(int x, int y) =>
      x >= 0 && y >= 0 && x < width && y < height;

  bool isDrawn(int x, int y) {
    if (!inBounds(x, y)) return true;
    final id = cells[index(x, y)];
    return id >= 0 || id == kVoid;
  }

  bool isVoid(int x, int y) => inBounds(x, y) && cells[index(x, y)] == kVoid;

  bool isEmpty(int x, int y) => inBounds(x, y) && !isDrawn(x, y);

  PaperColor? colorAt(int x, int y) {
    if (!inBounds(x, y)) return null;
    final id = cells[index(x, y)];
    if (id < 0 || id >= PaperColor.values.length) return null;
    return PaperColor.values[id];
  }

  bool paint(int x, int y, PaperColor color) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (cells[i] == kVoid) return false;
    if (cells[i] == color.index) return false;
    cells[i] = color.index;
    return true;
  }

  bool erase(int x, int y) {
    if (!inBounds(x, y)) return false;
    final i = index(x, y);
    if (cells[i] == kVoid || cells[i] == kEmpty) return false;
    cells[i] = kEmpty;
    return true;
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

  FaceCanvas copy() {
    final next = FaceCanvas(width: width, height: height);
    next.cells.setAll(0, cells);
    return next;
  }

  FaceCanvas resized(int newWidth, int newHeight) {
    if (newWidth == width && newHeight == height) return this;
    final next = FaceCanvas(width: newWidth, height: newHeight);
    final copyW = width < newWidth ? width : newWidth;
    final copyH = height < newHeight ? height : newHeight;
    for (var y = 0; y < copyH; y++) {
      for (var x = 0; x < copyW; x++) {
        next.cells[next.index(x, y)] = cells[index(x, y)];
      }
    }
    return next;
  }
}

class FacePaintStore {
  FacePaintStore();

  final Map<FacePaintKey, FaceCanvas> _canvases = {};

  Map<FacePaintKey, FaceCanvas> get canvases => Map.unmodifiable(_canvases);

  static (int width, int height) faceSize(BoxPrimitive box, VolumeFace face) {
    return switch (face) {
      VolumeFace.posY || VolumeFace.negY => (
          box.widthSubtiles,
          box.depthSubtiles,
        ),
      VolumeFace.posX || VolumeFace.negX => (
          box.depthSubtiles,
          box.heightSubtiles,
        ),
      VolumeFace.posZ || VolumeFace.negZ => (
          box.widthSubtiles,
          box.heightSubtiles,
        ),
    };
  }

  /// Subtile indices on [face] for a world hit, or null if outside the box.
  static (int u, int v)? pixelAt({
    required Vector3 world,
    required VolumeGrid grid,
    required VolumeCell cell,
    required VolumeFace face,
  }) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final s = grid.subtileSize;
    if (s <= 1e-8) return null;
    final (w, h) = faceSize(cell.box, face);
    late final double au;
    late final double av;
    switch (face) {
      case VolumeFace.posY:
      case VolumeFace.negY:
        au = (world.x - min.x) / s;
        av = (world.z - min.z) / s;
      case VolumeFace.posX:
      case VolumeFace.negX:
        au = (world.z - min.z) / s;
        av = (world.y - min.y) / s;
      case VolumeFace.posZ:
      case VolumeFace.negZ:
        au = (world.x - min.x) / s;
        av = (world.y - min.y) / s;
    }
    final u = au.floor().clamp(0, w - 1);
    final v = av.floor().clamp(0, h - 1);
    if (au < -1e-4 || av < -1e-4 || au > w + 1e-4 || av > h + 1e-4) {
      return null;
    }
    return (u, v);
  }

  static List<Vector3> pixelCorners({
    required int u,
    required int v,
    required VolumeGrid grid,
    required VolumeCell cell,
    required VolumeFace face,
    double outset = 0.04,
  }) {
    final min = cell.box.worldMin(grid, cell.tx, cell.ty);
    final max = cell.box.worldMax(grid, cell.tx, cell.ty);
    final s = grid.subtileSize;
    final n = face.originAndNormal(min, max).$2;
    final lift = n * outset;
    switch (face) {
      case VolumeFace.posY:
        {
          final x0 = min.x + u * s;
          final z0 = min.z + v * s;
          final y = max.y;
          return [
            Vector3(x0, y, z0) + lift,
            Vector3(x0, y, z0 + s) + lift,
            Vector3(x0 + s, y, z0 + s) + lift,
            Vector3(x0 + s, y, z0) + lift,
          ];
        }
      case VolumeFace.negY:
        {
          final x0 = min.x + u * s;
          final z0 = min.z + v * s;
          final y = min.y;
          return [
            Vector3(x0, y, z0) + lift,
            Vector3(x0 + s, y, z0) + lift,
            Vector3(x0 + s, y, z0 + s) + lift,
            Vector3(x0, y, z0 + s) + lift,
          ];
        }
      case VolumeFace.posX:
        {
          final z0 = min.z + u * s;
          final y0 = min.y + v * s;
          final x = max.x;
          return [
            Vector3(x, y0, z0) + lift,
            Vector3(x, y0 + s, z0) + lift,
            Vector3(x, y0 + s, z0 + s) + lift,
            Vector3(x, y0, z0 + s) + lift,
          ];
        }
      case VolumeFace.negX:
        {
          final z0 = min.z + u * s;
          final y0 = min.y + v * s;
          final x = min.x;
          return [
            Vector3(x, y0, z0) + lift,
            Vector3(x, y0, z0 + s) + lift,
            Vector3(x, y0 + s, z0 + s) + lift,
            Vector3(x, y0 + s, z0) + lift,
          ];
        }
      case VolumeFace.posZ:
        {
          final x0 = min.x + u * s;
          final y0 = min.y + v * s;
          final z = max.z;
          return [
            Vector3(x0, y0, z) + lift,
            Vector3(x0 + s, y0, z) + lift,
            Vector3(x0 + s, y0 + s, z) + lift,
            Vector3(x0, y0 + s, z) + lift,
          ];
        }
      case VolumeFace.negZ:
        {
          final x0 = min.x + u * s;
          final y0 = min.y + v * s;
          final z = min.z;
          return [
            Vector3(x0, y0, z) + lift,
            Vector3(x0, y0 + s, z) + lift,
            Vector3(x0 + s, y0 + s, z) + lift,
            Vector3(x0 + s, y0, z) + lift,
          ];
        }
    }
  }

  FaceCanvas canvasFor({
    required int volumeId,
    required VolumeCell cell,
    required VolumeFace face,
  }) {
    final key = FacePaintKey(
      volumeId: volumeId,
      tx: cell.tx,
      ty: cell.ty,
      face: face,
    );
    final (w, h) = faceSize(cell.box, face);
    final existing = _canvases[key];
    if (existing == null) {
      final created = FaceCanvas(width: w, height: h);
      _stampDoorVoids(created, cell, face);
      _canvases[key] = created;
      return created;
    }
    if (existing.width != w || existing.height != h) {
      final resized = existing.resized(w, h);
      _stampDoorVoids(resized, cell, face);
      _canvases[key] = resized;
      return resized;
    }
    _stampDoorVoids(existing, cell, face);
    return existing;
  }

  static void _stampDoorVoids(
    FaceCanvas canvas,
    VolumeCell cell,
    VolumeFace face,
  ) {
    for (var i = 0; i < canvas.cells.length; i++) {
      if (canvas.cells[i] == FaceCanvas.kVoid) {
        canvas.cells[i] = FaceCanvas.kEmpty;
      }
    }
    for (final side in cell.accessibleSides) {
      if (side.volumeFace != face) continue;
      final door = volumeDoorForSide(
        cell.box,
        side,
        originU: cell.doorOrigins[side],
      );
      if (door == null) continue;
      for (var v = door.originY; v < door.originY + door.height; v++) {
        for (var u = door.originU; u < door.originU + door.width; u++) {
          if (!canvas.inBounds(u, v)) continue;
          canvas.cells[canvas.index(u, v)] = FaceCanvas.kVoid;
        }
      }
    }
  }

  /// Move paint keys from [fromId] onto [toId] after a volume merge.
  void rekeyVolume(int fromId, int toId) {
    if (fromId == toId) return;
    final next = <FacePaintKey, FaceCanvas>{};
    for (final entry in _canvases.entries) {
      if (entry.key.volumeId != fromId) {
        next[entry.key] = entry.value;
        continue;
      }
      next[FacePaintKey(
        volumeId: toId,
        tx: entry.key.tx,
        ty: entry.key.ty,
        face: entry.key.face,
      )] = entry.value;
    }
    _canvases
      ..clear()
      ..addAll(next);
  }

  /// Move paint keys for [volumeId] by [dtx],[dty] after a volume translate.
  void remapVolumeTiles(int volumeId, int dtx, int dty) {
    if (dtx == 0 && dty == 0) return;
    final next = <FacePaintKey, FaceCanvas>{};
    for (final entry in _canvases.entries) {
      if (entry.key.volumeId != volumeId) {
        next[entry.key] = entry.value;
        continue;
      }
      next[FacePaintKey(
        volumeId: volumeId,
        tx: entry.key.tx + dtx,
        ty: entry.key.ty + dty,
        face: entry.key.face,
      )] = entry.value;
    }
    _canvases
      ..clear()
      ..addAll(next);
  }

  void prune(VolumeStore store) {
    _canvases.removeWhere((key, _) {
      Volume? volume;
      for (final v in store.visibleVolumes) {
        if (v.id == key.volumeId) {
          volume = v;
          break;
        }
      }
      if (volume == null) return true;
      return volume.cellAt(key.tx, key.ty) == null;
    });
  }

  FacePaintStore copy() {
    final next = FacePaintStore();
    for (final entry in _canvases.entries) {
      next._canvases[entry.key] = entry.value.copy();
    }
    return next;
  }

  factory FacePaintStore.fromCanvases(Map<FacePaintKey, FaceCanvas> canvases) {
    final next = FacePaintStore();
    for (final entry in canvases.entries) {
      next._canvases[entry.key] = entry.value.copy();
    }
    return next;
  }

  void restoreFrom(FacePaintStore other) {
    _canvases
      ..clear()
      ..addAll({
        for (final entry in other._canvases.entries) entry.key: entry.value.copy(),
      });
  }
}
