import 'package:flutter/material.dart';

import 'graph_theme.dart';

class GraphNodeMenu extends StatelessWidget {
  const GraphNodeMenu({
    super.key,
    required this.theme,
    required this.hasChildren,
    required this.isExpanded,
    required this.isFocusMode,
    this.onInfo,
    this.onToggleExpand,
  });

  final GraphViewTheme theme;
  final bool hasChildren;
  final bool isExpanded;
  final bool isFocusMode;
  final VoidCallback? onInfo;
  final VoidCallback? onToggleExpand;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: theme.menuBackground,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.menuBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MenuButton(
            icon: Icons.info_outline,
            theme: theme,
            onTap: onInfo,
            tooltip: 'Info',
          ),
          if (isFocusMode && hasChildren) ...[
            const SizedBox(width: 2),
            _MenuButton(
              icon: isExpanded ? Icons.remove : Icons.add,
              theme: theme,
              onTap: onToggleExpand,
              tooltip: isExpanded ? 'Collapse' : 'Expand',
            ),
          ],
        ],
      ),
    );
  }
}

class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.icon,
    required this.theme,
    this.onTap,
    this.tooltip,
  });

  final IconData icon;
  final GraphViewTheme theme;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          width: theme.menuButtonSize,
          height: theme.menuButtonSize,
          child: Icon(icon, color: theme.textSecondary, size: 18),
        ),
      ),
    );
    if (tooltip != null) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}
