import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/friends/friend_instance_store.dart';
import '../../gameplay/friends/friend_mesh_sync.dart';
import '../../gameplay/picking/selectable.dart';
import '../../gameplay/viewers/world_plane.dart';
import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_solid.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../gameplay/walls/wall_edge.dart';
import '../../gameplay/walls/wall_mesh.dart';
import '../../gameplay/walls/wall_store.dart';
import '../../rendering/scene/camera.dart';
import 'selection_highlight_style.dart';

/// Stored cells the overlay should draw for a volume hit.
List<VolumeCell> volumeCellsForHighlight(
  SelectableHit target,
  Volume volume, {
  required bool cellOnly,
}) {
  if (!cellOnly) return volume.cells;
  final cell = target.cell ??
      (target.tx != null && target.ty != null
          ? volume.cellAt(target.tx!, target.ty!)
          : null);
  return cell == null ? const [] : [cell];
}

/// Fades a fill + thick outline over the hovered or selected map entity.
class SelectionHighlightOverlay extends StatefulWidget {
  const SelectionHighlightOverlay({
    super.key,
    required this.hit,
    required this.volumes,
    required this.friends,
    required this.camera,
    required this.viewport,
    this.extraHits = const [],
    this.wallEdges = const [],
    this.style = SelectionHighlightStyle.standard,
    this.listenable,
    this.tileSize = 8,
    this.cellOnly = false,
  });

  final SelectableHit? hit;
  final List<SelectableHit> extraHits;
  final List<WallEdge> wallEdges;
  final VolumeStore volumes;
  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final SelectionHighlightStyle style;
  final Listenable? listenable;
  final double tileSize;

  /// When true, a volume hit draws only its stored cell, not the joined solid.
  final bool cellOnly;

  @override
  State<SelectionHighlightOverlay> createState() =>
      _SelectionHighlightOverlayState();
}

class _SelectionHighlightOverlayState extends State<SelectionHighlightOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade;
  SelectableHit? _shown;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: widget.style.fadeDuration,
    );
    _shown = widget.hit;
    if (_hasTarget) _fade.value = 1;
  }

  bool get _hasTarget =>
      widget.hit != null ||
      widget.extraHits.isNotEmpty ||
      widget.wallEdges.isNotEmpty;

  @override
  void didUpdateWidget(covariant SelectionHighlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    _fade.duration = widget.style.fadeDuration;
    if (!(widget.hit?.sameAs(_shown) ?? _shown == null) ||
        widget.extraHits.length != oldWidget.extraHits.length ||
        widget.wallEdges.length != oldWidget.wallEdges.length) {
      _shown = widget.hit;
      if (!_hasTarget) {
        _fade.reverse();
      } else {
        _fade.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final listenable = widget.listenable;
    if (listenable == null) return _layer();
    return ListenableBuilder(listenable: listenable, builder: (_, _) => _layer());
  }

  Widget _layer() {
    return FadeTransition(
      opacity: _fade,
      child: IgnorePointer(
        child: CustomPaint(
          size: widget.viewport,
          painter: _HighlightPainter(
            hit: _shown ?? widget.hit,
            extraHits: widget.extraHits,
            wallEdges: widget.wallEdges,
            volumes: widget.volumes,
            friends: widget.friends,
            camera: widget.camera,
            viewport: widget.viewport,
            style: widget.style,
            tileSize: widget.tileSize,
            cellOnly: widget.cellOnly,
          ),
        ),
      ),
    );
  }
}

class _HighlightPainter extends CustomPainter {
  _HighlightPainter({
    required this.hit,
    required this.extraHits,
    required this.wallEdges,
    required this.volumes,
    required this.friends,
    required this.camera,
    required this.viewport,
    required this.style,
    required this.tileSize,
    required this.cellOnly,
  });

  final SelectableHit? hit;
  final List<SelectableHit> extraHits;
  final List<WallEdge> wallEdges;
  final VolumeStore volumes;
  final FriendInstanceStore friends;
  final Camera camera;
  final Size viewport;
  final SelectionHighlightStyle style;
  final double tileSize;
  final bool cellOnly;

  @override
  void paint(Canvas canvas, Size size) {
    final targets = <SelectableHit>[
      if (hit != null) hit!,
      ...extraHits,
    ];
    if (targets.isEmpty && wallEdges.isEmpty) return;
    final fill = Paint()
      ..color = style.fill
      ..style = PaintingStyle.fill;
    final stroke = Paint()
      ..color = style.outline
      ..style = PaintingStyle.stroke
      ..strokeWidth = style.outlineWidth
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    for (final target in targets) {
      for (final quad in _quadsFor(target)) {
        final path = _projectQuad(quad);
        if (path == null) continue;
        canvas.drawPath(path, fill);
        canvas.drawPath(path, stroke);
      }
    }
    for (final edge in wallEdges) {
      final path = _projectQuad(_wallQuad(edge));
      if (path == null) continue;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
  }

  List<Vector3> _wallQuad(WallEdge edge) {
    final dummy = WallStore(grid: volumes.grid);
    final a = dummy.vertexWorld(edge.x0, edge.y0);
    final b = dummy.vertexWorld(edge.x1, edge.y1);
    return [
      Vector3(a.x, 0, a.z),
      Vector3(b.x, 0, b.z),
      Vector3(b.x, kFenceHeight, b.z),
      Vector3(a.x, kFenceHeight, a.z),
    ];
  }

  Path? _projectQuad(List<Vector3> world) {
    if (world.length < 3) return null;
    final path = Path();
    var started = false;
    for (final p in world) {
      final s = camera.projectToScreen(p, viewport);
      if (s == null) return null;
      if (!started) {
        path.moveTo(s.dx, s.dy);
        started = true;
      } else {
        path.lineTo(s.dx, s.dy);
      }
    }
    path.close();
    return path;
  }

  List<List<Vector3>> _quadsFor(SelectableHit target) {
    switch (target.kind) {
      case SelectableKind.tile:
      case SelectableKind.path:
        final tx = target.tx;
        final ty = target.ty;
        if (tx == null || ty == null) return const [];
        return [_tileQuad(volumes.grid, tx, ty)];
      case SelectableKind.region:
        final region = target.region;
        if (region == null) return const [];
        return [
          for (final tile in region.tiles)
            _tileQuad(volumes.grid, tile.$1, tile.$2),
        ];
      case SelectableKind.friend:
        final instance = target.friendId == null
            ? null
            : friends.byId(target.friendId!);
        if (instance == null) return const [];
        final half = FriendMeshLayout.halfSize(tileSize: tileSize);
        final p = instance.position;
        return _boxQuads(p - Vector3(half, half, half), p + Vector3(half, half, half));
      case SelectableKind.volume:
        return _volumeQuads(target, cellOnly: cellOnly);
      case SelectableKind.volumeFace:
        if (cellOnly) return _volumeQuads(target, cellOnly: true);
        final cell = target.cell;
        final face = target.face;
        final volume = target.volumeId == null
            ? null
            : volumes.volumeById(target.volumeId!);
        if (cell == null || face == null || volume == null) return const [];
        return resolveVolumeSolid(volume, volumes.grid).faceWorldQuads(
          cell: cell,
          face: face,
          grid: volumes.grid,
        );
    }
  }

  List<List<Vector3>> _volumeQuads(
    SelectableHit target, {
    required bool cellOnly,
  }) {
    final volume = target.volumeId == null
        ? null
        : volumes.volumeById(target.volumeId!);
    if (volume == null) return const [];
    final cells = volumeCellsForHighlight(
      target,
      volume,
      cellOnly: cellOnly,
    );
    final solid = resolveVolumeSolid(volume, volumes.grid);
    return [
      for (final cell in cells)
        for (final face in VolumeFace.values)
          ...solid.faceWorldQuads(
            cell: cell,
            face: face,
            grid: volumes.grid,
          ),
    ];
  }

  List<Vector3> _tileQuad(VolumeGrid grid, int tx, int ty) {
    final origin = grid.tileOrigin(tx, ty);
    final s = grid.tileSize;
    const y = 0.04;
    return [
      Vector3(origin.x, y, origin.z),
      Vector3(origin.x + s, y, origin.z),
      Vector3(origin.x + s, y, origin.z + s),
      Vector3(origin.x, y, origin.z + s),
    ];
  }

  List<List<Vector3>> _boxQuads(Vector3 min, Vector3 max) {
    return [
      _faceQuad(VolumeFace.negY, min, max),
      _faceQuad(VolumeFace.posY, min, max),
      _faceQuad(VolumeFace.negX, min, max),
      _faceQuad(VolumeFace.posX, min, max),
      _faceQuad(VolumeFace.negZ, min, max),
      _faceQuad(VolumeFace.posZ, min, max),
    ];
  }

  List<Vector3> _faceQuad(VolumeFace face, Vector3 min, Vector3 max) {
    return switch (face) {
      VolumeFace.posX => [
          Vector3(max.x, min.y, min.z),
          Vector3(max.x, max.y, min.z),
          Vector3(max.x, max.y, max.z),
          Vector3(max.x, min.y, max.z),
        ],
      VolumeFace.negX => [
          Vector3(min.x, min.y, min.z),
          Vector3(min.x, min.y, max.z),
          Vector3(min.x, max.y, max.z),
          Vector3(min.x, max.y, min.z),
        ],
      VolumeFace.posY => [
          Vector3(min.x, max.y, min.z),
          Vector3(max.x, max.y, min.z),
          Vector3(max.x, max.y, max.z),
          Vector3(min.x, max.y, max.z),
        ],
      VolumeFace.negY => [
          Vector3(min.x, min.y, min.z),
          Vector3(min.x, min.y, max.z),
          Vector3(max.x, min.y, max.z),
          Vector3(max.x, min.y, min.z),
        ],
      VolumeFace.posZ => [
          Vector3(min.x, min.y, max.z),
          Vector3(max.x, min.y, max.z),
          Vector3(max.x, max.y, max.z),
          Vector3(min.x, max.y, max.z),
        ],
      VolumeFace.negZ => [
          Vector3(min.x, min.y, min.z),
          Vector3(min.x, max.y, min.z),
          Vector3(max.x, max.y, min.z),
          Vector3(max.x, min.y, min.z),
        ],
    };
  }

  @override
  bool shouldRepaint(covariant _HighlightPainter oldDelegate) => true;
}
