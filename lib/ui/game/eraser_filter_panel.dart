import 'package:flutter/material.dart';

import '../../gameplay/eraser/eraser_filter.dart';

/// Delete-tool options: all features on a tile, with a filter caret.
class EraserFilterPanel extends StatefulWidget {
  const EraserFilterPanel({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final EraserFilter filter;
  final VoidCallback onChanged;

  @override
  State<EraserFilterPanel> createState() => _EraserFilterPanelState();
}

class _EraserFilterPanelState extends State<EraserFilterPanel> {
  bool _kindsOpen = false;

  EraserFilter get filter => widget.filter;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white10),
      ),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Erase',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          _FilterCheck(
            label: 'Erase all features on a tile',
            value: filter.eraseAllOnTile,
            onChanged: (v) {
              filter.eraseAllOnTile = v;
              widget.onChanged();
            },
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _kindsOpen = !_kindsOpen),
            child: SizedBox(
              height: 28,
              child: Row(
                children: [
                  Icon(
                    _kindsOpen ? Icons.expand_more : Icons.chevron_right,
                    color: Colors.white70,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Filter kinds',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          if (_kindsOpen) ...[
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Column(
                children: [
                  _FilterCheck(
                    label: 'Walls',
                    value: filter.walls,
                    onChanged: (v) {
                      filter.walls = v;
                      widget.onChanged();
                    },
                  ),
                  _FilterCheck(
                    label: 'Paths',
                    value: filter.paths,
                    onChanged: (v) {
                      filter.paths = v;
                      widget.onChanged();
                    },
                  ),
                  _FilterCheck(
                    label: 'Volumes',
                    value: filter.volumes,
                    onChanged: (v) {
                      filter.volumes = v;
                      widget.onChanged();
                    },
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _FilterCheck extends StatelessWidget {
  const _FilterCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      child: Row(
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              side: const BorderSide(color: Colors.white54),
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white.withValues(alpha: 0.85);
                }
                return Colors.transparent;
              }),
              checkColor: Colors.black,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}
