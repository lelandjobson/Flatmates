import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry.dart';
import '../geometry/obj_parser.dart';
import '../rendering/mesh.dart';
import 'craft_manifest.dart';

/// Per-step parts + applique meshes loaded from a v9 craft's step OBJs.
class CraftStepMeshes {
  CraftStepMeshes({
    required this.step,
    required this.parts,
    required this.appliques,
    required this.partColor,
  });

  final CraftStep step;
  final Mesh? parts;
  final Mesh? appliques;
  final Color partColor;

  Iterable<Mesh> get meshes sync* {
    if (parts != null) yield parts!;
    if (appliques != null) yield appliques!;
  }

  Iterable<Vector3> get vertices sync* {
    for (final mesh in meshes) {
      yield* mesh.geometry.vertices;
    }
  }
}

/// Loaded, assembly-centered step meshes for a single craft.
class CraftStepAssembly {
  CraftStepAssembly({required this.manifest, required this.steps});

  final CraftManifest manifest;
  final List<CraftStepMeshes> steps;

  static const appliqueColor = Color(0xFFFF66AA);

  static Color partColorForIndex(int index) {
    final hue = (index * 137.5) % 360;
    return HSLColor.fromAHSL(1, hue, 0.55, 0.5).toColor();
  }

  /// Loads `craft.json` + each step OBJ, then recenters the combined assembly.
  static Future<CraftStepAssembly> load(String craftName) async {
    final manifests = await CraftManifest.loadAll();
    final manifest = manifests
        .where((m) => m.craft.toLowerCase() == craftName.toLowerCase())
        .firstOrNull;
    if (manifest == null) {
      throw StateError('Craft "$craftName" not found.');
    }

    final loaded = <CraftStepMeshes>[];
    for (var i = 0; i < manifest.steps.length; i++) {
      final step = manifest.steps[i];
      final path = 'assets/models/${manifest.craft}/${step.model}';
      String source;
      try {
        source = await rootBundle.loadString(path);
      } catch (_) {
        loaded.add(
          CraftStepMeshes(
            step: step,
            parts: null,
            appliques: null,
            partColor: partColorForIndex(i),
          ),
        );
        continue;
      }

      final groups = ObjParser.parseGroups(
        id: '${manifest.craft}_step_${step.index}',
        source: source,
      );
      Mesh? parts;
      Mesh? appliques;
      final partColor = partColorForIndex(i);
      for (final entry in groups.entries) {
        final name = entry.key.toLowerCase();
        final isApplique = name.contains('applique');
        final mesh = Mesh(
          id: '${manifest.craft}_${step.index}_${entry.key}',
          name: entry.key,
          geometry: entry.value,
          material: MaterialModel(
            color: isApplique ? appliqueColor : partColor,
            doubleSided: true,
          ),
        );
        if (isApplique) {
          appliques = mesh;
        } else {
          parts = mesh;
        }
      }
      loaded.add(
        CraftStepMeshes(
          step: step,
          parts: parts,
          appliques: appliques,
          partColor: partColor,
        ),
      );
    }

    centerAssembly(loaded);
    return CraftStepAssembly(manifest: manifest, steps: loaded);
  }

  static void centerAssembly(List<CraftStepMeshes> steps) {
    final verts = <Vector3>[
      for (final step in steps) ...step.vertices,
    ];
    if (verts.isEmpty) return;
    var minX = verts.first.x, maxX = verts.first.x;
    var minY = verts.first.y, maxY = verts.first.y;
    var minZ = verts.first.z, maxZ = verts.first.z;
    for (final v in verts) {
      minX = math.min(minX, v.x);
      maxX = math.max(maxX, v.x);
      minY = math.min(minY, v.y);
      maxY = math.max(maxY, v.y);
      minZ = math.min(minZ, v.z);
      maxZ = math.max(maxZ, v.z);
    }
    final cx = (minX + maxX) / 2;
    final cy = (minY + maxY) / 2;
    final cz = (minZ + maxZ) / 2;
    for (final step in steps) {
      for (final mesh in step.meshes) {
        for (final v in mesh.geometry.vertices) {
          v.x -= cx;
          v.y -= cy;
          v.z -= cz;
        }
      }
    }
  }
}
