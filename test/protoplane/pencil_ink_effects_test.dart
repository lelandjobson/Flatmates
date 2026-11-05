import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import 'package:flatmates/protoplane/pencil.dart';
import 'package:flatmates/protoplane/pencil_rendering.dart';
import 'package:flatmates/protoplane/pencil_ink_effects.dart';
import 'package:flatmates/rendering/scene/camera.dart';
import 'pencil_test.dart' show paperWorld;

void main() {
  test(
    'graphite is stochastic but repeatable across reversal and subdivision',
    () {
      const line = PencilSegment(Offset.zero, Offset(4, 0));
      const reverse = PencilSegment(Offset(4, 0), Offset.zero);
      const part = PencilSegment(Offset(1, 0), Offset(2, 0));
      final a = graphiteSample(line, const Offset(1.37, 0));
      expect(graphiteSample(line, const Offset(1.37, 0)), a);
      final b = graphiteSample(reverse, const Offset(1.37, 0));
      final c = graphiteSample(part, const Offset(1.37, 0));
      expect(b, a);
      expect(c, a);
      var straight = 0, kinked = 0;
      final widths = <double>{}, opacity = <double>{};
      for (var i = 1; i < 800; i++) {
        final x = i * .005;
        final p = graphiteSample(line, Offset(x, 0));
        final left = graphiteSample(line, Offset(x - .005, 0)).$1.dy;
        final right = graphiteSample(line, Offset(x + .005, 0)).$1.dy;
        if ((left - right).abs() < 1e-9) straight++;
        if ((left + right - 2 * p.$1.dy).abs() > .00002) kinked++;
        widths.add(p.$3);
        opacity.add(p.$2);
        expect(p.$1.dy.abs(), lessThanOrEqualTo(.0015));
      }
      expect(straight, greaterThan(20));
      expect(kinked, greaterThan(20));
      expect(widths.length, greaterThan(100));
      expect(opacity.length, greaterThan(100));
    },
  );
  testWidgets(
    'grey stroke melts away and releases presentation state at 360ms',
    (tester) async {
      final model = paperWorld();
      addTearDown(model.dispose);
      final plane = model.activePlane!;
      final effects = PencilInkEffects(const TestVSync());
      addTearDown(effects.dispose);
      final camera = Camera(
        name: 'ink',
        position: plane.point(const Offset(.5, .5)) + plane.normal * 2,
        target: plane.point(const Offset(.5, .5)),
        up: Vector3(0, 0, -1),
        fovDegrees: 50,
      );
      const size = Size(300, 300);
      await tester.pumpWidget(
        MaterialApp(
          home: SizedBox(
            width: 300,
            height: 300,
            child: CustomPaint(painter: PencilInkPainter(effects, camera)),
          ),
        ),
      );
      final segments = [const PencilSegment(Offset(.25, .5), Offset(.75, .5))];
      Future<int> coverage() async {
        final recorder = ui.PictureRecorder();
        PencilInkPainter(effects, camera).paint(Canvas(recorder), size);
        final picture = recorder.endRecording();
        final count = await tester.runAsync(() async {
          final image = await picture.toImage(300, 300);
          final data = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!.buffer.asUint8List();
          var count = 0;
          for (var i = 3; i < data.length; i += 4) {
            if (data[i] > 16) count++;
          }
          image.dispose();
          return count;
        });
        picture.dispose();
        return count!;
      }

      effects.play(plane, segments);
      segments.clear();
      await tester.pump();
      final initial = await coverage();
      expect(initial, greaterThan(100));
      await tester.pump(const Duration(milliseconds: 180));
      final melting = await coverage();
      expect(melting, greaterThan(0));
      expect(melting, lessThan(initial));
      await tester.pump(const Duration(milliseconds: 180));
      expect(effects.activeCount, 0);
      expect(await coverage(), 0);
      effects.play(plane, [
        const PencilSegment(Offset(.25, .5), Offset(.75, .5)),
      ]);
      effects.clear();
      expect(effects.activeCount, 0);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
