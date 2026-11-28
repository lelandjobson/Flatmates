// flutter run -d macos --profile -t tool/construction_profile.dart
// Add --dart-define=ROOMS=4 for four occupied rooms.
// Fresh, unsaved occupied room. Writes frame timings to /tmp and exits.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flatmates/protoplane/controller.dart';
import 'package:flatmates/protoplane/construction.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/geometry.dart';
import 'package:flatmates/rendering/scene_view.dart';
import 'package:flatmates/screens/protoplane_concept_view.dart';

void main() => runApp(const MaterialApp(home: _Profile()));

class _Profile extends StatefulWidget {
  const _Profile();
  @override
  State<_Profile> createState() => _ProfileState();
}

class _ProfileState extends State<_Profile> {
  static const roomCount = int.fromEnvironment('ROOMS', defaultValue: 1);
  final model = ProtoplaneController()..enableInPlaceDrawing();
  final samples = <String, List<Map<String, num>>>{};
  String phase = 'warmup';
  final inputSamples = <String, List<double>>{};
  final overlaySamples = <String, List<double>>{};
  final constructionSamples = <double>[];
  SceneView? view;
  late final CraftObject room;
  void draw(String id, Region region) {
    model.constructionTool = ConstructionTool.pencil;
    model.enter(id);
    if (!model.commitDrawingPath([...region.outer, region.outer.first])) {
      throw StateError('Draw: ${model.error}');
    }
  }

  CraftObject place(
    ConstructionTool tool,
    String id,
    Offset point, [
    ConstructionPaper paper = ConstructionPaper.building,
  ]) {
    final watch = Stopwatch()..start();
    final evaluation = model.evaluateConstruction(
      tool,
      id,
      point,
      paper: paper,
    );
    if (!model.applyConstruction(evaluation)) {
      throw StateError('${evaluation.issue} / ${model.error}');
    }
    constructionSamples.add(watch.elapsedMicroseconds / 1000);
    return model.objects[evaluation.object!.id]!;
  }

  @override
  void initState() {
    super.initState();
    model.balances[PaperMaterial.paperWhite] = roomCount * 16;
    model.balances[PaperMaterial.paperGreen] = roomCount * 8;
    final origins = roomCount == 1
        ? [Offset.zero]
        : const [Offset(-1, -1), Offset(1, -1), Offset(-1, 1), Offset(1, 1)];
    for (final origin in origins) {
      final ground = model.landscape.terrain.tiles.values.firstWhere(
        (t) =>
            t.x == origin.dx &&
            t.y == origin.dy &&
            t.sheet.island == 'starter' &&
            t.sheet.material == PaperMaterial.paperWhite,
      );
      final center = origin + const Offset(.5, .5);
      draw(ground.id, rectangle(1, 1, origin: origin));
      final mat = place(ConstructionTool.paper, ground.id, center);
      final building = place(
        ConstructionTool.volume,
        'surface-${mat.id}',
        center,
      );
      if (origin == origins.first) room = building;
      final wall = 'surface-${building.id}-wall-0-0-out-0';
      draw(wall, rectangle(.25, .5, origin: const Offset(.25, 0)));
      place(ConstructionTool.scissors, wall, const Offset(.375, .25));
      final floor = 'surface-${building.id}-floor-in-0';
      draw(floor, rectangle(.25, .5, origin: origin + const Offset(.5, .25)));
      final spot = origin + const Offset(.625, .5);
      final cloth = place(
        ConstructionTool.paper,
        floor,
        spot,
        ConstructionPaper.cloth,
      );
      place(
        ConstructionTool.volume,
        'surface-${cloth.id}',
        spot,
        ConstructionPaper.cloth,
      );
    }
    model.leave();
    model.constructionTool = null;
    SchedulerBinding.instance.addTimingsCallback(timings);
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(run()));
  }

  void timings(List<ui.FrameTiming> batch) {
    final list = samples[phase];
    if (list == null) return;
    for (final t in batch) {
      list.add({
        'buildMs': t.buildDuration.inMicroseconds / 1000,
        'rasterMs': t.rasterDuration.inMicroseconds / 1000,
        'totalMs': t.totalSpan.inMicroseconds / 1000,
      });
    }
  }

  void locate(Element element) {
    if (element.widget is SceneView) view = element.widget as SceneView;
    element.visitChildren(locate);
  }

  void tap(Offset at) {
    GestureBinding.instance.handlePointerEvent(
      PointerDownEvent(pointer: 1, position: at),
    );
    GestureBinding.instance.handlePointerEvent(
      PointerUpEvent(pointer: 1, position: at),
    );
  }

  Future<void> run() async {
    await Future<void>.delayed(const Duration(seconds: 2));
    if (!mounted) return;
    (context as Element).visitChildren(locate);
    final scene = view!.scene;
    final camera = scene.camera!;
    final size = (context.findRenderObject()! as RenderBox).size;
    final roof = model.planes['surface-${room.id}-roof-out-0']!;
    for (final next in ['world', 'navigation', 'paper', 'idle']) {
      if (next == 'navigation') {
        tap(
          camera.projectToScreen(roof.point(roof.region.bounds.center), size)!,
        );
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      if (next == 'paper') {
        model.constructionTool = ConstructionTool.paper;
        model.constructionPaper = ConstructionPaper.cloth;
        model.clearError();
      }
      phase = 'warmup';
      await Future<void>.delayed(const Duration(seconds: 1));
      samples[next] = [];
      inputSamples[next] = [];
      overlaySamples[next] = [];
      phase = next;
      for (var i = 0; i < 180; i++) {
        if (next != 'idle') {
          final watch = Stopwatch()..start();
          GestureBinding.instance.handlePointerEvent(
            PointerScrollEvent(
              position: size.center(Offset.zero),
              scrollDelta: Offset(0, i.isEven ? 1 : -1),
            ),
          );
          inputSamples[next]!.add(watch.elapsedMicroseconds / 1000);
        }
        await Future<void>.delayed(const Duration(milliseconds: 16));
        overlaySamples[next]!.add(scene.overlayPaintMs);
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final report = <String, Object>{};
    for (final entry in samples.entries) {
      report[entry.key] = {
        'frames': entry.value.length,
        'inputCpuMs': summarize(inputSamples[entry.key]!),
        'inkCpuMs': summarize(overlaySamples[entry.key]!),
        for (final metric in ['buildMs', 'rasterMs', 'totalMs'])
          metric: summarize(
            entry.value.map((s) => s[metric]!.toDouble()).toList(),
          ),
      };
    }
    report['constructionCpuMs'] = summarize(constructionSamples);
    report['scene'] = {
      'rooms': roomCount,
      'residents': model.housing.tenants.length,
      'meshes': scene.meshes.length,
      'paintMs': scene.paintStats?.paintMs ?? 0,
    };
    final encoded = const JsonEncoder.withIndent('  ').convert(report);
    await File(
      '/tmp/construction-profile-$roomCount.json',
    ).writeAsString(encoded);
    debugPrint(encoded);
    exit(0);
  }

  Map<String, double> summarize(List<double> values) {
    values.sort();
    return values.isEmpty
        ? {}
        : {
            'median': values[values.length ~/ 2],
            'p95': values[((values.length - 1) * .95).round()],
          };
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(timings);
    model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ProtoplaneConceptView(controller: model, animateFog: false);
}
