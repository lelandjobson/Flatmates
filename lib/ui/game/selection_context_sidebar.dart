import 'package:flutter/material.dart';

import '../../gameplay/picking/selection_actions.dart';

/// Left-hand action strip for the current selection.
class SelectionContextSidebar extends StatelessWidget {
  const SelectionContextSidebar({
    super.key,
    required this.title,
    required this.actions,
    required this.onAction,
  });

  final String title;
  final List<SelectionActionSpec> actions;
  final ValueChanged<SelectionActionId> onAction;

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox.shrink();
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          for (final action in actions)
            Tooltip(
              message: action.label,
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onAction(action.id),
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(action.icon, color: Colors.white, size: 20),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
