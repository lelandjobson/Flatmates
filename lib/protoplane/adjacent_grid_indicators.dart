import 'package:flutter/material.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/scene.dart';
import 'controller.dart';
import 'focus_context.dart';
import 'models.dart';

class AdjacentGridIndicator {
  const AdjacentGridIndicator(this.plane, this.nodes);
  final CraftPlane plane;
  final List<Offset> nodes;
}

/// Use the same destinations as floor swipes, including exposed terrain at
/// different heights. Never display nodes over holes or depleted paper.
List<AdjacentGridIndicator> adjacentGridIndicators(ProtoplaneController model) {
  final active = model.activePlane;
  if (active == null || !isFloorOrientation(active)) return const [];
  final graph = model.navigationGraph;
  final source = graph.aliases[active.id] ?? active.id;
  final ids = {
    for (final edge in graph.swipeNeighbors[source] ?? []) edge.planeId,
  };
  final result = <AdjacentGridIndicator>[];
  for (final id in ids) {
    final plane = model.planes[id];
    if (plane == null ||
        id == source ||
        !isFloorOrientation(plane) ||
        plane.grids.isEmpty) {
      continue;
    }
    final regions = graph.availableRegions[id] ?? model.surfaceRegions(plane);
    result.add(
      AdjacentGridIndicator(plane, [
        for (final node in plane.grids.first.nodes)
          if (regions.any((r) => r.contains(node))) node,
      ]),
    );
  }
  return result;
}

/// Small, non-interactive navigation cues; active dots retain their own styling.
class AdjacentGridPainter extends CustomPainter {
  AdjacentGridPainter(
    this.model,
    this.camera,
    this.scene, {
    this.enabled = true,
    this.opacity = 1,
  }) : super(repaint: scene);

  final ProtoplaneController model;
  final Camera camera;
  final Scene scene;
  final bool enabled;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (!enabled || opacity <= 0) return;
    final meshes = {for (final mesh in scene.meshes) mesh.id: mesh};
    final white = Paint();
    final outline = Paint()..color = const Color(0xff181818);
    final occupied = <(int, int)>{};
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (final indicator in adjacentGridIndicators(model)) {
      final plane = indicator.plane;
      // Crafted floor surfaces are rendered by their owner mesh.
      final mesh = meshes[plane.id] ?? meshes[plane.owner];
      if (mesh == null || !mesh.visible || mesh.material.opacity <= 0) continue;
      final alpha = mesh.material.opacity.clamp(0.0, .55) * opacity;
      white.color = Colors.white.withValues(alpha: alpha);
      outline.color = const Color(0xff181818).withValues(alpha: alpha * .7);
      for (final local in indicator.nodes) {
        final world = plane.point(local, .008);
        if (mesh.cropBox != null &&
            !mesh.cropBox!.contains(plane.point(local))) {
          continue;
        }
        final screen = camera.projectToScreen(world, size);
        if (screen == null || !(Offset.zero & size).contains(screen)) continue;
        // Shared edges should not double the brightness of coincident nodes.
        if (!occupied.add((screen.dx.round(), screen.dy.round()))) continue;
        canvas.drawCircle(screen, 2, outline);
        canvas.drawCircle(screen, 1.25, white);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant AdjacentGridPainter oldDelegate) => true;
}
