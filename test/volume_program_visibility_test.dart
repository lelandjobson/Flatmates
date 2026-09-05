import 'package:flatmates/gameplay/picking/camera_rest_fade.dart';
import 'package:flatmates/gameplay/volumes/volume_program_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('volume alerts cover missing program and missing entry', () {
    expect(
      volumeAlerts(programmed: false, hasEntry: false),
      [VolumeAlertKind.unprogrammed, VolumeAlertKind.noEntry],
    );
    expect(
      volumeAlerts(programmed: true, hasEntry: false),
      [VolumeAlertKind.noEntry],
    );
    expect(
      volumeAlerts(programmed: false, hasEntry: true),
      [VolumeAlertKind.unprogrammed],
    );
    expect(volumeAlerts(programmed: true, hasEntry: true), isEmpty);
    expect(
      volumeAlerts(
        programmed: true,
        hasEntry: true,
        bedroomNeedsAccess: true,
      ),
      [VolumeAlertKind.bedroomAccess],
    );
  });

  test('mass HUD hides in create mode and when looking inside', () {
    expect(
      massProgramHudVisible(createMode: false, lookingInside: false),
      isTrue,
    );
    expect(
      massProgramHudVisible(createMode: true, lookingInside: false),
      isFalse,
    );
    expect(
      massProgramHudVisible(createMode: false, lookingInside: true),
      isFalse,
    );
  });

  test('floors are visible in interior viewers or when the ceiling is down', () {
    expect(
      volumeFloorVisible(interiorViewer: true, ceilingHidesFloor: true),
      isTrue,
    );
    expect(
      volumeFloorVisible(interiorViewer: false, ceilingHidesFloor: true),
      isFalse,
    );
    expect(
      volumeFloorVisible(interiorViewer: false, ceilingHidesFloor: false),
      isTrue,
    );
  });

  test('camera rest shows icons while moving and for 1s after rest', () {
    final fade = CameraRestFadeLogic(restMs: 100, holdMs: 1000);
    fade.cameraMoved();
    expect(fade.evaluateIdle(0), isTrue);
    expect(fade.evaluateIdle(500), isTrue);
    expect(fade.evaluateIdle(1099), isTrue);
    expect(fade.evaluateIdle(1100), isFalse);
    fade.cameraMoved();
    expect(fade.visible, isTrue);
    fade.alwaysOn = true;
    expect(fade.evaluateIdle(5000), isTrue);
  });
}
