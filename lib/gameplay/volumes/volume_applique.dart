import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../paint/face_paint_store.dart';
import '../viewers/world_plane.dart';
import 'volume.dart';
import 'volume_door.dart';

/// Door paper matches volume / path cardstock.
const Color kDoorAppliqueColor = Color(0xFFF4EFE6);

/// Kind of paper layered on a volume face. Doors are the first.
enum VolumeAppliqueKind { door }

/// Paper piece on a volume face. Layer 0 sits just above the volume itself.
class VolumeApplique {
  const VolumeApplique({
    required this.id,
    required this.volumeId,
    required this.tx,
    required this.ty,
    required this.face,
    required this.layer,
    required this.originU,
    required this.originV,
    required this.width,
    required this.height,
    required this.kind,
    required this.color,
    this.side,
  });

  final int id;
  final int volumeId;
  final int tx;
  final int ty;
  final VolumeFace face;
  final int layer;
  final int originU;
  final int originV;
  final int width;
  final int height;
  final VolumeAppliqueKind kind;
  final Color color;
  final VolumeSide? side;

  FacePaintKey get faceKey => FacePaintKey(
        volumeId: volumeId,
        tx: tx,
        ty: ty,
        face: face,
      );

  bool overlapsRect(int u0, int v0, int u1, int v1) {
    return originU < u1 &&
        originU + width > u0 &&
        originV < v1 &&
        originV + height > v0;
  }

  VolumeApplique copyWith({
    int? layer,
    int? originU,
    int? originV,
    int? width,
    int? height,
    Color? color,
  }) {
    return VolumeApplique(
      id: id,
      volumeId: volumeId,
      tx: tx,
      ty: ty,
      face: face,
      layer: layer ?? this.layer,
      originU: originU ?? this.originU,
      originV: originV ?? this.originV,
      width: width ?? this.width,
      height: height ?? this.height,
      kind: kind,
      color: color ?? this.color,
      side: side,
    );
  }
}

/// Appliques keyed by face, with a per-subtile max-layer grid for sampling.
class VolumeAppliqueStore {
  final List<VolumeApplique> items = [];
  final Map<FacePaintKey, Int16List> _maxLayer = {};
  final Map<FacePaintKey, (int width, int height)> _faceSize = {};
  int _nextId = 1;

  void clear() {
    items.clear();
    _maxLayer.clear();
    _faceSize.clear();
    _nextId = 1;
  }

  Iterable<VolumeApplique> onFace(FacePaintKey key) =>
      items.where((item) => item.faceKey == key);

  VolumeApplique? doorOn({
    required int volumeId,
    required int tx,
    required int ty,
    required VolumeSide side,
  }) {
    for (final item in items) {
      if (item.kind == VolumeAppliqueKind.door &&
          item.volumeId == volumeId &&
          item.tx == tx &&
          item.ty == ty &&
          item.side == side) {
        return item;
      }
    }
    return null;
  }

  /// Highest applique layer in [originU, originU+width) × [originV, originV+height).
  ///
  /// Returns `-1` when the volume face is bare (so the next paper is layer 0).
  int maxLayerInRect({
    required int volumeId,
    required int tx,
    required int ty,
    required VolumeFace face,
    required int originU,
    required int originV,
    required int width,
    required int height,
    int? ignoreId,
  }) {
    final u1 = originU + width;
    final v1 = originV + height;
    if (ignoreId != null) {
      var maxLayer = -1;
      for (final item in items) {
        if (item.id == ignoreId) continue;
        if (item.volumeId != volumeId ||
            item.tx != tx ||
            item.ty != ty ||
            item.face != face) {
          continue;
        }
        if (!item.overlapsRect(originU, originV, u1, v1)) continue;
        if (item.layer > maxLayer) maxLayer = item.layer;
      }
      return maxLayer;
    }
    final key = FacePaintKey(volumeId: volumeId, tx: tx, ty: ty, face: face);
    final grid = _maxLayer[key];
    final size = _faceSize[key];
    if (grid == null || size == null) return -1;
    final (fw, fh) = size;
    var maxLayer = -1;
    final x0 = originU.clamp(0, fw);
    final y0 = originV.clamp(0, fh);
    final x1 = u1.clamp(0, fw);
    final y1 = v1.clamp(0, fh);
    for (var v = y0; v < y1; v++) {
      final row = v * fw;
      for (var u = x0; u < x1; u++) {
        final layer = grid[row + u];
        if (layer > maxLayer) maxLayer = layer;
      }
    }
    return maxLayer;
  }

  int nextLayerAbove({
    required VolumeCell cell,
    required int volumeId,
    required VolumeFace face,
    required int originU,
    required int originV,
    required int width,
    required int height,
    int? ignoreId,
  }) {
    return maxLayerInRect(
          volumeId: volumeId,
          tx: cell.tx,
          ty: cell.ty,
          face: face,
          originU: originU,
          originV: originV,
          width: width,
          height: height,
          ignoreId: ignoreId,
        ) +
        1;
  }

  VolumeApplique add(VolumeApplique draft) {
    final item = VolumeApplique(
      id: draft.id > 0 ? draft.id : _nextId++,
      volumeId: draft.volumeId,
      tx: draft.tx,
      ty: draft.ty,
      face: draft.face,
      layer: draft.layer,
      originU: draft.originU,
      originV: draft.originV,
      width: draft.width,
      height: draft.height,
      kind: draft.kind,
      color: draft.color,
      side: draft.side,
    );
    if (item.id >= _nextId) _nextId = item.id + 1;
    items.add(item);
    _rebuildFace(item.faceKey, item.width, item.height);
    return item;
  }

  bool removeId(int id) {
    final index = items.indexWhere((item) => item.id == id);
    if (index < 0) return false;
    final removed = items.removeAt(index);
    _rebuildFace(removed.faceKey, removed.width, removed.height);
    return true;
  }

  bool removeDoor({
    required int volumeId,
    required int tx,
    required int ty,
    required VolumeSide side,
  }) {
    final existing = doorOn(volumeId: volumeId, tx: tx, ty: ty, side: side);
    if (existing == null) return false;
    return removeId(existing.id);
  }

  /// Create or move a door paper so it sits one layer above whatever it covers.
  VolumeApplique placeOrMoveDoor({
    required Volume volume,
    required VolumeCell cell,
    required VolumeSide side,
    required VolumeDoor door,
    Color? color,
  }) {
    final existing = doorOn(
      volumeId: volume.id,
      tx: cell.tx,
      ty: cell.ty,
      side: side,
    );
    final layer = nextLayerAbove(
      cell: cell,
      volumeId: volume.id,
      face: door.face,
      originU: door.originU,
      originV: door.originY,
      width: door.width,
      height: door.height,
      ignoreId: existing?.id,
    );
    if (existing != null) {
      final next = existing.copyWith(
        layer: layer,
        originU: door.originU,
        originV: door.originY,
        width: door.width,
        height: door.height,
        color: color ?? kDoorAppliqueColor,
      );
      final index = items.indexWhere((item) => item.id == existing.id);
      items[index] = next;
      _rebuildFace(next.faceKey, next.width, next.height);
      return next;
    }
    return add(
      VolumeApplique(
        id: 0,
        volumeId: volume.id,
        tx: cell.tx,
        ty: cell.ty,
        face: door.face,
        layer: layer,
        originU: door.originU,
        originV: door.originY,
        width: door.width,
        height: door.height,
        kind: VolumeAppliqueKind.door,
        color: color ?? kDoorAppliqueColor,
        side: side,
      ),
    );
  }

  void _rebuildFace(FacePaintKey key, int minWidth, int minHeight) {
    var width = math.max(minWidth, 1);
    var height = math.max(minHeight, 1);
    for (final item in onFace(key)) {
      width = math.max(width, item.originU + item.width);
      height = math.max(height, item.originV + item.height);
    }
    final grid = Int16List(width * height);
    for (var i = 0; i < grid.length; i++) {
      grid[i] = -1;
    }
    var any = false;
    for (final item in onFace(key)) {
      any = true;
      for (var v = 0; v < item.height; v++) {
        final y = item.originV + v;
        if (y < 0 || y >= height) continue;
        for (var u = 0; u < item.width; u++) {
          final x = item.originU + u;
          if (x < 0 || x >= width) continue;
          final i = y * width + x;
          if (item.layer > grid[i]) grid[i] = item.layer;
        }
      }
    }
    if (!any) {
      _maxLayer.remove(key);
      _faceSize.remove(key);
      return;
    }
    _maxLayer[key] = grid;
    _faceSize[key] = (width, height);
  }
}

/// World quad of an applique, CCW from outside. Doors reuse [doorWorldCorners].
List<Vector3> appliqueWorldCorners({
  required VolumeGrid grid,
  required VolumeCell cell,
  required VolumeApplique piece,
}) {
  if (piece.kind == VolumeAppliqueKind.door && piece.side != null) {
    final door = VolumeDoor(
      side: piece.side!,
      originU: piece.originU,
      originY: piece.originV,
      width: piece.width,
      height: piece.height,
    );
    return doorWorldCorners(
      grid: grid,
      tx: cell.tx,
      ty: cell.ty,
      box: cell.box,
      door: door,
    );
  }
  final min = cell.box.worldMin(grid, cell.tx, cell.ty);
  final max = cell.box.worldMax(grid, cell.tx, cell.ty);
  final s = grid.subtileSize;
  final u0 = piece.originU * s;
  final u1 = (piece.originU + piece.width) * s;
  final v0 = piece.originV * s;
  final v1 = (piece.originV + piece.height) * s;
  return switch (piece.face) {
    VolumeFace.posX => [
        Vector3(max.x, min.y + v0, min.z + u0),
        Vector3(max.x, min.y + v0, min.z + u1),
        Vector3(max.x, min.y + v1, min.z + u1),
        Vector3(max.x, min.y + v1, min.z + u0),
      ],
    VolumeFace.negX => [
        Vector3(min.x, min.y + v0, min.z + u1),
        Vector3(min.x, min.y + v0, min.z + u0),
        Vector3(min.x, min.y + v1, min.z + u0),
        Vector3(min.x, min.y + v1, min.z + u1),
      ],
    VolumeFace.posZ => [
        Vector3(min.x + u1, min.y + v0, max.z),
        Vector3(min.x + u0, min.y + v0, max.z),
        Vector3(min.x + u0, min.y + v1, max.z),
        Vector3(min.x + u1, min.y + v1, max.z),
      ],
    VolumeFace.negZ => [
        Vector3(min.x + u0, min.y + v0, min.z),
        Vector3(min.x + u1, min.y + v0, min.z),
        Vector3(min.x + u1, min.y + v1, min.z),
        Vector3(min.x + u0, min.y + v1, min.z),
      ],
    VolumeFace.posY => [
        Vector3(min.x + u0, max.y, min.z + v0),
        Vector3(min.x + u1, max.y, min.z + v0),
        Vector3(min.x + u1, max.y, min.z + v1),
        Vector3(min.x + u0, max.y, min.z + v1),
      ],
    VolumeFace.negY => [
        Vector3(min.x + u0, min.y, min.z + v1),
        Vector3(min.x + u1, min.y, min.z + v1),
        Vector3(min.x + u1, min.y, min.z + v0),
        Vector3(min.x + u0, min.y, min.z + v0),
      ],
  };
}
