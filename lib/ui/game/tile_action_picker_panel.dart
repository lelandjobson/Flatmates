import 'package:flutter/material.dart';

import '../../gameplay/flatmates/day_action.dart';
import 'game_tool_carousel.dart';

/// Collect / dye / dwell picker, with a back arrow to retake the tile.
class TileActionPickerPanel extends StatelessWidget {
  const TileActionPickerPanel({
    super.key,
    required this.onSelect,
    required this.onBack,
    this.selected,
    this.title = 'Action',
  });

  final ValueChanged<DayActionKind> onSelect;
  final VoidCallback onBack;
  final DayActionKind? selected;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.fromLTRB(6, 6, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 32, height: 32),
                onPressed: onBack,
                icon: const Icon(
                  Icons.arrow_back,
                  size: 18,
                  color: Colors.white70,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              padding: EdgeInsets.zero,
              children: [
                for (final kind in kProgrammableDayActions)
                  _ActionTile(
                    kind: kind,
                    selected: kind == selected,
                    onTap: () => onSelect(kind),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.kind,
    required this.selected,
    required this.onTap,
  });

  final DayActionKind kind;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fill = gameModeFill(GameMode.action, submenu: true);
    return Material(
      color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
          child: Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: fill,
                ),
                child: Icon(kind.icon, size: 14, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  kind.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}