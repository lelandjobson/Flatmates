import 'construction_fixture.dart';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart';
import 'package:flatmates/gestures/game_controls.dart';
import 'package:flatmates/protoplane/focus_view.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/protoplane/stroke_preview.dart';
import 'package:flatmates/rendering/scene/camera.dart';

void main() {
  test(
    'full focus fits long pieces to viewport and picks nearest half-turn',
    () {
      final model = constructionWorld();
      addTearDown(model.dispose);
      final ground = model.planes['ground-4-4']!;
      final plane = CraftPlane(
        id: 'long',
        origin: ground.origin,
        u: ground.u,
        v: ground.v,
        region: rectangle(2, .5),
        grids: ground.grids,
      );
      for (final size in [const Size(390, 844), const Size(1100, 700)]) {
        for (final sign in [-1.0, 1.0]) {
          final camera = Camera(
            name: 'fit',
            position: Vector3(sign * 6, 9, sign * 4),
            target: Vector3.zero(),
            fovDegrees: 50,
          );
          final pose = focusPlanePose(camera, plane, size, fullFocus: true);
          final axis = size.height > size.width ? plane.u : plane.v;
          expect(pose.up.dot(axis).abs(), closeTo(1, 1e-6));
          final incoming = (camera.position - camera.target).normalized();
          final screenUp = (camera.up - incoming * camera.up.dot(incoming))
              .normalized();
          expect(pose.up.dot(screenUp), greaterThan(0));
          final focused = Camera(
            name: 'result',
            position: pose.position,
            target: pose.target,
            up: pose.up,
            fovDegrees: pose.fov,
          );
          for (final vertex in plane.region.outer) {
            final projected = focused.projectToScreen(
              plane.point(vertex),
              size,
            )!;
            expect(projected.dx, greaterThanOrEqualTo(75));
            expect(projected.dx, lessThanOrEqualTo(size.width - 75));
            expect(projected.dy, greaterThanOrEqualTo(140));
            expect(projected.dy, lessThanOrEqualTo(size.height - 140));
          }
        }
      }
    },
  );

  test(
    'full focus chooses nearest quarter-turn for each incoming quadrant',
    () {
      final model = constructionWorld();
      addTearDown(model.dispose);
      final plane = model.planes['ground-4-4']!;
      for (final x in [-6.0, 6.0]) {
        for (final z in [-4.0, 4.0]) {
          final camera = Camera(
            name: 'test',
            position: Vector3(x, 9, z),
            target: Vector3.zero(),
            fovDegrees: 50,
          );
          final full = focusPlanePose(
            camera,
            plane,
            const Size(900, 700),
            fullFocus: true,
          );
          expect(
            (full.position - full.target).normalized().dot(plane.normal).abs(),
            closeTo(1, 1e-6),
          );
          expect(
            [
              full.up.dot(plane.u).abs(),
              full.up.dot(plane.v).abs(),
            ].reduce((a, b) => a > b ? a : b),
            closeTo(1, 1e-6),
          );
          final forward = (camera.position - camera.target).normalized();
          final screenUp = (camera.up - forward * camera.up.dot(forward))
              .normalized();
          // Chosen up cannot reverse the incoming screen orientation.
          expect(full.up.dot(screenUp), greaterThan(0));
        }
      }
    },
  );

  test(
    'profiles load by platform and switch by pointer without changing gesture meanings',
    () {
      final pc = loadGameControls(platform: TargetPlatform.macOS),
          mobile = loadGameControls(platform: TargetPlatform.android);
      addTearDown(pc.dispose);
      addTearDown(mobile.dispose);
      expect(pc.profile.reticle, ReticleMode.cursor);
      expect(mobile.profile.reticle, ReticleMode.centered);
      const size = Size(800, 600), point = Offset(100, 120);
      pc.hover(PointerDeviceKind.mouse, point);
      expect(pc.worldAim(size), point);
      pc.begin(PointerDeviceKind.touch, point);
      expect(pc.worldAim(size), const Offset(400, 300));
      pc.hover(PointerDeviceKind.mouse, const Offset(700, 500));
      expect(pc.worldAim(size), const Offset(400, 300));
      pc.end();
      pc.hover(PointerDeviceKind.mouse, point);
      expect(pc.worldAim(size), point);
      for (final profile in [
        GameControlProfile.mobile,
        GameControlProfile.desktop,
      ]) {
        expect(
          profile.worldDrag(pointers: 1, buttons: kPrimaryMouseButton),
          WorldDrag.pan,
        );
        expect(
          profile.worldDrag(pointers: 2, buttons: kPrimaryMouseButton),
          WorldDrag.rotate,
        );
        expect(profile.canActivate(kSecondaryMouseButton), isFalse);
      }
      expect(pc.craftingAim(point), point);
      expect(mobile.craftingAim(point), point);
    },
  );
  test('cursor reticle hides outside surface and clamps after resize', () {
    final c = loadGameControls(platform: TargetPlatform.windows);
    addTearDown(c.dispose);
    c.hover(PointerDeviceKind.mouse, const Offset(600, 400));
    expect(c.showReticle, isTrue);
    expect(c.worldAim(const Size(300, 200)), const Offset(300, 200));
    c.exit();
    c.move(PointerDeviceKind.mouse, const Offset(700, 400));
    expect(c.showReticle, isFalse);
    c.begin(PointerDeviceKind.touch, const Offset(20, 20));
    expect(c.showReticle, isTrue);
  });
  test('focus retains azimuth and lens and tips gently toward ground', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    final camera = Camera(
      name: 'world',
      position: Vector3(6, 9, 6),
      target: Vector3.zero(),
      fovDegrees: 50,
    );
    final pose = focusPlanePose(
      camera,
      c.planes['ground-4-4']!,
      const Size(900, 700),
    );
    final old = (camera.position - camera.target).normalized(),
        next = (pose.position - pose.target).normalized();
    expect(pose.fov, 50);
    expect(old.dot(next), greaterThan(.98));
    expect(next.x / next.z, closeTo(old.x / old.z, 1e-6));
    expect(pose.up.dot(camera.up), greaterThan(0));
    expect(pose.position.distanceTo(pose.target), greaterThanOrEqualTo(2.5));
  });
  test('focus context keeps only neighboring tiles on the same level', () {
    final c = constructionWorld();
    addTearDown(c.dispose);
    final active = c.planes['ground-4-4']!;
    expect(
      adjacentFocusContext(
        active,
        c.planes['ground-5-5']!,
        c.objects,
        c.planes,
      ),
      isTrue,
    );
    expect(
      adjacentFocusContext(
        active,
        c.planes['ground-6-4']!,
        c.objects,
        c.planes,
      ),
      isFalse,
    );
    final upper = CraftPlane(
      id: 'upper-test',
      origin: active.origin + Vector3(0, 1, 0),
      u: active.u,
      v: active.v,
      region: active.region,
      grids: active.grids,
    );
    expect(adjacentFocusContext(active, upper, c.objects, c.planes), isFalse);
  });
  test(
    'live stroke draws a partial permitted edge without committing a node',
    () {
      final c = constructionWorld();
      addTearDown(c.dispose);
      final grid = c.planes['ground-4-4']!.grids.single;
      final path = [0];
      final partial = liveStrokePreview(
        grid: grid,
        path: path,
        pointer: const Offset(.25, 0),
        project: (p) => p,
      );
      expect(partial.first, Offset.zero);
      expect(partial.last, const Offset(.25, 0));
      expect(path, [0]);
      expect(
        liveStrokePreview(
          grid: grid,
          path: [0, 1, 4, 3, 0],
          pointer: const Offset(.25, 0),
          project: (p) => p,
        ),
        isEmpty,
      );
    },
  );
  test('live curve follows the actual edge instead of its endpoint chord', () {
    final grid = CraftGrid(
      id: 'curve',
      name: 'curve',
      nodes: [Offset.zero, const Offset(1, 0)],
      edges: [const GridEdge(0, 1, Offset(.5, -.4))],
      recipes: [],
    );
    final partial = liveStrokePreview(
      grid: grid,
      path: [0],
      pointer: const Offset(.5, -.2),
      project: (p) => p,
    );
    expect(partial.length, greaterThan(2));
    expect(partial.last.dy, closeTo(-.2, .002));
    expect(partial.last.dx, closeTo(.5, .002));
  });
}
