import 'package:flatmates/landscape/landscape_plane_painter.dart';
import 'package:flatmates/rendering/game_shader_warm_up.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  testWidgets('game shader warm-up rasterizes GameView pipelines', (
    tester,
  ) async {
    await const GameViewShaderWarmUp().execute();
  });

  test('landscape painter treats a new modulate tint as a repaint', () {
    final camera = Camera(
      name: 'test',
      position: Vector3(0, 80, 80),
    );
    final listenable = ChangeNotifier();
    final day = LandscapePlanePainter(
      camera: camera,
      listenable: listenable,
      image: null,
      worldSize: 128,
      tilesSide: 16,
      pixelsPerTile: 8,
    );
    final dusk = LandscapePlanePainter(
      camera: camera,
      listenable: listenable,
      image: null,
      worldSize: 128,
      tilesSide: 16,
      pixelsPerTile: 8,
      modulateColor: const Color(0xFFE8E0F0),
    );
    expect(dusk.shouldRepaint(day), isTrue);
    expect(dusk.shouldRepaint(dusk), isFalse);
  });
}
