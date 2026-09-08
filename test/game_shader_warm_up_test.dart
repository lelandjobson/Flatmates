import 'package:flatmates/gameplay/paint/plane_shade_model.dart';
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

  test('landscape painter treats a new paper texture as a repaint', () {
    final camera = Camera(
      name: 'test',
      position: Vector3(0, 80, 80),
    );
    final listenable = ChangeNotifier();
    final plain = LandscapePlanePainter(
      camera: camera,
      listenable: listenable,
      image: null,
      worldSize: 128,
      tilesSide: 16,
      pixelsPerTile: 8,
    );
    final papered = LandscapePlanePainter(
      camera: camera,
      listenable: listenable,
      image: null,
      worldSize: 128,
      tilesSide: 16,
      pixelsPerTile: 8,
      paperRepeatWorld: 4.0,
    );
    expect(papered.shouldRepaint(plain), isTrue);
    expect(papered.shouldRepaint(papered), isFalse);
  });

  test('cut walls only draw the hole-facing side', () {
    final a = Vector3(0, 0, 0);
    final b = Vector3(0, -8, 0);
    final c = Vector3(8, -8, 0);
    // Inward +Z (into the cut). Visible from the south, hidden from the north.
    expect(
      landscapeCutWallFacesCamera(a, b, c, Vector3(4, 8, 16)),
      isTrue,
    );
    expect(
      landscapeCutWallFacesCamera(a, b, c, Vector3(4, 8, -16)),
      isFalse,
    );
  });

  test('cut walls and sloped ramp take different sun tints', () {
    const shade = PlaneShadeModel();
    final floor = landscapeFaceShadeColor(
      shade,
      Vector3(0, 0, 0),
      Vector3(8, 0, 0),
      Vector3(8, -4, -8),
    );
    final lifted = landscapeFaceShadeColor(
      shade,
      Vector3(0, 0, 0),
      Vector3(8, 0, 0),
      Vector3(8, -4, -8),
      lift: kLandscapeSlopeShadeLift,
    );
    final westWall = landscapeFaceShadeColor(
      shade,
      Vector3(0, 0, 0),
      Vector3(0, 0, 8),
      Vector3(0, -8, 8),
    );
    final eastWall = landscapeFaceShadeColor(
      shade,
      Vector3(8, 0, 0),
      Vector3(8, -8, 0),
      Vector3(8, -8, 8),
    );
    expect(floor, isNot(equals(westWall)));
    expect(westWall, isNot(equals(eastWall)));
    expect(floor.computeLuminance(), greaterThan(westWall.computeLuminance()));
    expect(lifted.computeLuminance(), greaterThan(floor.computeLuminance()));
    expect(lifted.computeLuminance(), lessThan(1.0));
  });

  test('slope-to-flat west wall keeps the top triangle', () {
    final a = Vector3(0, 0, 14);
    final b = Vector3(0, 0, 16);
    final c = Vector3(0, 0, 16);
    final d = Vector3(0, -1, 14);
    expect(
      landscapeCutWallFacesCamera(a, b, c, Vector3(4, 4, 15)),
      isFalse,
    );
    final verts = landscapeCleanWallVerts([a, b, c, d]);
    expect(verts, hasLength(3));
    expect(landscapeCutWallVisible(verts, Vector3(4, 4, 15)), isTrue);
  });

  test('west cut wall samples the neighboring (-1, ty) tile', () {
    expect(landscapeCutWallSampleX(0, 0, 1), 0);
    expect(landscapeCutWallSampleX(0, -8, 1), -8);
    expect(landscapeCutWallSampleX(8, -8, -1), 16);
  });
}
