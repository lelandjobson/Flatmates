import 'package:flutter/material.dart';

import '../../debug/perf_debug.dart';
import '../../gameplay/day_night/day_night_lighting.dart';
import '../../gameplay/viewers/game_viewer.dart';

/// Compact GameView DevTools sheet. Assets is the only tab for now.
class DevToolsPanel extends StatelessWidget {
  const DevToolsPanel({
    super.key,
    required this.showGizmos,
    required this.onShowGizmosChanged,
    required this.onPlaceCubeboy,
    required this.nightSwatchId,
    required this.onNightSwatchChanged,
    required this.dayNightProgress,
    required this.onDayNightProgressChanged,
    required this.perf,
    required this.onPerfChanged,
  });

  final bool showGizmos;
  final ValueChanged<bool> onShowGizmosChanged;
  final VoidCallback onPlaceCubeboy;
  final String nightSwatchId;
  final ValueChanged<NightSwatch> onNightSwatchChanged;
  final double dayNightProgress;
  final ValueChanged<double> onDayNightProgressChanged;
  final PerfDebugSettings perf;
  final VoidCallback onPerfChanged;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: SizedBox(
        width: 248,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _CheckRow(
                  label: 'Show gizmos',
                  value: showGizmos,
                  onChanged: onShowGizmosChanged,
                ),
                const SizedBox(height: 8),
                const _CategoryHeader('Performance'),
                const SizedBox(height: 4),
                _CheckRow(
                  label: 'Flutter graphs',
                  value: perf.showOverlay,
                  onChanged: (value) {
                    perf.showOverlay = value;
                    onPerfChanged();
                  },
                ),
                _CheckRow(
                  label: 'Frame details',
                  value: perf.showDetails,
                  onChanged: (value) {
                    perf.showDetails = value;
                    onPerfChanged();
                  },
                ),
                _CheckRow(
                  label: 'Repaint rainbow',
                  value: perf.repaintRainbow,
                  onChanged: (value) {
                    perf.repaintRainbow = value;
                    onPerfChanged();
                  },
                ),
                _CheckRow(
                  label: 'Profile paints',
                  value: perf.profilePaints,
                  onChanged: (value) {
                    perf.profilePaints = value;
                    onPerfChanged();
                  },
                ),
                Text(
                  'Graphs = UI vs raster. Rainbow = what redraws. '
                  'Profile paints + --profile → Flutter DevTools.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 8),
                const _CategoryHeader('Isolate layers'),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final layer in SceneLayer.values)
                      _LayerChip(
                        label: layer.shortLabel,
                        hidden: perf.hiddenLayers.contains(layer),
                        onTap: () {
                          if (perf.hiddenLayers.contains(layer)) {
                            perf.hiddenLayers.remove(layer);
                          } else {
                            perf.hiddenLayers.add(layer);
                          }
                          onPerfChanged();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                const _CategoryHeader('Day / night'),
                const SizedBox(height: 4),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: const Color(0xFF1A1A1A),
                    value: NightSwatch.byId(nightSwatchId).id,
                    iconEnabledColor: Colors.white70,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    items: [
                      for (final swatch in NightSwatch.all)
                        DropdownMenuItem(
                          value: swatch.id,
                          child: Text(swatch.label),
                        ),
                    ],
                    onChanged: (id) {
                      if (id != null)
                        onNightSwatchChanged(NightSwatch.byId(id));
                    },
                  ),
                ),
                Text(
                  'Day → night  ${dayNightProgress.toStringAsFixed(2)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    activeTrackColor: Colors.white70,
                    inactiveTrackColor: Colors.white24,
                    thumbColor: Colors.white,
                  ),
                  child: Slider(
                    min: 0,
                    max: 1,
                    value: dayNightProgress.clamp(0.0, 1.0),
                    onChanged: onDayNightProgressChanged,
                  ),
                ),
                const SizedBox(height: 6),
                const _TabChip(label: 'Assets', selected: true),
                const SizedBox(height: 10),
                const _CategoryHeader('Friends'),
                const SizedBox(height: 4),
                _AssetButton(label: 'Cubeboy', onTap: onPlaceCubeboy),
                const SizedBox(height: 10),
                const _CategoryHeader('Structures'),
                const SizedBox(height: 10),
                const _CategoryHeader('Decorations'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  const _CheckRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.85),
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            height: 24,
            width: 36,
            child: IgnorePointer(
              child: Checkbox(
                value: value,
                onChanged: (_) {},
                side: const BorderSide(color: Colors.white54),
                fillColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.selected)) {
                    return Colors.white24;
                  }
                  return Colors.transparent;
                }),
                checkColor: Colors.white,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LayerChip extends StatelessWidget {
  const _LayerChip({
    required this.label,
    required this.hidden,
    required this.onTap,
  });

  final String label;
  final bool hidden;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: hidden ? Colors.transparent : Colors.white24,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: hidden ? Colors.white38 : Colors.white,
            fontSize: 10,
            decoration: hidden ? TextDecoration.lineThrough : null,
          ),
        ),
      ),
    );
  }
}

class _TabChip extends StatelessWidget {
  const _TabChip({required this.label, required this.selected});

  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: selected ? Colors.white24 : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? Colors.white : Colors.white70,
          fontSize: 12,
          fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
        ),
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: TextStyle(
        color: Colors.white.withValues(alpha: 0.55),
        fontSize: 10,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w600,
      ),
    );
  }
}

class _AssetButton extends StatelessWidget {
  const _AssetButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ),
    );
  }
}
