import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/services.dart';

import 'crafting_blueprint.dart';

/// A step within a blueprint set, referencing a specific blueprint by its
/// craft name + island index.
class BlueprintStep {
  const BlueprintStep({
    required this.craft,
    required this.island,
    this.label,
    this.iconCodePoint = 0xe87e, // default: build icon
    this.layoutOffset = Offset.zero,
    this.layoutRotationDeg = 0,
  });

  final String craft;
  final int island;
  final String? label;
  final int iconCodePoint;

  /// World-space translation applied when laying out this step in a group.
  final Offset layoutOffset;

  /// In-plane rotation (degrees) applied around the island centroid before offset.
  final double layoutRotationDeg;

  String get assetKey => island == 0 ? craft : '$craft#$island';
}

/// An ordered collection of blueprints to be completed in sequence.
class BlueprintSet {
  const BlueprintSet({
    required this.name,
    required this.steps,
    this.isGroup = false,
  });

  final String name;
  final List<BlueprintStep> steps;

  /// True when this set was loaded from a craft `group.json` (multi-island layout).
  final bool isGroup;

  /// Creates a single-step set from an existing blueprint.
  factory BlueprintSet.single(CraftingBlueprint blueprint) {
    return BlueprintSet(
      name: blueprint.displayName,
      steps: [
        BlueprintStep(
          craft: blueprint.craft,
          island: blueprint.island,
          label: blueprint.displayName,
        ),
      ],
    );
  }
}

/// One component entry inside a craft `group.json`.
class BlueprintGroupComponent {
  const BlueprintGroupComponent({
    required this.island,
    this.label,
    this.iconCodePoint,
    this.offset,
    this.rotationDeg = 0,
  });

  final int island;
  final String? label;
  final int? iconCodePoint;

  /// Optional layout offset in craft grid units (same space as blueprint verts).
  /// When null, [BlueprintGroupDef] auto-lays out components side-by-side.
  final Offset? offset;

  /// In-plane rotation in degrees around the island centroid.
  final double rotationDeg;

  factory BlueprintGroupComponent.fromJson(Map<String, dynamic> json) {
    Offset? offset;
    final raw = json['offset'];
    if (raw is List && raw.length >= 2) {
      offset = Offset((raw[0] as num).toDouble(), (raw[1] as num).toDouble());
    }
    return BlueprintGroupComponent(
      island: (json['island'] as num).toInt(),
      label: json['label'] as String?,
      iconCodePoint: (json['iconCodePoint'] as num?)?.toInt(),
      offset: offset,
      rotationDeg: (json['rotation'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Parsed craft-level group file (`assets/crafting_blueprints/{craft}/group.json`).
class BlueprintGroupDef {
  const BlueprintGroupDef({
    required this.name,
    required this.craftFolder,
    required this.components,
    this.spacing = 30.0,
  });

  final String name;

  /// Folder name under `assets/crafting_blueprints/` (e.g. `group05`).
  final String craftFolder;

  final List<BlueprintGroupComponent> components;

  /// Gap between auto-laid-out component bounding boxes, in craft grid units.
  final double spacing;

  factory BlueprintGroupDef.fromJson(
    Map<String, dynamic> json, {
    required String craftFolder,
  }) {
    final rawComponents = json['components'] as List? ?? const [];
    return BlueprintGroupDef(
      name: json['name'] as String? ?? craftFolder,
      craftFolder: craftFolder,
      spacing: (json['spacing'] as num?)?.toDouble() ?? 30.0,
      components: [
        for (final c in rawComponents)
          BlueprintGroupComponent.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  /// Loads every `assets/crafting_blueprints/*/group.json` present in the bundle.
  static Future<List<BlueprintGroupDef>> loadAll() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final paths = manifest
        .listAssets()
        .where(
          (p) =>
              p.startsWith('assets/crafting_blueprints/') &&
              p.endsWith('/group.json'),
        )
        .toList();

    final groups = <BlueprintGroupDef>[];
    for (final path in paths) {
      try {
        // assets/crafting_blueprints/{folder}/group.json
        final parts = path.split('/');
        if (parts.length < 4) continue;
        final folder = parts[parts.length - 2];
        final jsonStr = await rootBundle.loadString(path);
        final json = jsonDecode(jsonStr) as Map<String, dynamic>;
        groups.add(BlueprintGroupDef.fromJson(json, craftFolder: folder));
      } catch (_) {
        // Skip malformed group files.
      }
    }
    return groups;
  }

  /// Builds a [BlueprintSet] from this group, resolving islands against [blueprints].
  ///
  /// Components without an explicit [BlueprintGroupComponent.offset] are placed
  /// left-to-right using each island's unfolded AABB plus [spacing].
  BlueprintSet? toBlueprintSet(
    List<CraftingBlueprint> blueprints, {
    required double minorGridSpacing,
  }) {
    final craftBlueprints = blueprints
        .where((b) => b.craft.toLowerCase() == craftFolder.toLowerCase())
        .toList();
    if (craftBlueprints.isEmpty) return null;

    final craftName = craftBlueprints.first.craft;
    final steps = <BlueprintStep>[];
    var cursorX = 0.0;

    for (final component in components) {
      final bp = craftBlueprints
          .where((b) => b.island == component.island)
          .firstOrNull;
      if (bp == null) continue;

      final rotRad = component.rotationDeg * math.pi / 180;
      final Offset layoutOffset;
      if (component.offset != null) {
        layoutOffset = Offset(
          component.offset!.dx * minorGridSpacing,
          component.offset!.dy * minorGridSpacing,
        );
        final bounds = _unfoldedBounds(
          bp,
          minorGridSpacing,
          rotationRad: rotRad,
        );
        if (bounds != null) {
          cursorX = math.max(
            cursorX,
            layoutOffset.dx + bounds.width + spacing * minorGridSpacing,
          );
        }
      } else {
        final bounds = _unfoldedBounds(
          bp,
          minorGridSpacing,
          rotationRad: rotRad,
        );
        if (bounds == null) continue;
        // Place so the island's left edge sits at cursorX; vertically centered.
        layoutOffset = Offset(cursorX - bounds.left, -bounds.center.dy);
        cursorX += bounds.width + spacing * minorGridSpacing;
      }

      steps.add(
        BlueprintStep(
          craft: craftName,
          island: component.island,
          label: component.label ?? 'Island ${component.island}',
          iconCodePoint: component.iconCodePoint ?? 0xe87e,
          layoutOffset: layoutOffset,
          layoutRotationDeg: component.rotationDeg,
        ),
      );
    }

    if (steps.isEmpty) return null;
    return BlueprintSet(name: name, steps: steps, isGroup: true);
  }

  /// Scaled (and optionally rotated-around-centroid) AABB of an island.
  static Rect? _unfoldedBounds(
    CraftingBlueprint bp,
    double minorGridSpacing, {
    double rotationRad = 0,
  }) {
    final pts = <Offset>[];
    for (final node in bp.transformTree.nodes) {
      final verts = node.unfoldedPolygon2D;
      if (verts.length < 3) continue;
      for (final v in verts) {
        pts.add(Offset(v.dx * minorGridSpacing, v.dy * minorGridSpacing));
      }
    }
    if (pts.isEmpty) return null;

    final oriented = rotationRad == 0
        ? pts
        : _rotateAroundCentroid(pts, rotationRad);

    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final p in oriented) {
      minX = math.min(minX, p.dx);
      minY = math.min(minY, p.dy);
      maxX = math.max(maxX, p.dx);
      maxY = math.max(maxY, p.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  static List<Offset> _rotateAroundCentroid(
    List<Offset> pts,
    double rotationRad,
  ) {
    var cx = 0.0, cy = 0.0;
    for (final p in pts) {
      cx += p.dx;
      cy += p.dy;
    }
    cx /= pts.length;
    cy /= pts.length;
    final c = math.cos(rotationRad);
    final s = math.sin(rotationRad);
    return [
      for (final p in pts)
        Offset(
          cx + (p.dx - cx) * c - (p.dy - cy) * s,
          cy + (p.dx - cx) * s + (p.dy - cy) * c,
        ),
    ];
  }
}
