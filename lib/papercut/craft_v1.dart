import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart';

/// Version-1 craft export from FlatmatesRh (`craft.json`).
class CraftV1 {
  const CraftV1({
    required this.version,
    required this.craft,
    required this.foldedModel,
    required this.steps,
    required this.faces,
    required this.edges,
    this.assetDirectory = '',
  });

  final int version;
  final String craft;
  final String foldedModel;
  final List<CraftV1Step> steps;
  final List<CraftV1Face> faces;
  final List<CraftV1Edge> edges;

  /// Bundle directory that holds [foldedModel], when loaded from assets.
  final String assetDirectory;

  String get foldedAsset =>
      assetDirectory.isEmpty ? foldedModel : '$assetDirectory/$foldedModel';

  List<int> get craftingSteps {
    final values = <int>{
      for (final face in faces) face.craftingStep,
      for (final edge in edges) edge.craftingStep,
      for (final step in steps) step.craftingStep,
    };
    final sorted = values.toList()..sort();
    return sorted;
  }

  factory CraftV1.fromJson(
    Map<String, dynamic> json, {
    String assetDirectory = '',
  }) {
    final stepsJson = json['steps'] as List? ?? const [];
    final facesJson = json['faces'] as List? ?? const [];
    final edgesJson = json['edges'] as List? ?? const [];
    return CraftV1(
      version: (json['version'] as num?)?.toInt() ?? 1,
      craft: json['craft'] as String? ?? 'craft',
      foldedModel: json['foldedModel'] as String? ?? 'folded.obj',
      steps: [
        for (final step in stepsJson)
          CraftV1Step.fromJson(step as Map<String, dynamic>),
      ],
      faces: [
        for (final face in facesJson)
          CraftV1Face.fromJson(face as Map<String, dynamic>),
      ],
      edges: [
        for (final edge in edgesJson)
          CraftV1Edge.fromJson(edge as Map<String, dynamic>),
      ],
      assetDirectory: assetDirectory,
    );
  }

  /// Loads every `assets/craft_viewer/*/craft.json` in the bundle.
  static Future<List<CraftV1>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where(
          (path) =>
              path.startsWith('assets/craft_viewer/') &&
              path.endsWith('/craft.json'),
        )
        .toList()
      ..sort();
    final crafts = <CraftV1>[];
    for (final path in paths) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        final directory = path.substring(0, path.lastIndexOf('/'));
        crafts.add(
          CraftV1.fromJson(
            jsonDecode(jsonStr) as Map<String, dynamic>,
            assetDirectory: directory,
          ),
        );
      } catch (error, stack) {
        debugPrint('[craft-v1] failed to load $path: $error\n$stack');
      }
    }
    return crafts;
  }
}

class CraftV1Step {
  const CraftV1Step({required this.craftingStep, required this.model});

  final int craftingStep;
  final String model;

  factory CraftV1Step.fromJson(Map<String, dynamic> json) {
    return CraftV1Step(
      craftingStep: (json['craftingStep'] as num?)?.toInt() ?? 0,
      model: json['model'] as String? ?? '',
    );
  }
}

class CraftV1Face {
  const CraftV1Face({
    required this.id,
    required this.craftingStep,
    required this.surfaceId,
    required this.pieceKey,
    required this.islandId,
    required this.layer,
    required this.flatLoops,
    required this.transform,
    this.foldParentSurfaceId,
  });

  final String id;
  final int craftingStep;
  final String surfaceId;
  final String? foldParentSurfaceId;
  final String pieceKey;
  final String islandId;
  final String layer;
  final List<List<Vector3>> flatLoops;
  final CraftV1Transform transform;

  String get islandKey => '$pieceKey|$islandId';

  factory CraftV1Face.fromJson(Map<String, dynamic> json) {
    final loopsJson = json['flatLoops'] as List? ?? const [];
    return CraftV1Face(
      id: json['id'] as String? ?? '',
      craftingStep: _stepOf(json),
      surfaceId: json['flatmates.surfaceId'] as String? ?? '',
      foldParentSurfaceId: json['flatmates.foldParentSurfaceId'] as String?,
      pieceKey: json['flatmates.pieceKey'] as String? ?? '',
      islandId: json['flatmates.islandId'] as String? ?? '',
      layer: json['flatmates.layer'] as String? ?? '',
      flatLoops: [
        for (final loop in loopsJson) _points(loop as List),
      ],
      transform: CraftV1Transform.fromJson(
        json['transform'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class CraftV1Edge {
  const CraftV1Edge({
    required this.role,
    required this.craftingStep,
    required this.curve,
    this.faceA,
    this.faceB,
  });

  final String role;
  final int craftingStep;
  final String? faceA;
  final String? faceB;
  final List<Vector3> curve;

  bool get isFold => role == 'fold';
  bool get isCut => role == 'cut';

  factory CraftV1Edge.fromJson(Map<String, dynamic> json) {
    return CraftV1Edge(
      role: json['flatmates.role'] as String? ?? '',
      craftingStep: _stepOf(json),
      faceA: json['faceA'] as String?,
      faceB: json['faceB'] as String?,
      curve: _points(json['curve'] as List? ?? const []),
    );
  }
}

sealed class CraftV1Transform {
  const CraftV1Transform();

  factory CraftV1Transform.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? '';
    if (type == 'movement') {
      return CraftV1Movement(_matrix(json['inverse']));
    }
    if (type == 'rotation') {
      final axis = _doubles(json['axis']);
      return CraftV1Rotation(
        axisStart: Vector3(
          axis.isNotEmpty ? axis[0] : 0,
          axis.length > 1 ? axis[1] : 0,
          axis.length > 2 ? axis[2] : 0,
        ),
        axisEnd: Vector3(
          axis.length > 3 ? axis[3] : 0,
          axis.length > 4 ? axis[4] : 0,
          axis.length > 5 ? axis[5] : 0,
        ),
        angleRadians: _angle(json['angleRadians']),
      );
    }
    return const CraftV1None();
  }
}

class CraftV1Movement extends CraftV1Transform {
  const CraftV1Movement(this.inverse);

  /// Row-major Rhino inverse, stored column-major for [Matrix4].
  final Matrix4 inverse;
}

class CraftV1Rotation extends CraftV1Transform {
  const CraftV1Rotation({
    required this.axisStart,
    required this.axisEnd,
    required this.angleRadians,
  });

  final Vector3 axisStart;
  final Vector3 axisEnd;
  final double angleRadians;
}

class CraftV1None extends CraftV1Transform {
  const CraftV1None();
}

int _stepOf(Map<String, dynamic> json) {
  final raw = json['flatmates.craftingStep'];
  if (raw is num) return raw.toInt();
  return int.tryParse(raw?.toString() ?? '') ?? 0;
}

List<Vector3> _points(List<dynamic> raw) {
  final points = <Vector3>[];
  for (final item in raw) {
    if (item is! List || item.length < 2) continue;
    points.add(
      Vector3(
        (item[0] as num).toDouble(),
        (item[1] as num).toDouble(),
        item.length > 2 ? (item[2] as num).toDouble() : 0,
      ),
    );
  }
  return points;
}

List<double> _doubles(Object? raw) {
  if (raw is! List) return const [];
  return [for (final value in raw) (value as num).toDouble()];
}

double _angle(Object? raw) {
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw?.toString() ?? '') ?? 0;
}

/// Rhino writes a row-major 4×4. [Matrix4] stores columns.
Matrix4 _matrix(Object? raw) {
  final values = _doubles(raw);
  if (values.length != 16) return Matrix4.identity();
  return Matrix4.zero()
    ..setValues(
      values[0],
      values[4],
      values[8],
      values[12],
      values[1],
      values[5],
      values[9],
      values[13],
      values[2],
      values[6],
      values[10],
      values[14],
      values[3],
      values[7],
      values[11],
      values[15],
    );
}
