import 'package:flutter/material.dart';

import '../../gameplay/eraser/eraser_filter.dart';

/// Checkboxes and radius slider for the map eraser. Separate from the tool strip.
class EraserFilterPanel extends StatelessWidget {
  const EraserFilterPanel({
    super.key,
    required this.filter,
    required this.onChanged,
  });

  final EraserFilter filter;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 176,
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
            label: 'Walls',
            value: filter.walls,
            onChanged: (v) {
              filter.walls = v;
              onChanged();
            },
          ),
          _FilterCheck(
            label: 'Paths',
            value: filter.paths,
            onChanged: (v) {
              filter.paths = v;
              onChanged();
            },
          ),
          _FilterCheck(
            label: 'Volumes',
            value: filter.volumes,
            onChanged: (v) {
              filter.volumes = v;
              onChanged();
            },
          ),
          const SizedBox(height: 6),
          Text(
            'Radius  ${filter.radiusTiles.toStringAsFixed(2)}',
            style: const TextStyle(color: Colors.white70, fontSize: 11),
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: Colors.white70,
              inactiveTrackColor: Colors.white24,
              thumbColor: Colors.white,
            ),
            child: Slider(
              min: EraserFilter.minRadiusTiles,
              max: EraserFilter.maxRadiusTiles,
              value: filter.radiusTiles.clamp(
                EraserFilter.minRadiusTiles,
                EraserFilter.maxRadiusTiles,
              ),
              onChanged: (v) {
                filter.radiusTiles = v;
                onChanged();
              },
            ),
          ),
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
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
