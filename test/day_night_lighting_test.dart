import 'package:flatmates/gameplay/day_night/day_night_lighting.dart';
import 'package:flatmates/gameplay/paint/plane_shade_model.dart';
import 'package:flatmates/theme/world_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('day lighting matches the paper diorama lamps', () {
    final day = DayNightLighting.day();
    expect(day.background, WorldTheme.paperDiorama.background);
    expect(day.globalIllumination, closeTo(0.7, 0.001));
    expect(day.keyIntensity, closeTo(0.25, 0.001));
    expect(day.fillIntensity, closeTo(0.3, 0.001));
    expect(day.shade.minShade, WorldTheme.paperDiorama.shade.minShade);
    expect(day.wash.a, 0);
    expect(day.lights, hasLength(2));
  });

  test('lerp endpoints are day and the chosen night', () {
    final day = DayNightLighting.day();
    final night = NightSwatch.invertedTwilight.lighting;
    final atDay = DayNightLighting.lerp(day, night, 0);
    final atNight = DayNightLighting.lerp(day, night, 1);

    expect(atDay.background, day.background);
    expect(atDay.globalIllumination, day.globalIllumination);
    expect(atDay.shade.litTint, day.shade.litTint);
    expect(atNight.background, night.background);
    expect(atNight.globalIllumination, night.globalIllumination);
    expect(atNight.shade.litTint, night.shade.litTint);
    expect(atNight.wash, night.wash);
  });

  test('mid lerp sits between day gold and night moonlight', () {
    final day = DayNightLighting.day();
    final night = NightSwatch.invertedTwilight.lighting;
    final mid = DayNightLighting.lerp(day, night, 0.5);
    expect(mid.keyIntensity, closeTo(0.40, 0.02));
    expect(mid.shade.minShade, lessThan(day.shade.minShade));
    expect(mid.shade.minShade, greaterThan(night.shade.minShade));
  });

  test('night swatches are unique twilight inversions, not black', () {
    final ids = NightSwatch.all.map((s) => s.id).toSet();
    expect(ids, hasLength(NightSwatch.all.length));
    expect(NightSwatch.byId('missing').id, NightSwatch.invertedTwilight.id);

    final dayLit = WorldTheme.paperDiorama.shade.litTint;
    for (final swatch in NightSwatch.all) {
      final night = swatch.lighting;
      expect(night.background.computeLuminance(), greaterThan(0.02));
      expect(night.shade.minShade, greaterThan(0.6));
      expect(night.shade.maxShade, greaterThan(0.85));
      expect(
        night.shade.litTint.b,
        greaterThan(night.shade.litTint.r),
        reason: '${swatch.id} moonlight should be cooler than warm',
      );
      expect(
        dayLit.r,
        greaterThan(dayLit.b),
        reason: 'day key stays gold',
      );
    }
  });

  test('night shade inverts paper tints: cool key, gold leftover', () {
    const day = WorldTheme.kPaperShade;
    final night = NightSwatch.invertedTwilight.lighting.shade;
    expect(day.litTint.r, greaterThan(day.litTint.b));
    expect(night.litTint.b, greaterThan(night.litTint.r));
    expect(night.shadeTint.r, greaterThan(night.shadeTint.b));
    expect(night.lightX, closeTo(-day.lightX, 0.001));
    expect(night.lightZ, closeTo(-day.lightZ, 0.001));
  });

  test('PlaneShadeModel.lerp blends tints and light', () {
    const a = PlaneShadeModel(
      lightX: 0,
      minShade: 0.2,
      litTint: Color(0xFFFFFFFF),
    );
    const b = PlaneShadeModel(
      lightX: 1,
      minShade: 0.8,
      litTint: Color(0xFF000000),
    );
    final mid = PlaneShadeModel.lerp(a, b, 0.5);
    expect(mid.lightX, closeTo(0.5, 0.001));
    expect(mid.minShade, closeTo(0.5, 0.001));
    expect(mid.litTint.r, closeTo(0.5, 0.02));
  });

  test('copyWith raises ambient without mutating the day lamps', () {
    final day = DayNightLighting.day();
    final lifted = day.copyWith(globalIllumination: 0.85);
    expect(day.globalIllumination, closeTo(0.7, 0.001));
    expect(lifted.globalIllumination, closeTo(0.85, 0.001));
    expect(lifted.keyIntensity, day.keyIntensity);
    expect(lifted.keyDirection.x, day.keyDirection.x);
  });
}
