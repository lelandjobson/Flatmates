import 'dart:convert';
import 'dart:io';

import 'package:flatmates/gameplay/flatmates/movement_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('JSON round-trips a custom profile', () {
    const original = MovementProfile(
      id: 'lane-right',
      name: 'Lane right',
      movementTileRatio: 1.5,
      offset: 0.4,
      jank: 0.2,
      jankIntensity: 0.3,
      smoothness: 0.8,
      bendSlowdown: 0.6,
      hopHeight: 0.7,
      tileSpeed: 3,
      startBackup: 0.2,
      startSeconds: 0.3,
      startTilt: 0.1,
      stopSlide: 0.25,
      stopSeconds: 0.4,
      stopTilt: 0.15,
      rotationInertia: 0.4,
    );
    final copy = MovementProfile.fromJson(original.toJson());
    expect(copy, original);
  });

  test('fromJson clamps out-of-range fields', () {
    final profile = MovementProfile.fromJson({
      'id': 'wild',
      'name': 'Wild',
      'movementTileRatio': 99,
      'offset': -2,
      'jank': 4,
      'smoothness': 2,
      'tileSpeed': 0.1,
      'startBackup': 9,
      'startSeconds': 0,
      'startTilt': 2,
      'stopSlide': 9,
      'stopSeconds': 0,
      'stopTilt': 2,
      'rotationInertia': 4,
    });
    expect(profile.movementTileRatio, 3);
    expect(profile.offset, 0);
    expect(profile.jank, 1);
    expect(profile.smoothness, 1);
    expect(profile.tileSpeed, 0.5);
    expect(profile.startBackup, 0.5);
    expect(profile.startSeconds, 0.05);
    expect(profile.startTilt, 0.45);
    expect(profile.stopSlide, 1);
    expect(profile.stopSeconds, 0.05);
    expect(profile.stopTilt, 0.45);
    expect(profile.rotationInertia, 1);
  });

  test('slug strips punctuation', () {
    expect(movementProfileSlug('Lane Right!'), 'lane-right');
    expect(movementProfileSlug('   '), 'profile');
  });

  test('byId falls back to hop', () {
    expect(MovementProfile.byId('slide'), MovementProfile.slide);
    expect(MovementProfile.byId('missing'), MovementProfile.hop);
  });

  test('bundled default.json parses', () {
    final file = File('assets/gameplay/movement_profiles/default.json');
    expect(file.existsSync(), isTrue);
    final profile = MovementProfile.fromJson(
      jsonDecode(file.readAsStringSync()) as Map<String, dynamic>,
    );
    expect(profile.id, 'default');
    expect(profile.movementTileRatio, 1);
  });
}
