import 'dart:math' as math;

import 'package:flatmates/gridcraft/scissor_glyph.dart';
import 'package:flatmates/gridcraft/tool_animation.dart';
import 'package:flatmates/gridcraft/tool_flight.dart';
import 'package:flatmates/papercut/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const heading = Offset(0, 1);
  const anchor = Offset(10, 20);
  const reach = 2.0;

  ToolCue cueAt(Offset aim, {Offset at = anchor}) {
    return ToolCue(
      anchor: at,
      direction: heading,
      aim: aim,
      reach: reach,
    );
  }

  test('arrive starts off the anchor along the perpendicular and eases on', () {
    const viewport = Size(800, 600);
    const screenAnchor = Offset(100, 300);
    final approach = approachFor(
      anchor: screenAnchor,
      heading: heading,
      viewport: viewport,
    );
    final cue = cueAt(anchor);
    final start = sampleArrive(
      t: 0,
      cue: cue,
      distance: approach.distance,
      sign: approach.sign,
    );
    final end = sampleArrive(
      t: 1,
      cue: cue,
      distance: approach.distance,
      sign: approach.sign,
    );

    expect(start.tip, anchor);
    expect(end.tip, anchor);
    expect(start.lateral.abs(), greaterThan(140));
    expect(end.lateral.abs(), lessThan(1e-6));

    final offset = lateralOffset(heading, start.lateral);
    final along = offset.dx * heading.dx + offset.dy * heading.dy;
    expect(along.abs(), lessThan(1e-6));
    expect(offset.distance, closeTo(start.lateral.abs(), 1e-6));
    expect(offset.dx.isNegative, isTrue);

    for (final t in [0.0, 0.35, 0.7, 1.0]) {
      final roll = sampleArrive(
        t: t,
        cue: cue,
        distance: approach.distance,
        sign: approach.sign,
      ).roll.abs();
      expect(roll, lessThanOrEqualTo(kArriveRoll + 1e-9));
      expect(roll, lessThanOrEqualTo(kMaxRoll + 1e-9));
    }
  });

  test('aim drift rolls a seated tool and leaves the tip on the snap', () {
    final parked = sampleHold(cue: cueAt(anchor), sign: 1);
    final drifted = sampleHold(
      cue: cueAt(anchor + const Offset(-reach, 0)),
      sign: 1,
    );
    expect(parked.tip, anchor);
    expect(drifted.tip, anchor);
    expect(drifted.lateral, 0);
    expect(drifted.roll, isNot(closeTo(parked.roll, 1e-6)));
    expect(drifted.roll.abs(), lessThanOrEqualTo(kMaxRoll + 1e-9));
  });

  test('a new snap changes the tip target', () {
    const next = ToolCue(
      anchor: Offset(4, 1),
      direction: Offset(0, 1),
      aim: Offset(4, 1),
      reach: 1,
    );
    const from = ToolPose(
      tip: anchor,
      direction: heading,
      roll: kRestRoll,
      open: kBladeOpen,
      lateral: 0,
      visible: 1,
    );
    expect(
      sampleRelocate(t: 0, from: from, to: next, sign: 1).tip,
      anchor,
    );
    expect(
      sampleRelocate(t: 1, from: from, to: next, sign: 1).tip,
      next.anchor,
    );

    final flight = ToolFlight();
    flight.offer(
      cueAt(anchor),
      t: 0,
      approach: const ScreenApproach(sign: 1, distance: 400),
    );
    flight.land();
    final duration = flight.offer(
      next,
      t: 0,
      approach: const ScreenApproach(sign: 1, distance: 400),
    );
    expect(duration, kRelocateDuration);
    expect(flight.pose(1).tip, next.anchor);
  });

  test('an invalid cue leaves and ends hidden', () {
    final flight = ToolFlight();
    const approach = ScreenApproach(sign: 1, distance: 480);
    flight.offer(cueAt(anchor), t: 0, approach: approach);
    flight.land();
    expect(flight.offer(null, t: 0, approach: approach), kLeaveDuration);
    expect(flight.pose(0).visible, 1);
    expect(flight.pose(1).visible, 0);
    expect(flight.pose(1).lateral.abs(), greaterThan(0));
  });

  test('a cut travels the segment and closes the blades', () {
    const from = Offset(1, 0);
    const to = Offset(1, 6);
    final start = sampleCut(
      t: 0,
      from: from,
      to: to,
      direction: heading,
      fromRoll: kRestRoll,
      fromLateral: 0,
      fromOpen: kBladeOpen,
      sign: 1,
    );
    final end = sampleCut(
      t: 1,
      from: from,
      to: to,
      direction: heading,
      fromRoll: kRestRoll,
      fromLateral: 0,
      fromOpen: kBladeOpen,
      sign: 1,
    );
    expect(start.tip, from);
    expect(end.tip, to);
    expect(start.cutting, isTrue);
    expect(end.open, lessThan(start.open));
    expect(end.open, closeTo(kBladeClosed, 1e-9));
    expect(end.roll.abs(), lessThanOrEqualTo(kMaxRoll + 1e-9));
  });

  test('the first cut fades out and a continued march stays hidden', () {
    final opening = sampleCut(
      t: 0,
      from: anchor,
      to: anchor + heading * 4,
      direction: heading,
      fromRoll: kRestRoll,
      fromLateral: 0,
      fromOpen: kBladeOpen,
      sign: 1,
      present: true,
    );
    final finished = sampleCut(
      t: 1,
      from: anchor,
      to: anchor + heading * 4,
      direction: heading,
      fromRoll: kRestRoll,
      fromLateral: 0,
      fromOpen: kBladeOpen,
      sign: 1,
      present: true,
    );
    expect(opening.visible, closeTo(1, 1e-6));
    expect(finished.visible, closeTo(0, 1e-6));

    final flight = ToolFlight()..presented = false;
    flight.seat(cueAt(anchor));
    expect(flight.pose(0).visible, 0);
    flight.presented = true;
    expect(flight.pose(0).visible, closeTo(1, 1e-6));
  });

  testWidgets('the scissor glyph paints', (tester) async {
    final camera = PapercutCamera();
    const viewport = Size(800, 600);
    camera.frameSheet(viewport, sheetMm: 20, center: Offset.zero);
    final errors = <FlutterErrorDetails>[];
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      errors.add(details);
      previous?.call(details);
    };
    addTearDown(() => FlutterError.onError = previous);

    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: viewport.width,
          height: viewport.height,
          child: CustomPaint(
            painter: ScissorGlyphPainter(
              camera: camera,
              tool: ScissorToolAnimation(),
              pose: const ToolPose(
                tip: Offset.zero,
                direction: Offset(0, 1),
                roll: kRestRoll,
                open: kBladeOpen,
                lateral: 40,
                visible: 1,
                cutting: true,
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(errors, isEmpty);
    expect(math.max(kArriveRoll, kRestRoll), lessThanOrEqualTo(kMaxRoll));
  });
}
