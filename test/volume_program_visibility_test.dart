import 'package:flatmates/gameplay/picking/camera_rest_fade.dart';
import 'package:flatmates/gameplay/volumes/volume_program_visibility.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('volume alerts cover missing program and missing door', () {
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

  test('program selection drops when the floor closes or the tile leaves view',
      () {
    expect(
      keepProgramSelection(floorVisible: true, tileInView: true),
      isTrue,
    );
    expect(
      keepProgramSelection(floorVisible: false, tileInView: true),
      isFalse,
    );
    expect(
      keepProgramSelection(floorVisible: true, tileInView: false),
      isFalse,
    );
    expect(
      programTileOnScreen(
        screenX: 12,
        screenY: 20,
        viewportWidth: 400,
        viewportHeight: 300,
      ),
      isTrue,
    );
    expect(
      programTileOnScreen(
        screenX: -4,
        screenY: 20,
        viewportWidth: 400,
        viewportHeight: 300,
      ),
      isFalse,
    );
    expect(
      programTileOnScreen(
        screenX: 12,
        screenY: 20,
        viewportWidth: 0,
        viewportHeight: 0,
      ),
      isTrue,
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
