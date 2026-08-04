import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../../animation/scene_animatables.dart';
import '../../rendering/mesh.dart';
import '../../rendering/scene/scene.dart';
import '../folded_geometry.dart';
import '../geometry.dart';

class CableClampLoader {
  CableClampLoader({
    required this.vsync,
    required this.unfoldDuration,
    this.assetPath = 'lib/obj/Cableclamp.obj',
    this.targetSpan = 220.0,
  });

  final TickerProvider vsync;
  final Duration unfoldDuration;
  final String assetPath;
  final double targetSpan;

  Future<CableClampLoadResult> load() async {
    final source = await rootBundle.loadString(assetPath);
    final foldedGeometry = FoldedGeometry.fromString(
      id: 'cableClamp',
      name: 'Cable Clamp',
      objSource: source,
    );
    final closedGeometry = ensureOutwardFacingGeometry(
      foldedGeometry.toGeometry(foldValue: 1),
    );
    final unfoldedGeometry = ensureOutwardFacingGeometry(
      foldedGeometry.toGeometry(foldValue: 0),
    );
    final transform = buildNormalizationTransform(
      closedGeometry,
      targetSpan: targetSpan,
    );
    final normalizedClosedGeometry = transform(closedGeometry);
    final normalizedUnfoldedGeometry = transform(unfoldedGeometry);
    final mesh =
        Mesh(
            id: 'cableClamp',
            name: 'Cable Clamp',
            geometry: normalizedClosedGeometry,
            material: const MaterialModel(
              color: Colors.amberAccent,
              doubleSided: true,
            ),
          )
          ..setPosition(Vector3(200, 0, -40))
          ..setRotation(Vector3(0, math.pi / 5, 0));
    final animatable = MeshUnfoldAnimatable(
      vsync: vsync,
      mesh: mesh,
      foldedGeometry: foldedGeometry,
      unfoldedGeometry: normalizedUnfoldedGeometry,
      duration: unfoldDuration,
      geometryMapper: transform,
    );
    return CableClampLoadResult(
      animatable: animatable,
      vertexCount: normalizedClosedGeometry.vertices.length,
      faceCount: normalizedClosedGeometry.faces.length,
    );
  }
}

class CableClampLoadResult {
  CableClampLoadResult({
    required this.animatable,
    required this.vertexCount,
    required this.faceCount,
  });

  final SceneAnimatable animatable;
  final int vertexCount;
  final int faceCount;
}
