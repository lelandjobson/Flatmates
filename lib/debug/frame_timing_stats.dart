import 'package:flutter/scheduler.dart';

/// Rolling average of [FrameTiming]s for an in-game HUD.
///
/// [fps] uses [FrameTiming.totalSpan]. [uiMs] is Dart build/layout/paint
/// recording; [rasterMs] is the raster thread (canvas / Impeller / Skia).
class FrameTimingSnapshot {
  const FrameTimingSnapshot({
    this.fps = 0,
    this.uiMs = 0,
    this.rasterMs = 0,
    this.totalMs = 0,
    this.jankCount = 0,
    this.sampleCount = 0,
  });

  final double fps;
  final double uiMs;
  final double rasterMs;
  final double totalMs;
  final int jankCount;
  final int sampleCount;

  bool get hasData => sampleCount > 0;
}

class FrameTimingSampler {
  FrameTimingSampler({
    this.minSamples = 4,
    this.minInterval = const Duration(milliseconds: 250),
    this.jankBudgetMs = 17,
  });

  final int minSamples;
  final Duration minInterval;
  final int jankBudgetMs;

  FrameTimingSnapshot snapshot = const FrameTimingSnapshot();

  int _samples = 0;
  double _accumTotalMs = 0;
  double _accumUiMs = 0;
  double _accumRasterMs = 0;
  int _jank = 0;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// Folds [timings] into the window. Returns a new [snapshot] when enough
  /// samples have landed and [minInterval] has elapsed; otherwise `null`.
  FrameTimingSnapshot? add(List<FrameTiming> timings, {DateTime? now}) {
    final budgetUs = jankBudgetMs * 1000;
    for (final timing in timings) {
      final totalMs = timing.totalSpan.inMicroseconds / 1000.0;
      if (totalMs <= 0) continue;
      _accumTotalMs += totalMs;
      _accumUiMs += timing.buildDuration.inMicroseconds / 1000.0;
      _accumRasterMs += timing.rasterDuration.inMicroseconds / 1000.0;
      _samples++;
      if (timing.buildDuration.inMicroseconds >= budgetUs ||
          timing.rasterDuration.inMicroseconds >= budgetUs) {
        _jank++;
      }
    }
    if (_samples < minSamples) return null;
    final at = now ?? DateTime.now();
    if (at.difference(_lastEmit) < minInterval) return null;

    snapshot = FrameTimingSnapshot(
      fps: 1000.0 * _samples / _accumTotalMs,
      uiMs: _accumUiMs / _samples,
      rasterMs: _accumRasterMs / _samples,
      totalMs: _accumTotalMs / _samples,
      jankCount: _jank,
      sampleCount: _samples,
    );
    _samples = 0;
    _accumTotalMs = 0;
    _accumUiMs = 0;
    _accumRasterMs = 0;
    _jank = 0;
    _lastEmit = at;
    return snapshot;
  }
}
