import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../rendering/mesh.dart';
import '../geometry/geometry.dart';
import '../rendering/scene/scene.dart';
import 'geometry.dart';
import 'meshes.dart';
import 'models.dart';

/// Session-only renderer load. Never enters the crafting model or save file.
class GeometryBenchmark {
  final meshes = <Mesh>[];
  math.Random _random = math.Random(42);
  double side = 32;
  int walls = 0, volumes = 0;
  bool get active => meshes.isNotEmpty || side > 32;

  CraftPlane get plane => CraftPlane(
    id: 'benchmark-ground',
    origin: Vector3.zero(),
    u: Vector3(1, 0, 0),
    v: Vector3(0, 0, -1),
    region: rectangle(-side / 2, -side / 2, side, side),
    grids: const [],
  );

  static Region rectangle(double x, double y, double w, double h) => Region([
    Offset(x, y),
    Offset(x + w, y),
    Offset(x + w, y + h),
    Offset(x, y + h),
  ]);

  Mesh get ground => Mesh(
    id: 'benchmark-ground',
    name: 'Benchmark map',
    groundPlane: true,
    geometry: regionGeometry(
      'benchmark-ground',
      plane,
      plane.region,
      0,
      base: -.02,
    ),
    material: MaterialModel(color: const Color(0xff858578), doubleSided: true),
  );

  void expand() {
    side *= 2;
  }

  void add({required bool wall}) {
    final p = plane;
    for (var i = 0; i < 100; i++) {
      final x = _random.nextDouble() * (side - 3) - side / 2;
      final y = _random.nextDouble() * (side - 3) - side / 2;
      final width = .5 + _random.nextDouble() * 2;
      final height = .5 + _random.nextDouble() * 2;
      final horizontal = _random.nextBool();
      final region = rectangle(
        x,
        y,
        wall && !horizontal ? .12 : width,
        wall && horizontal ? .12 : height,
      );
      final id = 'benchmark-${meshes.length}';
      meshes.add(
        Mesh(
          id: id,
          name: wall ? 'Benchmark wall' : 'Benchmark volume',
          geometry: regionGeometry(
            id,
            p,
            region,
            .5 + _random.nextDouble() * 2,
          ),
          material: MaterialModel(
            color: wall ? const Color(0xffbfa98c) : const Color(0xff91a5b8),
          ),
        ),
      );
    }
    if (wall) {
      walls += 100;
    } else {
      volumes += 100;
    }
  }

  void reset() {
    meshes.clear();
    side = 32;
    walls = volumes = 0;
    _random = math.Random(42);
  }
}

class GeometryBenchmarkPanel extends StatefulWidget {
  const GeometryBenchmarkPanel({
    super.key,
    required this.benchmark,
    required this.scene,
    required this.changed,
  });
  final GeometryBenchmark benchmark;
  final Scene scene;
  final VoidCallback changed;
  @override
  State<GeometryBenchmarkPanel> createState() => _GeometryBenchmarkPanelState();
}

class _GeometryBenchmarkPanelState extends State<GeometryBenchmarkPanel> {
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void change(VoidCallback action) {
    action();
    widget.changed();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.benchmark;
    final stats = widget.scene.paintStats;
    final meshes = widget.scene.meshes;
    final faces = meshes.fold<int>(
      0,
      (sum, m) => sum + m.geometry.faces.length,
    );
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Text('Map: ${b.side.toInt()} × ${b.side.toInt()}'),
        Text('Benchmark walls: ${b.walls}  Volumes: ${b.volumes}'),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: b.side < 4096 ? () => change(b.expand) : null,
              child: const Text('Expand map ×2'),
            ),
            TextButton(
              onPressed: () => change(() => b.add(wall: true)),
              child: const Text('Add 100 walls'),
            ),
            TextButton(
              onPressed: () => change(() => b.add(wall: false)),
              child: const Text('Add 100 volumes'),
            ),
            TextButton(
              onPressed: () => change(b.reset),
              child: const Text('Reset benchmark'),
            ),
          ],
        ),
        const Divider(),
        Text('World meshes: ${meshes.length}'),
        Text('World faces: $faces'),
        Text('Enabled meshes: ${stats?.visibleMeshes ?? 0}'),
        Text('Viewport meshes (bounds): ${stats?.viewportMeshes ?? 0}'),
        Text('Submitted faces: ${stats?.faces ?? 0}'),
        Text('Draw calls: ${stats?.drawCalls ?? 0}'),
        Text('Paint: ${stats?.paintMs.toStringAsFixed(2) ?? "—"} ms'),
        Text(
          'Ink overlay: ${widget.scene.overlayPaintMs.toStringAsFixed(2)} ms',
        ),
      ],
    );
  }
}
