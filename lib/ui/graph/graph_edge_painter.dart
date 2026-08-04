import 'package:flutter/material.dart';

import 'graph_data.dart';
import 'graph_theme.dart';

class GraphEdgePainter extends CustomPainter {
  const GraphEdgePainter({
    required this.edges,
    required this.positions,
    required this.colorForNode,
    required this.theme,
    this.dimmedNodeIds = const {},
  });

  final List<GraphEdgeData> edges;
  final Map<String, Offset> positions;
  final Color Function(String nodeId) colorForNode;
  final GraphViewTheme theme;
  final Set<String> dimmedNodeIds;

  @override
  void paint(Canvas canvas, Size size) {
    for (final edge in edges) {
      final sourcePos = positions[edge.sourceId];
      final targetPos = positions[edge.targetId];
      if (sourcePos == null || targetPos == null) continue;

      final start = Offset(
        sourcePos.dx + theme.nodeWidth,
        sourcePos.dy + theme.nodeHeight * 0.5,
      );
      final end = Offset(
        targetPos.dx,
        targetPos.dy + theme.nodeHeight * 0.5,
      );
      final dx = (end.dx - start.dx).abs();
      final control = dx * 0.45;
      final c1 = Offset(start.dx + control, start.dy);
      final c2 = Offset(end.dx - control, end.dy);

      final path = Path()
        ..moveTo(start.dx, start.dy)
        ..cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, end.dx, end.dy);

      final baseColor = colorForNode(edge.sourceId);
      final isDimmed = dimmedNodeIds.contains(edge.sourceId) &&
          dimmedNodeIds.contains(edge.targetId);
      final alpha = isDimmed ? 0.2 : 0.78;
      final paint = Paint()
        ..color = baseColor.withValues(alpha: alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = edge.amount > 1 ? 2.6 : 1.8;
      canvas.drawPath(path, paint);

      const arrowLength = 8.0;
      final dir = end - c2;
      final norm =
          dir.distance == 0 ? const Offset(1, 0) : dir / dir.distance;
      final normal = Offset(-norm.dy, norm.dx);
      final p1 = end - norm * arrowLength + normal * 4.2;
      final p2 = end - norm * arrowLength - normal * 4.2;
      final arrow = Path()
        ..moveTo(end.dx, end.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close();
      final arrowPaint = Paint()
        ..color = baseColor.withValues(alpha: isDimmed ? 0.2 : 0.9);
      canvas.drawPath(arrow, arrowPaint);
    }
  }

  @override
  bool shouldRepaint(covariant GraphEdgePainter oldDelegate) {
    return oldDelegate.edges != edges ||
        oldDelegate.positions != positions ||
        oldDelegate.dimmedNodeIds != dimmedNodeIds;
  }
}
