import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import 'blueprint_set.dart';
import 'crafting_blueprint.dart';

/// v9 flatpipeline craft manifest (`craft.json`).
class CraftManifest {
  const CraftManifest({
    required this.version,
    required this.craft,
    required this.steps,
    this.volumes = const [],
  });

  final int version;
  final String craft;
  final List<CraftStep> steps;
  final List<CraftVolume> volumes;

  factory CraftManifest.fromJson(Map<String, dynamic> json) {
    final stepsJson = json['steps'] as List? ?? const [];
    final volumesJson = json['volumes'] as List? ?? const [];
    return CraftManifest(
      version: (json['version'] as num?)?.toInt() ?? 9,
      craft: json['craft'] as String? ?? 'craft',
      steps: [
        for (final s in stepsJson) CraftStep.fromJson(s as Map<String, dynamic>),
      ],
      volumes: [
        for (final v in volumesJson)
          CraftVolume.fromJson(v as Map<String, dynamic>),
      ],
    );
  }

  /// Loads every `assets/crafting_blueprints/*/craft.json` in the bundle.
  static Future<List<CraftManifest>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where(
          (p) =>
              p.startsWith('assets/crafting_blueprints/') &&
              p.endsWith('/craft.json'),
        )
        .toList();

    final crafts = <CraftManifest>[];
    for (final path in paths) {
      try {
        final jsonStr = await rootBundle.loadString(path);
        crafts.add(
          CraftManifest.fromJson(jsonDecode(jsonStr) as Map<String, dynamic>),
        );
      } catch (e, st) {
        debugPrint('[craft] failed to load $path: $e\n$st');
      }
    }
    return crafts;
  }

  int maxQLayer(CraftStep step) {
    if (step.appliques.isEmpty) return -1;
    return step.appliques.map((a) => a.qLayer).reduce((a, b) => a > b ? a : b);
  }

  /// One fill blueprint per navigation beat: parts, then each qLayer.
  List<CraftingBlueprint> toFillBlueprints() {
    final result = <CraftingBlueprint>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      result.add(_partsBlueprint(i, step));
      final maxQ = maxQLayer(step);
      for (var q = 0; q <= maxQ; q++) {
        result.add(_appliqueBlueprint(i, step, q));
      }
    }
    return result;
  }

  BlueprintSet toBlueprintSet() {
    final nav = <BlueprintStep>[];
    for (var i = 0; i < steps.length; i++) {
      final step = steps[i];
      nav.add(
        BlueprintStep(
          craft: craft,
          stepIndex: i,
          logicalIndex: step.index,
          kind: BlueprintStepKind.parts,
          label: 'Step ${step.index}',
          iconCodePoint: 0xe87e,
        ),
      );
      final maxQ = maxQLayer(step);
      for (var q = 0; q <= maxQ; q++) {
        nav.add(
          BlueprintStep(
            craft: craft,
            stepIndex: i,
            logicalIndex: step.index,
            kind: BlueprintStepKind.applique,
            qLayer: q,
            label: 'Step ${step.index} applique ${q + 1}',
            iconCodePoint: 0xe3c9,
          ),
        );
      }
    }
    return BlueprintSet(name: craft, steps: nav);
  }

  CraftingBlueprint _partsBlueprint(int stepIndex, CraftStep step) {
    final islands = <CraftingIsland>[
      for (final part in step.parts)
        for (final island in part.islands) island,
    ];
    return CraftingBlueprint(
      version: version,
      craft: craft,
      stepIndex: stepIndex,
      logicalIndex: step.index,
      kind: BlueprintStepKind.parts,
      islands: islands,
      coordinateSpace: BlueprintCoordinateSpace.craftUnits,
    );
  }

  CraftingBlueprint _appliqueBlueprint(int stepIndex, CraftStep step, int qLayer) {
    final islands = <CraftingIsland>[
      for (final part in step.parts)
        for (final island in part.islands) island,
    ];
    final atLayer = step.appliques.where((a) => a.qLayer == qLayer).toList();
    return CraftingBlueprint(
      version: version,
      craft: craft,
      stepIndex: stepIndex,
      logicalIndex: step.index,
      kind: BlueprintStepKind.applique,
      qLayer: qLayer,
      islands: islands,
      appliqueSurfaces: [for (final a in atLayer) ...a.surfaces],
      appliqueCurves: [for (final a in atLayer) a.curves],
      coordinateSpace: BlueprintCoordinateSpace.craftUnits,
    );
  }
}

class CraftStep {
  const CraftStep({
    required this.index,
    required this.name,
    required this.model,
    required this.isolationGroup,
    required this.bboxMin,
    required this.bboxMax,
    required this.stepOffset,
    required this.parts,
    required this.appliques,
  });

  final int index;
  final String name;
  final String model;
  final String? isolationGroup;
  final List<double> bboxMin;
  final List<double> bboxMax;
  final Vector3 stepOffset;
  final List<CraftPart> parts;
  final List<CraftApplique> appliques;

  factory CraftStep.fromJson(Map<String, dynamic> json) {
    final bbox = json['bbox'] as Map<String, dynamic>? ?? const {};
    final min = (bbox['min'] as List?) ?? const [0, 0];
    final max = (bbox['max'] as List?) ?? const [0, 0];
    final offset = json['stepOffset'] as List? ?? const [0, 0, 0];
    return CraftStep(
      index: (json['index'] as num).toInt(),
      name: json['name'] as String? ?? '${json['index']}',
      model: json['model'] as String? ?? 'steps/${json['index']}.obj',
      isolationGroup: json['isolationGroup'] as String?,
      bboxMin: [(min[0] as num).toDouble(), (min[1] as num).toDouble()],
      bboxMax: [(max[0] as num).toDouble(), (max[1] as num).toDouble()],
      stepOffset: Vector3(
        (offset[0] as num).toDouble(),
        (offset[1] as num).toDouble(),
        (offset[2] as num).toDouble(),
      ),
      parts: [
        for (final p in json['parts'] as List? ?? const [])
          CraftPart.fromJson(p as Map<String, dynamic>),
      ],
      appliques: [
        for (final a in json['appliques'] as List? ?? const [])
          CraftApplique.fromJson(a as Map<String, dynamic>),
      ],
    );
  }
}

class CraftPart {
  const CraftPart({
    required this.id,
    required this.surfaceArea,
    required this.islands,
  });

  final int id;
  final double surfaceArea;
  final List<CraftingIsland> islands;

  factory CraftPart.fromJson(Map<String, dynamic> json) {
    return CraftPart(
      id: (json['id'] as num).toInt(),
      surfaceArea: (json['surfaceArea'] as num?)?.toDouble() ?? 0,
      islands: [
        for (final i in json['islands'] as List? ?? const [])
          CraftingIsland.fromJson(i as Map<String, dynamic>),
      ],
    );
  }
}

class CraftApplique {
  const CraftApplique({
    required this.qLayer,
    required this.partId,
    required this.faceIndex,
    required this.curves,
    required this.surfaces,
  });

  final int qLayer;
  final int partId;
  final int faceIndex;
  final List<Vector3> curves;
  final List<List<Vector3>> surfaces;

  factory CraftApplique.fromJson(Map<String, dynamic> json) {
    final surfaceId = json['surfaceId'] as Map<String, dynamic>? ?? const {};
    return CraftApplique(
      qLayer: (json['qLayer'] as num?)?.toInt() ?? 0,
      partId: (surfaceId['partId'] as num?)?.toInt() ?? 0,
      faceIndex: (surfaceId['faceIndex'] as num?)?.toInt() ?? 0,
      curves: _parseVec3List(json['curves'] as List? ?? const []),
      surfaces: [
        for (final ring in json['surfaces'] as List? ?? const [])
          _parseVec3List(ring as List),
      ],
    );
  }

  static List<Vector3> _parseVec3List(List json) {
    return [
      for (final v in json)
        Vector3(
          ((v as List)[0] as num).toDouble(),
          (v[1] as num).toDouble(),
          (v[2] as num).toDouble(),
        ),
    ];
  }
}

class CraftVolume {
  const CraftVolume({
    required this.name,
    required this.model,
    this.render = false,
  });

  final String name;
  final String model;
  final bool render;

  factory CraftVolume.fromJson(Map<String, dynamic> json) {
    return CraftVolume(
      name: json['name'] as String? ?? 'volume',
      model: json['model'] as String? ?? '',
      render: json['render'] as bool? ?? false,
    );
  }
}
