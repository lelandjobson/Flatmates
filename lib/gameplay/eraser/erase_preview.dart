import '../paths/path_store.dart';
import '../picking/selectable.dart';
import '../volumes/volume_store.dart';
import '../walls/wall_edge.dart';
import '../walls/wall_store.dart';
import 'eraser_filter.dart';

/// What a delete-tool click would remove under the current filter.
class ErasePreview {
  const ErasePreview({
    this.hits = const [],
    this.walls = const [],
  });

  final List<SelectableHit> hits;
  final List<WallEdge> walls;

  bool get isEmpty => hits.isEmpty && walls.isEmpty;
}

ErasePreview erasePreviewAt({
  required int tx,
  required int ty,
  required EraserFilter filter,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
  SelectableHit? primary,
}) {
  if (filter.eraseAllOnTile) {
    return _allOnTile(
      tx: tx,
      ty: ty,
      filter: filter,
      volumes: volumes,
      paths: paths,
      walls: walls,
    );
  }
  return _primaryOnly(
    tx: tx,
    ty: ty,
    filter: filter,
    volumes: volumes,
    paths: paths,
    walls: walls,
    primary: primary,
  );
}

ErasePreview _allOnTile({
  required int tx,
  required int ty,
  required EraserFilter filter,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
}) {
  final hits = <SelectableHit>[];
  if (filter.volumes) {
    final volume = volumes.volumeAt(tx, ty);
    if (volume != null) {
      hits.add(SelectableHit.volume(volume.id, cell: volume.cellAt(tx, ty)));
    }
  }
  if (filter.paths && paths.contains(tx, ty)) {
    hits.add(SelectableHit.path(tx, ty));
  }
  return ErasePreview(
    hits: hits,
    walls: filter.walls ? walls.edgesTouchingTile(tx, ty) : const [],
  );
}

ErasePreview _primaryOnly({
  required int tx,
  required int ty,
  required EraserFilter filter,
  required VolumeStore volumes,
  required PathStore paths,
  required WallStore walls,
  SelectableHit? primary,
}) {
  if (primary != null) {
    switch (primary.kind) {
      case SelectableKind.volume:
      case SelectableKind.volumeFace:
        if (filter.volumes && primary.volumeId != null) {
          return ErasePreview(hits: [primary]);
        }
      case SelectableKind.path:
        if (filter.paths) return ErasePreview(hits: [primary]);
      case SelectableKind.region:
      case SelectableKind.tile:
      case SelectableKind.friend:
        break;
    }
  }
  if (filter.volumes) {
    final volume = volumes.volumeAt(tx, ty);
    if (volume != null) {
      return ErasePreview(
        hits: [SelectableHit.volume(volume.id, cell: volume.cellAt(tx, ty))],
      );
    }
  }
  if (filter.paths && paths.contains(tx, ty)) {
    return ErasePreview(hits: [SelectableHit.path(tx, ty)]);
  }
  if (filter.walls) {
    final edges = walls.edgesTouchingTile(tx, ty);
    if (edges.isNotEmpty) return ErasePreview(walls: edges);
  }
  return const ErasePreview();
}
