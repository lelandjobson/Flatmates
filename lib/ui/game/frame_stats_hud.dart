import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../debug/frame_timing_stats.dart';
import '../../debug/scene_paint_stats.dart';
import '../fm_safe_area.dart';

/// Live frame-rate from [FrameTiming]s, independent of map [setState].
///
/// Collapsed: fps only. Expanded: UI vs raster split, jank window, and the
/// last [ScenePainter] / landscape paint snapshots.
class FrameStatsHud extends StatefulWidget {
  const FrameStatsHud({super.key, this.expanded = false});

  final bool expanded;

  @override
  State<FrameStatsHud> createState() => _FrameStatsHudState();
}

class _FrameStatsHudState extends State<FrameStatsHud> {
  final _sampler = FrameTimingSampler();
  ScenePaintStats? _scene;
  ScenePaintStats? _landscape;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    final next = _sampler.add(timings);
    if (next == null || !mounted) return;
    setState(() {
      _scene = PaintStatsProbe.scene;
      _landscape = PaintStatsProbe.landscape;
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _sampler.snapshot;
    final fps = snap.fps;
    final color = fps >= 55
        ? Colors.lightGreenAccent
        : fps >= 30
        ? Colors.amberAccent
        : Colors.redAccent;
    return FmSafePositioned(
      top: 12,
      right: 12,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: DefaultTextStyle(
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
              child: widget.expanded
                  ? _ExpandedStats(
                      snap: snap,
                      scene: _scene,
                      landscape: _landscape,
                    )
                  : Text(fps <= 0 ? '— fps' : '${fps.toStringAsFixed(0)} fps'),
            ),
          ),
        ),
      ),
    );
  }
}

class _ExpandedStats extends StatelessWidget {
  const _ExpandedStats({
    required this.snap,
    required this.scene,
    required this.landscape,
  });

  final FrameTimingSnapshot snap;
  final ScenePaintStats? scene;
  final ScenePaintStats? landscape;

  @override
  Widget build(BuildContext context) {
    final fps = snap.fps;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(fps <= 0 ? '— fps' : '${fps.toStringAsFixed(0)} fps'),
        if (snap.hasData) ...[
          const SizedBox(height: 2),
          Text(
            'UI ${snap.uiMs.toStringAsFixed(1)}  '
            'raster ${snap.rasterMs.toStringAsFixed(1)}  '
            'jank ${snap.jankCount}',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        ],
        if (scene != null)
          Text(
            'scene ${scene!.paintMs.toStringAsFixed(1)}ms  '
            '${scene!.visibleMeshes}/${scene!.meshes} mesh  '
            '${scene!.faces} face',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
        if (landscape != null)
          Text(
            'land ${landscape!.paintMs.toStringAsFixed(1)}ms',
            style: const TextStyle(color: Colors.white70, fontSize: 10),
          ),
      ],
    );
  }
}
