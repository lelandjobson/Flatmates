import 'package:flatmates/debug/perf_debug.dart';
import 'package:flatmates/gameplay/day_night/day_night_lighting.dart';
import 'package:flatmates/gameplay/viewers/game_viewer.dart';
import 'package:flatmates/ui/game/dev_tools_panel.dart';
import 'package:flatmates/ui/game/frame_stats_hud.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('applyEngineFlags sets rainbow and paint profiling, then clears', () {
    final perf = PerfDebugSettings()
      ..repaintRainbow = true
      ..profilePaints = true;
    try {
      perf.applyEngineFlags();
      expect(debugRepaintRainbowEnabled, isTrue);
      expect(debugProfilePaintsEnabled, isTrue);
    } finally {
      PerfDebugSettings.resetEngineFlags();
    }
    expect(debugRepaintRainbowEnabled, isFalse);
    expect(debugProfilePaintsEnabled, isFalse);
  });

  testWidgets('performance toggles flip overlay, details, and layer isolation', (
    tester,
  ) async {
    final perf = PerfDebugSettings();
    var changed = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DevToolsPanel(
            showGizmos: false,
            onShowGizmosChanged: (_) {},
            onPlaceCubeboy: () {},
            nightSwatchId: NightSwatch.invertedTwilight.id,
            onNightSwatchChanged: (_) {},
            dayNightProgress: 0,
            onDayNightProgressChanged: (_) {},
            closeZoom: 42,
            onCloseZoomChanged: (_) {},
            perf: perf,
            onPerfChanged: () => changed++,
            faceAmbient: 0.25,
            faceKeyIntensity: 0.95,
            faceFillIntensity: 0.35,
            faceSunX: -0.6,
            faceSunY: -1,
            faceSunZ: -0.4,
            faceShadowOpacity: 0.22,
            onFaceLightChanged: ({
              ambient,
              keyIntensity,
              fillIntensity,
              sunX,
              sunY,
              sunZ,
              shadowOpacity,
            }) {},
            onFaceLightReset: () {},
          ),
        ),
      ),
    );

    expect(find.text('Performance'), findsOneWidget);
    expect(find.text('Isolate layers'), findsOneWidget);

    await tester.tap(find.text('Flutter graphs'));
    expect(perf.showOverlay, isTrue);
    expect(changed, 1);

    await tester.tap(find.text('Frame details'));
    expect(perf.showDetails, isTrue);

    await tester.tap(find.text('Repaint rainbow'));
    expect(perf.repaintRainbow, isTrue);

    await tester.tap(find.text('Profile paints'));
    expect(perf.profilePaints, isTrue);

    await tester.tap(find.text('land'));
    expect(perf.hiddenLayers, contains(SceneLayer.landscape));
    await tester.tap(find.text('land'));
    expect(perf.hiddenLayers, isNot(contains(SceneLayer.landscape)));

    expect(find.text('Camera'), findsOneWidget);
    expect(find.text('Close zoom  42'), findsOneWidget);
    expect(find.text('Sun / shade'), findsOneWidget);
    expect(find.text('Reset sun / shade'), findsOneWidget);
  });

  testWidgets('frame hud starts collapsed on a dash fps', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [FrameStatsHud()])),
      ),
    );
    expect(find.text('— fps'), findsOneWidget);
    expect(find.textContaining('raster'), findsNothing);
  });

  testWidgets('expanded frame hud shows the thread split labels', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Stack(children: [FrameStatsHud(expanded: true)])),
      ),
    );
    expect(find.text('— fps'), findsOneWidget);
  });
}
