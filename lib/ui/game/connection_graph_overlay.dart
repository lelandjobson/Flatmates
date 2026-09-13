import 'package:flutter/material.dart';

import '../../gameplay/graph/connection_graph.dart';
import '../../gameplay/volumes/volume.dart';
import '../../rendering/scene/camera.dart';

const kJointInInColor = Color(0xFF40C4FF);
const kJointOutOutColor = Color(0xFFFFB74D);
const kNodeInsideColor = Color(0xFF40C4FF);
const kNodeOutsideColor = Color(0xFFFFB74D);
const kAnchorColor = Color(0xFF111111);

const _kEdgeStroke = 7.0;
const _kNodeDiameter = 16.0;

/// Projected thick edges and thicker node circles for a [ConnectionGraph].
class ConnectionGraphOverlay extends StatelessWidget {
  const ConnectionGraphOverlay({
    super.key,
    required this.graph,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.listenable,
    this.tileVisible,
  });

  final ConnectionGraph graph;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final Listenable? listenable;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  Widget build(BuildContext context) {
    final listenable = this.listenable;
    if (listenable != null) {
      return ListenableBuilder(
        listenable: listenable,
        builder: (context, _) => _paint(),
      );
    }
    return _paint();
  }

  Widget _paint() {
    if (graph.nodes.isEmpty && graph.edges.isEmpty) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: CustomPaint(
        size: viewport,
        painter: _ConnectionGraphPainter(
          graph: graph,
          grid: grid,
          camera: camera,
          viewport: viewport,
          tileVisible: tileVisible,
        ),
      ),
    );
  }
}

class _ConnectionGraphPainter extends CustomPainter {
  _ConnectionGraphPainter({
    required this.graph,
    required this.grid,
    required this.camera,
    required this.viewport,
    this.tileVisible,
  });

  final ConnectionGraph graph;
  final VolumeGrid grid;
  final Camera camera;
  final Size viewport;
  final bool Function(int tx, int ty)? tileVisible;

  @override
  void paint(Canvas canvas, Size size) {
    Offset? project(GraphNode node) =>
        camera.projectToScreen(node.worldPosition(grid), viewport);

    final visible = tileVisible;
    bool show(GraphNode n) => visible == null || visible(n.x, n.y);

    final anchorNodes = <GraphNode>{
      for (final anchor in graph.anchors) ...[anchor.inner, anchor.outer],
    };

    for (final edge in graph.edges) {
      if (!show(edge.a) || !show(edge.b)) continue;
      final a = project(edge.a);
      final b = project(edge.b);
      if (a == null || b == null) continue;
      final isAnchor = edge.kind == JointKind.inOut;
      final paint = Paint()
        ..color = switch (edge.kind) {
          JointKind.inIn => kJointInInColor,
          JointKind.inOut => kAnchorColor,
          JointKind.outOut => kJointOutOutColor,
        }
        ..strokeWidth = isAnchor ? _kEdgeStroke + 1 : _kEdgeStroke
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      canvas.drawLine(a, b, paint);
    }

    final r = _kNodeDiameter * 0.5;
    for (final node in graph.nodes) {
      if (!show(node)) continue;
      final p = project(node);
      if (p == null) continue;
      final anchored = anchorNodes.contains(node);
      final paint = Paint()
        ..color = anchored
            ? kAnchorColor
            : switch (node.kind) {
                NodeKind.inside || NodeKind.region => kNodeInsideColor,
                NodeKind.outside => kNodeOutsideColor,
              }
        ..style = PaintingStyle.fill;
      canvas.drawCircle(p, r, paint);
    }

    for (final anchor in graph.anchors) {
      if (!show(anchor.inner) || !show(anchor.outer)) continue;
      final a = project(anchor.inner);
      final b = project(anchor.outer);
      if (a == null || b == null) continue;
      _paintAnchorLabel(
        canvas,
        Offset((a.dx + b.dx) * 0.5, (a.dy + b.dy) * 0.5),
        'A',
      );
    }
  }

  void _paintAnchorLabel(Canvas canvas, Offset center, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: kAnchorColor,
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = center - Offset(painter.width * 0.5, painter.height + 8);
    final halo = Paint()
      ..color = const Color(0xE6FFFFFF)
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin.dx - 3,
          origin.dy - 1,
          painter.width + 6,
          painter.height + 2,
        ),
        const Radius.circular(3),
      ),
      halo,
    );
    painter.paint(canvas, origin);
  }

  @override
  bool shouldRepaint(covariant _ConnectionGraphPainter oldDelegate) =>
      oldDelegate.graph != graph ||
      oldDelegate.camera != camera ||
      oldDelegate.viewport != viewport;
}
