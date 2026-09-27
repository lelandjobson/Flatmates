import 'dart:io';
import 'dart:math' as math;

import 'package:flatmates/gridcraft/tool_animation.dart';
import 'package:flatmates/gridcraft/tool_animation_io.dart';
import 'package:flatmates/gridcraft/tool_flight.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a loop feature moves the scissor loop center', () {
    final tool = ScissorToolAnimation();
    expect(tool.loopCenter().dx, closeTo(-74, 1e-6));
    expect(tool.loopCenter().dy, closeTo(15, 1e-6));

    final moved = tool.withFeature('loopCenterX', -90) as ScissorToolAnimation;
    expect(moved.loopCenter().dx, closeTo(-90, 1e-6));
    expect(moved.loopCenter().dy, tool.loopCenter().dy);
    expect(tool.loopCenter().dx, closeTo(-74, 1e-6));
  });

  test('tool json round-trips and a missing file uses defaults', () async {
    final directory = await Directory.systemTemp.createTemp('tool-animations');
    addTearDown(() => directory.delete(recursive: true));
    final store = ToolAnimationStore(directory: directory);

    final missing = await store.load();
    final scissors = missing.whereType<ScissorToolAnimation>().single;
    expect(scissors.feature('pivotX'), closeTo(-36, 1e-6));
    expect(scissors.style.fill, kScissorStyle.fill);

    final edited = scissors
        .withFeature('loopSpread', 22)
        .withStyle(scissors.style.copyWith(strokeWidth: 3.5));
    await store.save([
      edited,
      missing.whereType<StraightEdgeToolAnimation>().single,
    ]);

    final loaded = await store.load();
    final again = loaded.whereType<ScissorToolAnimation>().single;
    expect(again.feature('loopSpread'), closeTo(22, 1e-6));
    expect(again.style.strokeWidth, closeTo(3.5, 1e-6));
    expect(again.style.fill, scissors.style.fill);
    expect(loaded.whereType<StraightEdgeToolAnimation>(), hasLength(1));
  });

  test('the start appearance is cocked and a cut ends parallel', () {
    final tool = ScissorToolAnimation();
    expect(tool.feature('startAngle'), closeTo(20, 1e-6));
    const parked = ToolPose(
      tip: Offset.zero,
      direction: Offset(0, 1),
      roll: kRestRoll,
      open: kBladeOpen,
      lateral: 0,
      visible: 1,
    );
    expect(toolYaw(tool, parked), closeTo(20 * math.pi / 180, 1e-6));

    const cutting = ToolPose(
      tip: Offset(0, 4),
      direction: Offset(0, 1),
      roll: kRestRoll,
      open: kBladeOpen,
      lateral: 0,
      visible: 1,
      cutting: true,
    );
    expect(toolYaw(tool, cutting).abs(), lessThan(1e-9));
  });

  test('roll scale matches cos and stays visible inside the cap', () {
    expect(rollFaceScale(0), closeTo(1, 1e-9));
    expect(rollFaceScale(kRestRoll), closeTo(math.cos(kRestRoll), 1e-9));
    expect(rollFaceScale(kArriveRoll), closeTo(math.cos(kArriveRoll), 1e-9));
    expect(rollFaceScale(kMaxRoll), closeTo(math.cos(kMaxRoll), 1e-9));
    expect(rollFaceScale(kMaxRoll), greaterThan(0.15));
    expect(rollFaceScale(kArriveRoll), greaterThan(0));
  });
}
