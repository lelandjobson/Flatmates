import 'package:flatmates/gameplay/flatmates/flatmate_movement.dart';
import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flatmates/gameplay/volumes/volume.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const grid = VolumeGrid(tilesSide: 16, tileSize: 8);
  const sitY = 1.0;

  const profile = MovementProfile(
    id: 'flourish',
    name: 'Flourish',
    offset: 0,
    jank: 0,
    smoothness: 0,
    bendSlowdown: 0,
    hopHeight: 0,
    tileSpeed: 2.5,
    startBackup: 0.2,
    startSeconds: 0.4,
    startTilt: 0.3,
    stopSlide: 0,
    stopSeconds: 0.4,
    stopTilt: 0.25,
  );

  FlatmateMovement openWalk({
    bool flourish = false,
    bool loop = false,
    MovementProfile? gait,
    Offset? startFrom,
  }) {
    return FlatmateMovement()
      ..start(
        const [(0, 0), (1, 0), (2, 0), (3, 0)],
        grid: grid,
        profile: gait ?? profile,
        flourish: flourish,
        loop: loop,
        startFrom: startFrom,
      );
  }

  void step(
    FlatmateMovement move, {
    required double dt,
    double tilesPerSecond = 10,
  }) {
    move.advance(
      dt: dt,
      baseTilesPerSecond: tilesPerSecond,
      onPath: (_, _) => false,
      grid: grid,
    );
  }

  test('requestStop keeps travel speed then snaps to the next tile', () {
    final move = openWalk();
    move.distance = 3;
    move.requestStop();
    expect(move.phase, MovementPhase.stopping);
    expect(move.stopDistance, closeTo(move.curve!.tileDistances[1], 1e-6));
    final target = move.stopDistance!;
    step(move, dt: 0.05);
    expect(move.distance, closeTo(7, 1e-6));
    expect(move.distance, lessThan(target - 1e-6));
    expect(move.phase, MovementPhase.stopping);
    step(move, dt: 1);
    expect(move.distance, closeTo(target, 1e-6));
    expect(move.phase, MovementPhase.settling);
  });

  test('already on a tile station stops at the tile after it', () {
    final move = openWalk();
    move.distance = move.curve!.tileDistances[1];
    move.requestStop();
    expect(move.stopDistance, closeTo(move.curve!.tileDistances[2], 1e-6));
  });

  test('requestStart does not change committed distance and overlays backup', () {
    final move = openWalk();
    move.progress = 0.4;
    final committed = move.distance;
    move.requestStop();
    while (move.phase != MovementPhase.idle) {
      step(move, dt: 0.05);
    }
    final parked = move.distance;
    expect(parked, isNot(committed));
    move.requestStart();
    expect(move.phase, MovementPhase.starting);
    expect(move.distance, closeTo(parked, 1e-9));
    step(move, dt: profile.startSeconds / 2);
    expect(move.distance, closeTo(parked, 1e-9));
    expect(move.overlayAlong, lessThan(0));
    expect(move.pitch, greaterThan(0));
    final start = grid.tileCenter(0, 0);
    final pos = move.worldPosition(grid, sitY);
    expect(pos.x, lessThan(start.x + parked));
    step(move, dt: profile.startSeconds);
    expect(move.distance, closeTo(parked, 1e-9));
    expect(move.overlayAlong, 0);
    expect(move.pitch, 0);
    expect(move.phase, MovementPhase.moving);
  });

  test('start flourish begins from the supplied world point', () {
    const from = Offset(1.5, 3);
    final move = openWalk(flourish: true, startFrom: from);
    expect(move.phase, MovementPhase.starting);
    expect(move.distance, 0);
    final first = move.worldPosition(grid, sitY);
    expect(first.x, closeTo(from.dx, 1e-6));
    expect(first.z, closeTo(from.dy, 1e-6));
    step(move, dt: profile.startSeconds / 2);
    expect(move.distance, 0);
    expect(move.overlayAlong, lessThan(0));
    expect(move.pitch, greaterThan(0));
    step(move, dt: profile.startSeconds);
    expect(move.phase, MovementPhase.moving);
    expect(move.overlayAlong, 0);
    final landed = move.worldPosition(grid, sitY);
    final onCurve = move.curve!.pointAtDistance(move.distance);
    expect(landed.x, closeTo(onCurve.dx, 1e-6));
    expect(landed.z, closeTo(onCurve.dy, 1e-6));
  });

  test('settle leans back without overshooting the dest', () {
    final move = openWalk();
    move.distance = 3;
    move.requestStop();
    while (move.phase != MovementPhase.settling) {
      step(move, dt: 0.05);
    }
    step(move, dt: profile.stopSeconds / 2);
    expect(move.pitch, lessThan(0));
    expect(move.overlayAlong, 0);
    step(move, dt: profile.stopSeconds);
    expect(move.phase, MovementPhase.idle);
    expect(move.isMoving, isFalse);
    expect(move.overlayAlong, 0);
    expect(move.pitch, 0);
  });

  test('stopSlide 0 stays at dest through settle', () {
    final move = openWalk();
    move.distance = 3;
    move.requestStop();
    while (move.phase != MovementPhase.settling) {
      step(move, dt: 0.05);
    }
    final dest = move.curve!.offsetDest(1);
    final parked = move.worldPosition(grid, sitY);
    expect(parked.x, closeTo(dest.dx, 1e-4));
    expect(parked.z, closeTo(dest.dy, 1e-4));
    step(move, dt: profile.stopSeconds);
    final ended = move.worldPosition(grid, sitY);
    expect(ended.x, closeTo(dest.dx, 1e-4));
    expect(ended.z, closeTo(dest.dy, 1e-4));
  });

  test('stopSlide 1 eases from the shared-edge mid to offset dest', () {
    const slide = MovementProfile(
      id: 'slide-in',
      name: 'Slide in',
      offset: 0,
      jank: 0,
      smoothness: 0,
      bendSlowdown: 0,
      hopHeight: 0,
      tileSpeed: 2.5,
      stopSlide: 1,
      stopSeconds: 0.4,
      stopTilt: 0.25,
    );
    final move = openWalk(gait: slide);
    move.distance = 3;
    move.requestStop();
    while (move.phase != MovementPhase.settling) {
      step(move, dt: 0.05);
    }
    final edge = move.curve!.arrivalEdgeMid(1);
    final dest = move.curve!.offsetDest(1);
    final start = move.worldPosition(grid, sitY);
    expect(start.x, closeTo(edge.dx, 0.2));
    expect(start.z, closeTo(edge.dy, 0.2));
    expect(move.overlayAlong, 0);
    step(move, dt: slide.stopSeconds);
    expect(move.phase, MovementPhase.idle);
    final ended = move.worldPosition(grid, sitY);
    expect(ended.x, closeTo(dest.dx, 1e-4));
    expect(ended.z, closeTo(dest.dy, 1e-4));
    expect(ended.x, greaterThan(start.x));
  });

  test('open path settles on the last tile then is idle', () {
    final move = openWalk();
    move.progress = 0.99;
    step(move, dt: 1);
    expect(move.phase, MovementPhase.settling);
    expect(move.distance, closeTo(move.curve!.totalLength, 1e-6));
    expect(move.isMoving, isTrue);
    step(move, dt: 1);
    expect(move.phase, MovementPhase.idle);
    expect(move.isMoving, isFalse);
    expect(move.overlayAlong, 0);
    expect(move.pitch, 0);
    final dest = move.curve!.offsetDest(move.tiles.length - 1);
    final pos = move.worldPosition(grid, sitY);
    expect(pos.x, closeTo(dest.dx, 1e-4));
    expect(pos.z, closeTo(dest.dy, 1e-4));
  });

  test('start and stop requests are ignored in the wrong phase', () {
    final move = openWalk();
    expect(move.canRequestStart, isFalse);
    expect(move.canRequestStop, isTrue);
    move.requestStart();
    expect(move.phase, MovementPhase.moving);
    move.requestStop();
    expect(move.phase, MovementPhase.stopping);
    move.requestStop();
    expect(move.phase, MovementPhase.stopping);
    while (move.phase != MovementPhase.idle) {
      step(move, dt: 0.05);
    }
    expect(move.canRequestStart, isTrue);
    expect(move.canRequestStop, isFalse);
    move.requestStop();
    expect(move.phase, MovementPhase.idle);
  });
}
