import 'package:flatmates/gameplay/paint/plane_shade_model.dart';
import 'package:flatmates/gameplay/viewers/world_plane.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

void main() {
  test('facing the light is brighter than facing away', () {
    const model = PlaneShadeModel(
      lightX: 0,
      lightY: -1,
      lightZ: 0,
      minShade: 0.4,
      maxShade: 1.0,
      tintStrength: 0,
    );
    expect(
      model.shadeAmount(VolumeFace.posY.worldNormal),
      closeTo(1.0, 0.001),
    );
    expect(
      model.shadeAmount(VolumeFace.negY.worldNormal),
      closeTo(0.4, 0.001),
    );
  });

  test('axis-aligned faces get distinct shades under diagonal light', () {
    const model = PlaneShadeModel(
      lightX: -0.4,
      lightY: -1,
      lightZ: -0.15,
      minShade: 0.3,
      maxShade: 1.0,
      tintStrength: 0,
    );
    final top = model.shadeAmount(VolumeFace.posY.worldNormal);
    final east = model.shadeAmount(VolumeFace.posX.worldNormal);
    final south = model.shadeAmount(VolumeFace.posZ.worldNormal);
    expect(top, greaterThan(east));
    expect(east, greaterThan(south));
  });

  test('apply mixes toward lit tint on the sunward face', () {
    const model = PlaneShadeModel(
      lightX: 0,
      lightY: -1,
      lightZ: 0,
      minShade: 1,
      maxShade: 1,
      litTint: Color(0xFFFFFF00),
      shadeTint: Color(0xFF0000FF),
      tintStrength: 1,
    );
    final top = model.apply(const Color(0xFFFFFFFF), Vector3(0, 1, 0));
    final bottom = model.apply(const Color(0xFFFFFFFF), Vector3(0, -1, 0));
    expect(top.g, greaterThan(top.b));
    expect(bottom.b, greaterThan(bottom.g));
  });

  test('zero light direction falls back to downward travel', () {
    const model = PlaneShadeModel(lightX: 0, lightY: 0, lightZ: 0);
    expect(model.facing(Vector3(0, 1, 0)), closeTo(1.0, 0.001));
    expect(model.facing(Vector3(0, -1, 0)), closeTo(0.0, 0.001));
  });
}
