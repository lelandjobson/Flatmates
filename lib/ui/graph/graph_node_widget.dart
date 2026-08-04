import 'package:flutter/material.dart';

import 'graph_data.dart';
import 'graph_theme.dart';

class GraphNodeWidget extends StatelessWidget {
  const GraphNodeWidget({
    super.key,
    required this.node,
    required this.theme,
    this.quantity = 1,
    this.isSelected = false,
    this.isDimmed = false,
    this.iconBuilder,
  });

  final GraphNodeData node;
  final GraphViewTheme theme;
  final int quantity;
  final bool isSelected;
  final bool isDimmed;
  final Widget Function(GraphNodeData node, double size)? iconBuilder;

  @override
  Widget build(BuildContext context) {
    final color = node.color ?? theme.edgeFallbackColor;
    final isLeaf = !node.hasChildren;

    final bodyColor = isLeaf ? theme.nodeLeafBody : theme.nodeExpandableBody;
    final borderColor = isSelected
        ? theme.selectedBorder
        : isLeaf
            ? theme.nodeLeafBorder
            : color.withValues(alpha: 0.65);
    final borderWidth =
        isSelected ? theme.selectedBorderWidth : theme.defaultBorderWidth;

    return AnimatedOpacity(
      opacity: isDimmed ? theme.dimmedOpacity : 1.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      child: Container(
        decoration: BoxDecoration(
          color: bodyColor,
          borderRadius: BorderRadius.circular(theme.borderRadius),
          border: Border.all(color: borderColor, width: borderWidth),
          boxShadow: [
            BoxShadow(
              color: theme.nodeShadowColor,
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 44,
              child: iconBuilder != null
                  ? iconBuilder!(node, 44)
                  : _DefaultNodeIcon(color: color, theme: theme),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    node.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: theme.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                    ),
                  ),
                  if (node.category != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      node.category!,
                      style: TextStyle(
                        color: color.withValues(alpha: 0.9),
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (quantity > 1)
              Container(
                margin: const EdgeInsets.only(left: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  'x$quantity',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DefaultNodeIcon extends StatelessWidget {
  const _DefaultNodeIcon({
    required this.color,
    required this.theme,
  });

  final Color color;
  final GraphViewTheme theme;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.7)),
      ),
      child: Icon(Icons.category, color: theme.textSecondary, size: 20),
    );
  }
}
