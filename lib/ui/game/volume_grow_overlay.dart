import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../gameplay/volumes/volume.dart';
import '../../gameplay/volumes/volume_store.dart';
import '../../rendering/scene/camera.dart';
import 'projected_world_anchor.dart';

const _kGrowIconSize = 32.0;

class VolumeGrowOverlay extends StatelessWidget {
  const VolumeGrowOverlay({
    super.key,
    required this.store,
    required this.camera,
    required this.viewport,
    required this.onGrow,
    this.blocked,
  });

  final VolumeStore store;
  final Camera camera;
  final Size viewport;
  final ValueChanged<VolumeGrowCandidate> onGrow;
  final bool Function(int tx, int ty)? blocked;

  @override
  Widget build(BuildContext context) {
    final candidates = store.growCandidates(blocked: blocked);
    if (candidates.isEmpty) return const SizedBox.shrink();

    final stems = <(Offset, Offset)>[];
    final buttons = <Widget>[];

    for (final c in candidates) {
      final from = c.source.box.sideFaceCenter(
        store.grid,
        c.source.tx,
        c.source.ty,
        c.side,
      );
      final emptyCenter = store.grid.tileCenter(c.tx, c.ty);
      // 30% from the occupied face toward the empty tile center (on the
      // empty tile), so the stem points outward and the tile stays clickable.
      final iconWorld = Vector3(
        from.x + (emptyCenter.x - from.x) * 0.3,
        from.y + (emptyCenter.y - from.y) * 0.3,
        from.z + (emptyCenter.z - from.z) * 0.3,
      );
      final start = camera.projectToScreen(from, viewport);
      final icon = camera.projectToScreen(iconWorld, viewport);
      if (start != null && icon != null) {
        stems.add((start, icon));
      }
      var rotation = 0.0;
      if (start != null && icon != null) {
        final delta = icon - start;
        if (delta.distanceSquared > 1e-4) {
          rotation = math.atan2(delta.dy, delta.dx);
        }
      }
      buttons.add(
        ProjectedWorldAnchor(
          camera: camera,
          viewport: viewport,
          world: iconWorld,
          size: const Size(_kGrowIconSize, _kGrowIconSize),
          rotation: rotation,
          child: _GrowPlusButton(onTap: () => onGrow(c)),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        IgnorePointer(
          child: CustomPaint(
            size: viewport,
            painter: _StemPainter(stems: stems),
          ),
        ),
        ...buttons,
      ],
    );
  }
}

class VolumeAccessOverlay extends StatelessWidget {
  const VolumeAccessOverlay({
    super.key,
    required this.store,
    required this.camera,
    required this.viewport,
    required this.onToggle,
  });

  final VolumeStore store;
  final Camera camera;
  final Size viewport;
  final ValueChanged<VolumeSide> onToggle;

  @override
  Widget build(BuildContext context) {
    final cell = store.draftCell;
    if (cell == null) return const SizedBox.shrink();

    return Stack(
      fit: StackFit.expand,
      children: [
        for (final side in VolumeSide.values)
          ProjectedWorldAnchor(
            camera: camera,
            viewport: viewport,
            world: cell.box.sideFaceCenter(store.grid, cell.tx, cell.ty, side),
            size: const Size(36, 36),
            child: _AccessFaceButton(
              selected: cell.accessibleSides.contains(side),
              onTap: () => onToggle(side),
            ),
          ),
      ],
    );
  }
}

class _StemPainter extends CustomPainter {
  _StemPainter({required this.stems});

  final List<(Offset, Offset)> stems;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    for (final (a, b) in stems) {
      canvas.drawLine(a, b, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StemPainter oldDelegate) =>
      oldDelegate.stems != stems;
}

class _GrowPlusButton extends StatelessWidget {
  const _GrowPlusButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.82),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const SizedBox(
          width: _kGrowIconSize,
          height: _kGrowIconSize,
          child: CustomPaint(painter: _OutwardPlusPainter()),
        ),
      ),
    );
  }
}

class _OutwardPlusPainter extends CustomPainter {
  const _OutwardPlusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.square;
    final c = Offset(size.width / 2, size.height / 2);
    final short = size.width * 0.18;
    final long = size.width * 0.32;
    canvas.drawLine(
      Offset(c.dx - short, c.dy),
      Offset(c.dx + long, c.dy),
      paint,
    );
    canvas.drawLine(
      Offset(c.dx, c.dy - short),
      Offset(c.dx, c.dy + short),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _AccessFaceButton extends StatelessWidget {
  const _AccessFaceButton({required this.selected, required this.onTap});

  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? const Color(0xFFE53935)
          : Colors.black.withValues(alpha: 0.75),
      shape: const CircleBorder(
        side: BorderSide(color: Colors.white70, width: 1.5),
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Icon(
          Icons.login,
          color: Colors.white,
          size: 18,
        ),
      ),
    );
  }
}
