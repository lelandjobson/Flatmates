import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../rendering/lights.dart';
import '../../theme/world_theme.dart';
import '../paint/ground_shadow_model.dart';
import '../paint/plane_shade_model.dart';

/// One resolved lighting look: scene lamps, face shade, ground shadow, sky.
@immutable
class DayNightLighting {
  const DayNightLighting({
    required this.background,
    required this.globalIllumination,
    required this.shade,
    required this.shadow,
    required this.keyColor,
    required this.keyIntensity,
    required this.keyDirection,
    required this.fillColor,
    required this.fillIntensity,
    required this.fillDirection,
    this.wash = const Color(0x00000000),
  });

  final Color background;
  final double globalIllumination;
  final PlaneShadeModel shade;
  final GroundShadowModel shadow;
  final Color keyColor;
  final double keyIntensity;
  final Vector3 keyDirection;
  final Color fillColor;
  final double fillIntensity;
  final Vector3 fillDirection;

  /// Soft multiply wash over the 3D viewport. Transparent at day.
  final Color wash;

  static final Vector3 kDayKeyDir = Vector3(-0.6, -1, -0.4);
  static final Vector3 kDayFillDir = Vector3(0.4, -0.5, 0.6);

  /// Paper-diorama daylight — matches the GameView lamps we ship with.
  factory DayNightLighting.day([WorldTheme theme = WorldTheme.paperDiorama]) {
    return DayNightLighting(
      background: theme.background,
      globalIllumination: 0.7,
      shade: theme.shade,
      shadow: GroundShadowModel(
        lightX: theme.shade.lightX,
        lightY: theme.shade.lightY,
        lightZ: theme.shade.lightZ,
      ),
      keyColor: const Color(0xFFFFFFFF),
      keyIntensity: 0.25,
      keyDirection: Vector3.copy(kDayKeyDir),
      fillColor: const Color(0xB3FFFFFF),
      fillIntensity: 0.3,
      fillDirection: Vector3.copy(kDayFillDir),
    );
  }

  List<DirectionalLight> get lights => [
        DirectionalLight(
          color: keyColor,
          intensity: keyIntensity,
          direction: Vector3.copy(keyDirection),
        ),
        DirectionalLight(
          color: fillColor,
          intensity: fillIntensity,
          direction: Vector3.copy(fillDirection),
        ),
      ];

  DayNightLighting copyWith({
    Color? background,
    double? globalIllumination,
    PlaneShadeModel? shade,
    GroundShadowModel? shadow,
    Color? keyColor,
    double? keyIntensity,
    Vector3? keyDirection,
    Color? fillColor,
    double? fillIntensity,
    Vector3? fillDirection,
    Color? wash,
  }) {
    return DayNightLighting(
      background: background ?? this.background,
      globalIllumination: globalIllumination ?? this.globalIllumination,
      shade: shade ?? this.shade,
      shadow: shadow ?? this.shadow,
      keyColor: keyColor ?? this.keyColor,
      keyIntensity: keyIntensity ?? this.keyIntensity,
      keyDirection: Vector3.copy(keyDirection ?? this.keyDirection),
      fillColor: fillColor ?? this.fillColor,
      fillIntensity: fillIntensity ?? this.fillIntensity,
      fillDirection: Vector3.copy(fillDirection ?? this.fillDirection),
      wash: wash ?? this.wash,
    );
  }

  static DayNightLighting lerp(
    DayNightLighting a,
    DayNightLighting b,
    double t,
  ) {
    final u = t.clamp(0.0, 1.0);
    return DayNightLighting(
      background: Color.lerp(a.background, b.background, u)!,
      globalIllumination:
          a.globalIllumination + (b.globalIllumination - a.globalIllumination) * u,
      shade: PlaneShadeModel.lerp(a.shade, b.shade, u),
      shadow: GroundShadowModel.lerp(a.shadow, b.shadow, u),
      keyColor: Color.lerp(a.keyColor, b.keyColor, u)!,
      keyIntensity: a.keyIntensity + (b.keyIntensity - a.keyIntensity) * u,
      keyDirection: _lerpVec(a.keyDirection, b.keyDirection, u),
      fillColor: Color.lerp(a.fillColor, b.fillColor, u)!,
      fillIntensity: a.fillIntensity + (b.fillIntensity - a.fillIntensity) * u,
      fillDirection: _lerpVec(a.fillDirection, b.fillDirection, u),
      wash: Color.lerp(a.wash, b.wash, u)!,
    );
  }

  static Vector3 _lerpVec(Vector3 a, Vector3 b, double t) {
    return Vector3(
      a.x + (b.x - a.x) * t,
      a.y + (b.y - a.y) * t,
      a.z + (b.z - a.z) * t,
    );
  }
}

/// Named twilight recipe. Days stay on [DayNightLighting.day]; nights pick one
/// of these. They are inversions of paper shade: cool moon on the lit side,
/// leftover gold in the shade, never pitch-black.
@immutable
class NightSwatch {
  const NightSwatch({
    required this.id,
    required this.label,
    required this.lighting,
  });

  final String id;
  final String label;
  final DayNightLighting lighting;

  /// Hue-rotated paper shade: gold key becomes moonlight, cool shade becomes
  /// warm leftover. Default pick.
  static final NightSwatch invertedTwilight = NightSwatch(
    id: 'inverted_twilight',
    label: 'Inverted twilight',
    lighting: DayNightLighting(
      background: const Color(0xFF2A3048),
      globalIllumination: 0.20,
      shade: const PlaneShadeModel(
        lightX: 0.55,
        lightY: -1.0,
        lightZ: 0.35,
        minShade: 0.70,
        maxShade: 0.94,
        litTint: Color(0xFFB8C4F0),
        shadeTint: Color(0xFFE6C8A0),
        tintStrength: 0.22,
      ),
      shadow: const GroundShadowModel(
        lightX: 0.55,
        lightY: -1.0,
        lightZ: 0.35,
        opacity: 0.30,
        color: Color(0xFF1A1630),
      ),
      keyColor: const Color(0xFFC8D0F8),
      keyIntensity: 0.55,
      keyDirection: Vector3(0.6, -1, 0.4),
      fillColor: const Color(0xFFE8C878),
      fillIntensity: 0.22,
      fillDirection: Vector3(-0.4, -0.45, -0.5),
      wash: const Color(0x2E3A2A68),
    ),
  );

  /// Deeper indigo with a thin gold rim. Cooler than [invertedTwilight].
  static final NightSwatch indigoGold = NightSwatch(
    id: 'indigo_gold',
    label: 'Indigo gold',
    lighting: DayNightLighting(
      background: const Color(0xFF243048),
      globalIllumination: 0.18,
      shade: const PlaneShadeModel(
        lightX: 0.45,
        lightY: -1.0,
        lightZ: 0.50,
        minShade: 0.66,
        maxShade: 0.92,
        litTint: Color(0xFF8EB0E8),
        shadeTint: Color(0xFFF0C060),
        tintStrength: 0.20,
      ),
      shadow: const GroundShadowModel(
        lightX: 0.45,
        lightY: -1.0,
        lightZ: 0.50,
        opacity: 0.34,
        color: Color(0xFF101828),
      ),
      keyColor: const Color(0xFFA8C4F0),
      keyIntensity: 0.48,
      keyDirection: Vector3(0.5, -1, 0.45),
      fillColor: const Color(0xFFF0C060),
      fillIntensity: 0.20,
      fillDirection: Vector3(-0.35, -0.4, -0.55),
      wash: const Color(0x331A2848),
    ),
  );

  /// Magenta-violet dusk, champagne accents.
  static final NightSwatch violetHour = NightSwatch(
    id: 'violet_hour',
    label: 'Violet hour',
    lighting: DayNightLighting(
      background: const Color(0xFF32203C),
      globalIllumination: 0.19,
      shade: const PlaneShadeModel(
        lightX: 0.35,
        lightY: -1.0,
        lightZ: 0.55,
        minShade: 0.68,
        maxShade: 0.93,
        litTint: Color(0xFFD0B8F0),
        shadeTint: Color(0xFFFFD27A),
        tintStrength: 0.24,
      ),
      shadow: const GroundShadowModel(
        lightX: 0.35,
        lightY: -1.0,
        lightZ: 0.55,
        opacity: 0.32,
        color: Color(0xFF1C1028),
      ),
      keyColor: const Color(0xFFE0C8FF),
      keyIntensity: 0.50,
      keyDirection: Vector3(0.4, -1, 0.5),
      fillColor: const Color(0xFFFFD27A),
      fillIntensity: 0.26,
      fillDirection: Vector3(-0.45, -0.4, -0.4),
      wash: const Color(0x295A2080),
    ),
  );

  /// Softest night — still paper, just dusk. Highest floor brightness.
  static final NightSwatch lavenderPaper = NightSwatch(
    id: 'lavender_paper',
    label: 'Lavender paper',
    lighting: DayNightLighting(
      background: const Color(0xFF3E3A52),
      globalIllumination: 0.22,
      shade: const PlaneShadeModel(
        lightX: 0.50,
        lightY: -1.0,
        lightZ: 0.28,
        minShade: 0.76,
        maxShade: 0.96,
        litTint: Color(0xFFD4CCF0),
        shadeTint: Color(0xFFF5E6B8),
        tintStrength: 0.16,
      ),
      shadow: const GroundShadowModel(
        lightX: 0.50,
        lightY: -1.0,
        lightZ: 0.28,
        opacity: 0.26,
        color: Color(0xFF242030),
      ),
      keyColor: const Color(0xFFE8E0F8),
      keyIntensity: 0.62,
      keyDirection: Vector3(0.55, -1, 0.3),
      fillColor: const Color(0xFFF5E6B8),
      fillIntensity: 0.18,
      fillDirection: Vector3(-0.35, -0.5, -0.45),
      wash: const Color(0x1F5A4A78),
    ),
  );

  static final List<NightSwatch> all = [
    invertedTwilight,
    indigoGold,
    violetHour,
    lavenderPaper,
  ];

  static NightSwatch byId(String id) {
    return all.firstWhere((s) => s.id == id, orElse: () => invertedTwilight);
  }
}
