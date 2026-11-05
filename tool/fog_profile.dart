// flutter run -d macos --profile -t tool/fog_profile.dart
// Uses a fresh unsaved world; writes captures and timings to /tmp.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/fog_settings.dart';
import 'package:flatmates/protoplane/fog_overlay.dart';
import 'package:flatmates/protoplane/harvest_meshes.dart';
import 'package:flatmates/rendering/scene/scene.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/gameplay/day_night/day_night_lighting.dart';

void main() => runApp(
  const MaterialApp(debugShowCheckedModeBanner: false, home: _Profile()),
);

class _Profile extends StatefulWidget {
  const _Profile();
  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile>
    with SingleTickerProviderStateMixin {
  final c = ProtoplaneController(preset: WorldPreset.paper);
  final fog = FogSettings();
  final cache = HarvestMeshCache();
  final scene = Scene();
  final camera = Camera(
    name: 'fog-profile',
    position: Vector3(-6, 9, 6),
    target: Vector3(2, 0, -2),
    fovDegrees: 50,
    near: .01,
  );
  final boundary = GlobalKey();
  final timings = <String, List<double>>{'off': [], 'on': [], 'idle': []};
  late final Ticker ticker = createTicker(_tick);
  int frame = 0;
  String phase = 'warmup';
  int idlePaintStart = 0, maskStart = 0, slotsStart = 0, wallsStart = 0;
  bool finishing = false;
  Size captureSize = const Size(900, 700);
  @override
  void initState() {
    super.initState();
    final light = DayNightLighting.day();
    scene.camera = camera;
    scene.globalIllumination = light.globalIllumination;
    scene.setLights(light.lights);
    scene.setMeshes([
      for (final p in c.planes.values) cache.mesh(p, c.landscape),
      ...cache.walls(c.landscape.terrain!),
    ]);
    SchedulerBinding.instance.addTimingsCallback(_timings);
    ticker.start();
  }

  void _timings(List<ui.FrameTiming> batch) {
    final list = timings[phase];
    if (list != null) {
      for (final t in batch) {
        list.add(t.rasterDuration.inMicroseconds / 1000);
      }
    }
  }

  void _tick(Duration elapsed) {
    if (finishing) return;
    frame++;
    if (frame == 120) {
      setState(() {
        fog.enabled = false;
        phase = 'off';
      });
      maskStart = FogField.builds;
      slotsStart = cache.rasterizedTiles;
      wallsStart = cache.rebuiltWalls;
    }
    if (frame == 480) {
      setState(() {
        fog.enabled = true;
        phase = 'on';
      });
    }
    if (frame == 840) {
      phase = 'idle';
      idlePaintStart = _CountingPainter.paints;
    }
    if (frame < 840) {
      final t = (frame % 360) / 360 * math.pi * 2;
      final target = Vector3(2 + math.sin(t) * .7, 0, -2 + math.cos(t) * .7);
      camera.setTarget(target);
      camera.setPosition(target + Vector3(-8, 9, 8));
      scene.markNeedsPaint();
    }
    if (frame == 960) {
      finishing = true;
      ticker.stop();
      unawaited(_finish());
    }
  }

  Future<void> _capture(String name) async {
    await Future<void>.delayed(const Duration(milliseconds: 150));
    await WidgetsBinding.instance.endOfFrame;
    final b =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await b.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('/tmp/fog-$name.png').writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  }

  Future<void> _finish() async {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    final result = <String, dynamic>{};
    for (final e in timings.entries) {
      e.value.sort();
      result[e.key] = {
        'frames': e.value.length,
        'p95RasterMs': e.value[(e.value.length * .95).floor()],
        'medianRasterMs': e.value[e.value.length ~/ 2],
      };
    }
    result['shader'] = {
      'paints': FogDiagnostics.shaderPaints,
      'fallback': FogDiagnostics.fallbackPaints,
      'error': FogDiagnostics.shaderError?.toString(),
    };
    result['cacheDeltas'] = {
      'masks': FogField.builds - maskStart,
      'atlasSlots': cache.rasterizedTiles - slotsStart,
      'walls': cache.rebuiltWalls - wallsStart,
      'idleScenePaints': _CountingPainter.paints - idlePaintStart,
    };
    await File(
      '/tmp/fog-profile.json',
    ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
    debugPrint('FOG_PROFILE ${jsonEncode(result)}');
    for (final size in [
      const Size(900, 700),
      const Size(390, 844),
      const Size(844, 390),
    ]) {
      for (final theme in FogTheme.values) {
        setState(() {
          fog.theme = theme;
          captureSize = size;
        });
        await _capture('${size.width.toInt()}-${theme.name}');
      }
    }
    setState(() => fog.theme = FogTheme.paper);
    c.revealAllAreas();
    setState(() {});
    await Future<void>.delayed(const Duration(seconds: 1));
    await _capture('revealed');
    debugPrint('FOG_PROFILE_DONE');
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: OverflowBox(
      minWidth: captureSize.width,
      maxWidth: captureSize.width,
      minHeight: captureSize.height,
      maxHeight: captureSize.height,
      child: SizedBox(
        width: captureSize.width,
        height: captureSize.height,
        child: RepaintBoundary(
          key: boundary,
          child: Stack(
            fit: StackFit.expand,
            children: [
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Color(0xff263b70),
                      Color(0xff765184),
                      Color(0xffe9a072),
                    ],
                  ),
                ),
              ),
              RepaintBoundary(
                child: CustomPaint(
                  painter: _CountingPainter(scene: scene),
                  isComplex: true,
                ),
              ),
              FogOverlay(
                model: c,
                camera: camera,
                settings: fog,
                cameraChanges: scene,
              ),
              Positioned(
                left: 12,
                top: 12,
                child: Text('Fog profile · $phase'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  @override
  void dispose() {
    ticker.dispose();
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    cache.dispose();
    c.dispose();
    super.dispose();
  }
}

class _CountingPainter extends ScenePainter {
  _CountingPainter({required super.scene});
  static int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    super.paint(canvas, size);
  }
}
