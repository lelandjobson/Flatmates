import 'package:flatmates/debug/frame_timing_stats.dart';
import 'package:flatmates/gameplay/viewers/game_viewer.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

FrameTiming _timing({
  required int buildUs,
  required int rasterUs,
  int vsyncStart = 0,
}) {
  final buildStart = vsyncStart + 1000;
  final buildFinish = buildStart + buildUs;
  final rasterStart = buildFinish;
  final rasterFinish = rasterStart + rasterUs;
  return FrameTiming(
    vsyncStart: vsyncStart,
    buildStart: buildStart,
    buildFinish: buildFinish,
    rasterStart: rasterStart,
    rasterFinish: rasterFinish,
    rasterFinishWallTime: rasterFinish,
  );
}

void main() {
  test('sampler waits for min samples then reports fps and thread split', () {
    final sampler = FrameTimingSampler(
      minSamples: 4,
      minInterval: Duration.zero,
    );
    final now = DateTime(2026, 1, 1);
    expect(
      sampler.add([_timing(buildUs: 4000, rasterUs: 8000)], now: now),
      isNull,
    );

    final frames = [
      for (var i = 1; i < 4; i++)
        _timing(buildUs: 4000, rasterUs: 8000, vsyncStart: i * 16667),
    ];
    final snap = sampler.add(frames, now: now);
    expect(snap, isNotNull);
    expect(snap!.sampleCount, 4);
    expect(snap.uiMs, closeTo(4.0, 0.05));
    expect(snap.rasterMs, closeTo(8.0, 0.05));
    expect(snap.fps, greaterThan(50));
    expect(snap.jankCount, 0);
  });

  test('jank counts frames whose UI or raster exceeds the budget', () {
    final sampler = FrameTimingSampler(
      minSamples: 2,
      minInterval: Duration.zero,
      jankBudgetMs: 17,
    );
    final now = DateTime(2026, 1, 1);
    final snap = sampler.add([
      _timing(buildUs: 4000, rasterUs: 8000),
      _timing(buildUs: 22000, rasterUs: 4000, vsyncStart: 20000),
    ], now: now);
    expect(snap, isNotNull);
    expect(snap!.jankCount, 1);
  });

  test('layer mask hiding subtracts without mutating the original', () {
    final hidden = SceneLayerMask.all.hiding({
      SceneLayer.landscape,
      SceneLayer.friends,
    });
    expect(hidden.shows(SceneLayer.landscape), isFalse);
    expect(hidden.shows(SceneLayer.volumes), isTrue);
    expect(SceneLayerMask.all.shows(SceneLayer.landscape), isTrue);
    expect(SceneLayerMask.all.hiding({}).visible, SceneLayerMask.all.visible);
  });
}
