import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flatmates/protoplane/safe_zone.dart';
import 'package:flatmates/protoplane/focus_view.dart';
import 'package:flatmates/protoplane/dev_settings.dart';
import 'package:flatmates/protoplane/models.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  test('safe rectangle excludes measured controls and platform insets', () {
    final r = craftingSafeZone(
      const Size(900, 700),
      header: const Rect.fromLTWH(12, 24, 876, 64),
      left: const Rect.fromLTWH(10, 200, 52, 250),
      right: const Rect.fromLTWH(778, 200, 112, 300),
      footer: const Rect.fromLTWH(76, 580, 748, 100),
      insetBottom: 20,
    );
    expect(r, const Rect.fromLTRB(70, 96, 770, 572));
  });
  test('safe-zone toggle persists and migrates disabled', () {
    final s = ProtoplaneSettings()..showSafeZone = true;
    expect((ProtoplaneSettings()..load(s.toJson())).showSafeZone, isTrue);
    expect(
      (ProtoplaneSettings()..load(s.toJson()..remove('showSafeZone')))
          .showSafeZone,
      isFalse,
    );
  });
  test('safe zone fill persists, migrates to full and validates range', () {
    final s = ProtoplaneSettings();
    expect(s.safeZoneFill, 1);
    s.safeZoneFill = .65;
    final copy = ProtoplaneSettings()..load(s.toJson());
    expect(copy.safeZoneFill, .65);
    copy.load(s.toJson()..remove('safeZoneFill'));
    expect(copy.safeZoneFill, 1);
    for (final bad in [.49, 1.01, double.nan, 'half']) {
      expect(
        () => copy.load({...s.toJson(), 'safeZoneFill': bad}),
        throwsFormatException,
      );
    }
  });
  for (final size in [
    const Size(390, 844),
    const Size(844, 390),
    const Size(1100, 800),
  ]) {
    for (final wall in [false, true]) {
      test('full focus fills asymmetric safe zone at $size wall=$wall', () {
        final plane = CraftPlane(
          id: 'test',
          origin: Vector3.zero(),
          u: Vector3(1, 0, 0),
          v: wall ? Vector3(0, 1, 0) : Vector3(0, 0, -1),
          region: rectangle(2, 1),
          grids: [],
        );
        final camera = Camera(
          name: 'test',
          position: Vector3(4, 5, 6),
          target: Vector3.zero(),
        );
        final zone = Rect.fromLTRB(70, 88, size.width - 125, size.height - 120);
        final pose = focusPlanePose(
          camera,
          plane,
          size,
          fullFocus: true,
          contextTiles: 4,
          safeZone: zone,
        );
        camera.setPosition(pose.position);
        camera.setTarget(pose.target);
        camera.setUp(pose.up);
        camera.fovDegrees = pose.fov;
        final points = plane.region.outer
            .map((p) => camera.projectToScreen(plane.point(p), size)!)
            .toList();
        var bounds = Rect.fromPoints(points.first, points.first);
        for (final p in points) {
          bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
        }
        expect(bounds.left, greaterThanOrEqualTo(zone.left - 1e-5));
        expect(bounds.right, lessThanOrEqualTo(zone.right + 1e-5));
        expect(bounds.top, greaterThanOrEqualTo(zone.top - 1e-5));
        expect(bounds.bottom, lessThanOrEqualTo(zone.bottom + 1e-5));
        expect((bounds.center - zone.center).distance, lessThan(1e-5));
        expect(
          (bounds.width - zone.width).abs() < 1e-5 ||
              (bounds.height - zone.height).abs() < 1e-5,
          isTrue,
        );
        for (final fill in [.5, .75]) {
          final fitted = focusPlanePose(
            camera,
            plane,
            size,
            fullFocus: true,
            contextTiles: 4,
            safeZone: zone,
            safeZoneFill: fill,
          );
          final reduced = Camera(
            name: 'reduced',
            position: fitted.position,
            target: fitted.target,
            up: fitted.up,
            fovDegrees: fitted.fov,
          );
          final projected = plane.region.outer
              .map((p) => reduced.projectToScreen(plane.point(p), size)!)
              .toList();
          var smaller = Rect.fromPoints(projected.first, projected.first);
          for (final p in projected) {
            smaller = smaller.expandToInclude(Rect.fromPoints(p, p));
          }
          expect(smaller.width, closeTo(bounds.width * fill, 1e-5));
          expect(smaller.height, closeTo(bounds.height * fill, 1e-5));
          expect((smaller.center - zone.center).distance, lessThan(1e-5));
          expect(fitted.up.dot(pose.up), closeTo(1, 1e-6));
        }
      });
    }
  }
}
