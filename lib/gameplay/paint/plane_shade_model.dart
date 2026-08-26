import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

/// Orientation lighting for a painted AABB face.
///
/// The face normal is split into (x, y, z) and dotted with the negated
/// light-travel direction. That facing value is remapped to
/// [[minShade], [maxShade]] and used both to dim the paper color and to
/// mix it along a cool→warm tint gradient (shadow → light).
@immutable
class PlaneShadeModel {
  const PlaneShadeModel({
    this.lightX = -0.55,
    this.lightY = -1.0,
    this.lightZ = -0.35,
    this.minShade = 0.58,
    this.maxShade = 1.0,
    this.litTint = const Color(0xFFFFE08A),
    this.shadeTint = const Color(0xFF7A74B8),
    this.tintStrength = 0.28,
  });

  /// Light travels along this vector (same convention as [DirectionalLight]).
  final double lightX;
  final double lightY;
  final double lightZ;

  /// Brightness of a face pointing away from the light.
  final double minShade;

  /// Brightness of a face pointing into the light.
  final double maxShade;

  /// Mixed into faces that face the light.
  final Color litTint;

  /// Mixed into faces that face away from the light.
  final Color shadeTint;

  /// How far paper color moves toward [litTint] / [shadeTint] (0 = none).
  final double tintStrength;

  Vector3 get lightTravel => Vector3(lightX, lightY, lightZ);

  /// 0 = facing away from the light, 1 = facing into it.
  double facing(Vector3 normal) {
    final nx = normal.x;
    final ny = normal.y;
    final nz = normal.z;
    final nLen = math.sqrt(nx * nx + ny * ny + nz * nz);
    if (nLen < 1e-8) return 0.5;

    var lx = lightX;
    var ly = lightY;
    var lz = lightZ;
    final lLen = math.sqrt(lx * lx + ly * ly + lz * lz);
    if (lLen < 1e-8) {
      lx = 0;
      ly = -1;
      lz = 0;
    } else {
      lx /= lLen;
      ly /= lLen;
      lz /= lLen;
    }

    final inv = 1.0 / nLen;
    final lambert = (nx * inv) * -lx + (ny * inv) * -ly + (nz * inv) * -lz;
    return ((lambert + 1.0) * 0.5).clamp(0.0, 1.0);
  }

  /// Shade multiplier in [[minShade], [maxShade]].
  double shadeAmount(Vector3 normal) {
    final lo = math.min(minShade, maxShade).clamp(0.0, 1.0);
    final hi = math.max(minShade, maxShade).clamp(0.0, 1.0);
    return lo + (hi - lo) * facing(normal);
  }

  /// Tint along the cool→warm gradient for [normal].
  Color tintColor(Vector3 normal) {
    return Color.lerp(shadeTint, litTint, facing(normal))!;
  }

  /// Paper color after orientation shade + warm/cool mix.
  Color apply(Color paper, Vector3 normal) {
    final t = facing(normal);
    final lo = math.min(minShade, maxShade).clamp(0.0, 1.0);
    final hi = math.max(minShade, maxShade).clamp(0.0, 1.0);
    final shade = lo + (hi - lo) * t;
    final tint = Color.lerp(shadeTint, litTint, t)!;
    final mixed = Color.lerp(paper, tint, tintStrength.clamp(0.0, 1.0))!;
    return mixed.withValues(
      alpha: paper.a,
      red: (mixed.r * shade).clamp(0.0, 1.0),
      green: (mixed.g * shade).clamp(0.0, 1.0),
      blue: (mixed.b * shade).clamp(0.0, 1.0),
    );
  }

  PlaneShadeModel copyWith({
    double? lightX,
    double? lightY,
    double? lightZ,
    double? minShade,
    double? maxShade,
    Color? litTint,
    Color? shadeTint,
    double? tintStrength,
  }) {
    return PlaneShadeModel(
      lightX: lightX ?? this.lightX,
      lightY: lightY ?? this.lightY,
      lightZ: lightZ ?? this.lightZ,
      minShade: minShade ?? this.minShade,
      maxShade: maxShade ?? this.maxShade,
      litTint: litTint ?? this.litTint,
      shadeTint: shadeTint ?? this.shadeTint,
      tintStrength: tintStrength ?? this.tintStrength,
    );
  }

  static PlaneShadeModel lerp(PlaneShadeModel a, PlaneShadeModel b, double t) {
    final u = t.clamp(0.0, 1.0);
    return PlaneShadeModel(
      lightX: a.lightX + (b.lightX - a.lightX) * u,
      lightY: a.lightY + (b.lightY - a.lightY) * u,
      lightZ: a.lightZ + (b.lightZ - a.lightZ) * u,
      minShade: a.minShade + (b.minShade - a.minShade) * u,
      maxShade: a.maxShade + (b.maxShade - a.maxShade) * u,
      litTint: Color.lerp(a.litTint, b.litTint, u)!,
      shadeTint: Color.lerp(a.shadeTint, b.shadeTint, u)!,
      tintStrength: a.tintStrength + (b.tintStrength - a.tintStrength) * u,
    );
  }
}
