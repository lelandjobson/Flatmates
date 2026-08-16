import 'dart:collection';
import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' hide Colors;

// ---------------------------------------------------------------------------
// Folding transforms
// ---------------------------------------------------------------------------

sealed class FoldingTransform {
  const FoldingTransform();

  factory FoldingTransform.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String;
    return switch (type) {
      'movement' => MovementTransform.fromJson(json),
      'rotation' => RotationTransform.fromJson(json),
      _ => const NoneTransform(),
    };
  }
}

class MovementTransform extends FoldingTransform {
  const MovementTransform({required this.forward, required this.inverse});

  final Matrix4 forward;
  final Matrix4 inverse;

  factory MovementTransform.fromJson(Map<String, dynamic> json) {
    return MovementTransform(
      forward: _parseMatrix4(json['forward'] as List),
      inverse: _parseMatrix4(json['inverse'] as List),
    );
  }

  /// Accepts v9 nested 4x4 row lists or a flat 16-float row-major array.
  static Matrix4 _parseMatrix4(List values) {
    final m = Matrix4.zero();
    if (values.isNotEmpty && values.first is List) {
      for (var r = 0; r < 4; r++) {
        final row = values[r] as List;
        for (var c = 0; c < 4; c++) {
          m.setEntry(r, c, (row[c] as num).toDouble());
        }
      }
      return m;
    }
    if (values.length != 16) {
      throw FormatException(
        'Movement matrix must be 4x4 rows or 16 floats, got ${values.length}',
      );
    }
    for (var i = 0; i < 16; i++) {
      m.setEntry(i ~/ 4, i % 4, (values[i] as num).toDouble());
    }
    return m;
  }
}

class RotationTransform extends FoldingTransform {
  const RotationTransform({
    required this.axisStart,
    required this.axisEnd,
    required this.angleRadians,
  });

  final Vector3 axisStart;
  final Vector3 axisEnd;
  final double angleRadians;

  factory RotationTransform.fromJson(Map<String, dynamic> json) {
    final axis = json['axis'] as Map<String, dynamic>;
    final s = axis['start'] as List;
    final e = axis['end'] as List;
    return RotationTransform(
      axisStart: Vector3(
        (s[0] as num).toDouble(),
        (s[1] as num).toDouble(),
        (s[2] as num).toDouble(),
      ),
      axisEnd: Vector3(
        (e[0] as num).toDouble(),
        (e[1] as num).toDouble(),
        (e[2] as num).toDouble(),
      ),
      angleRadians: (json['angleRadians'] as num).toDouble(),
    );
  }

  /// Build a Matrix4 that rotates [angle] radians around the fold edge.
  Matrix4 buildMatrix(double angle) {
    final dir = axisEnd - axisStart;
    final len = dir.length;
    if (len < 1e-10) return Matrix4.identity();
    final axis = dir / len;
    final origin = axisStart.clone();

    final toOrigin = Matrix4.identity()..setTranslation(-origin);
    final rot = Matrix4.identity()
      ..setRotation(Quaternion.axisAngle(axis, angle).asRotationMatrix());
    final back = Matrix4.identity()..setTranslation(origin);
    return back * rot * toOrigin;
  }
}

class NoneTransform extends FoldingTransform {
  const NoneTransform();
}

// ---------------------------------------------------------------------------
// Transform tree node
// ---------------------------------------------------------------------------

class TransformTreeNode {
  const TransformTreeNode({
    required this.id,
    required this.faceIndex,
    required this.layer,
    required this.parentId,
    required this.childIds,
    required this.foldedVertices,
    required this.unfoldedVertices,
    required this.transform,
    this.foldedHoles = const [],
    this.unfoldedHoles = const [],
  });

  final int id;
  final int faceIndex;
  final String layer;
  final int? parentId;
  final List<int> childIds;
  final List<Vector3> foldedVertices;
  final List<Vector3> unfoldedVertices;
  final List<List<Vector3>> foldedHoles;
  final List<List<Vector3>> unfoldedHoles;
  final FoldingTransform transform;

  /// The unfolded polygon projected to 2D (dropping Z, which is ~0).
  List<Offset> get unfoldedPolygon2D =>
      unfoldedVertices.map((v) => Offset(v.x, v.y)).toList();

  /// The folded polygon projected to 2D (dropping Z).
  List<Offset> get foldedPolygon2D =>
      foldedVertices.map((v) => Offset(v.x, v.y)).toList();

  factory TransformTreeNode.fromJson(Map<String, dynamic> json) {
    return TransformTreeNode(
      id: (json['id'] as num).toInt(),
      faceIndex: (json['faceIndex'] as num).toInt(),
      layer: json['layer'] as String? ?? 'GEO',
      parentId: (json['parentId'] as num?)?.toInt(),
      childIds: _parseIntList(json['childIds'] as List? ?? const []),
      foldedVertices: _parseVec3List(json['foldedVertices'] as List? ?? const []),
      unfoldedVertices:
          _parseVec3List(json['unfoldedVertices'] as List? ?? const []),
      foldedHoles: _parseVec3ListList(json['foldedHoles'] as List? ?? const []),
      unfoldedHoles:
          _parseVec3ListList(json['unfoldedHoles'] as List? ?? const []),
      transform:
          FoldingTransform.fromJson(json['transform'] as Map<String, dynamic>),
    );
  }

  static List<int> _parseIntList(List json) =>
      json.map((v) => (v as num).toInt()).toList();

  static List<Vector3> _parseVec3List(List json) {
    return json.map((v) {
      final l = v as List;
      return Vector3(
        (l[0] as num).toDouble(),
        (l[1] as num).toDouble(),
        (l[2] as num).toDouble(),
      );
    }).toList();
  }

  static List<List<Vector3>> _parseVec3ListList(List json) {
    return json.map((ring) => _parseVec3List(ring as List)).toList();
  }
}

// ---------------------------------------------------------------------------
// Transform tree
// ---------------------------------------------------------------------------

class TransformTree {
  TransformTree({required this.rootId, required this.nodes})
      : _byId = {for (final n in nodes) n.id: n};

  final int rootId;
  final List<TransformTreeNode> nodes;
  final Map<int, TransformTreeNode> _byId;

  TransformTreeNode get root => _byId[rootId]!;

  TransformTreeNode? nodeById(int id) => _byId[id];

  /// Root-to-leaf BFS order (unfold direction).
  List<TransformTreeNode> rootToLeafOrder() {
    final result = <TransformTreeNode>[];
    final queue = Queue<int>()..add(rootId);
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      final node = _byId[id];
      if (node == null) continue;
      result.add(node);
      for (final childId in node.childIds) {
        queue.add(childId);
      }
    }
    return result;
  }

  /// Leaf-to-root order (refold direction).
  List<TransformTreeNode> leafToRootOrder() {
    final all = rootToLeafOrder();
    final visited = <int>{};
    final result = <TransformTreeNode>[];
    final leaves = all.where((n) => n.childIds.isEmpty).toList();
    final queue = Queue<TransformTreeNode>.from(leaves);

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (visited.contains(node.id)) continue;

      final allChildrenDone = node.childIds.every((c) => visited.contains(c));
      if (!allChildrenDone) {
        queue.add(node);
        continue;
      }

      result.add(node);
      visited.add(node.id);

      if (node.parentId != null && !visited.contains(node.parentId)) {
        final parent = _byId[node.parentId!];
        if (parent != null) queue.add(parent);
      }
    }
    return result;
  }

  /// All descendant IDs of [nodeId] (not including [nodeId] itself).
  Set<int> descendants(int nodeId) {
    final result = <int>{};
    final stack = <int>[...(_byId[nodeId]?.childIds ?? [])];
    while (stack.isNotEmpty) {
      final id = stack.removeLast();
      if (result.add(id)) {
        final node = _byId[id];
        if (node != null) stack.addAll(node.childIds);
      }
    }
    return result;
  }

  factory TransformTree.fromJson(Map<String, dynamic> json) {
    final nodesJson = json['nodes'] as List;
    return TransformTree(
      rootId: (json['rootId'] as num).toInt(),
      nodes: nodesJson
          .map((n) => TransformTreeNode.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Blueprint (runtime fill target)
// ---------------------------------------------------------------------------

/// How unfolded vertex coordinates in a [CraftingBlueprint] are interpreted.
enum BlueprintCoordinateSpace {
  /// Values are already craft world units (same space as papers / 3D handoff).
  world,

  /// Values are flatpipeline craft units, where 1 unit is one minor grid cell.
  craftUnits,
}

enum BlueprintStepKind { parts, applique }

class CraftingIsland {
  const CraftingIsland({
    required this.index,
    required this.originOffset,
    required this.foldedOffset,
    required this.unfoldedYDisplacement,
    required this.transformTree,
  });

  final int index;
  final Offset originOffset;
  final Vector3 foldedOffset;
  final double unfoldedYDisplacement;
  final TransformTree transformTree;

  factory CraftingIsland.fromJson(Map<String, dynamic> json) {
    final oo = json['origin_offset'] as List? ?? const [0, 0];
    final fo = json['folded_offset'] as List? ?? const [0, 0, 0];
    return CraftingIsland(
      index: (json['island'] as num?)?.toInt() ?? 0,
      originOffset: Offset(
        (oo[0] as num).toDouble(),
        (oo[1] as num).toDouble(),
      ),
      foldedOffset: Vector3(
        (fo[0] as num).toDouble(),
        (fo[1] as num).toDouble(),
        (fo[2] as num).toDouble(),
      ),
      unfoldedYDisplacement:
          (json['unfoldedYDisplacement'] as num?)?.toDouble() ?? 0,
      transformTree: TransformTree.fromJson(
        json['transformTree'] as Map<String, dynamic>,
      ),
    );
  }
}

class CraftingBlueprint {
  const CraftingBlueprint({
    required this.version,
    required this.craft,
    required this.stepIndex,
    required this.logicalIndex,
    required this.kind,
    required this.islands,
    this.qLayer,
    this.appliqueSurfaces = const [],
    this.appliqueCurves = const [],
    this.coordinateSpace = BlueprintCoordinateSpace.world,
    this.foldedGeometryId,
  });

  final int version;
  final String craft;

  /// Index into the parent craft's `steps` array.
  final int stepIndex;

  /// Logical step number from the source layer (`index` in the manifest).
  final int logicalIndex;

  final BlueprintStepKind kind;
  final int? qLayer;
  final List<CraftingIsland> islands;

  /// Applique surface outlines in absolute flat coordinates.
  final List<List<Vector3>> appliqueSurfaces;

  /// Applique boundary curves in absolute flat coordinates.
  final List<List<Vector3>> appliqueCurves;

  final BlueprintCoordinateSpace coordinateSpace;
  final String? foldedGeometryId;

  bool get isWorldSpace => coordinateSpace == BlueprintCoordinateSpace.world;

  /// Multiplier taking this blueprint's coordinates into craft world units.
  double worldScale(double minorGridSpacing) => switch (coordinateSpace) {
        BlueprintCoordinateSpace.world => 1.0,
        BlueprintCoordinateSpace.craftUnits => minorGridSpacing,
      };

  bool get isApplique => kind == BlueprintStepKind.applique;

  String get fillKey => '$craft#$stepIndex#${kind.name}#${qLayer ?? -1}';

  String get displayName => isApplique
      ? '$craft step $logicalIndex applique ${(qLayer ?? 0) + 1}'
      : (logicalIndex == 0 && stepIndex == 0 ? craft : '$craft step $logicalIndex');

  /// First island tree — used by single-island runtime handoff (mixed-3D).
  TransformTree get transformTree => islands.first.transformTree;

  Offset get originOffset =>
      islands.isEmpty ? Offset.zero : islands.first.originOffset;

  Vector3 get foldedOffset =>
      islands.isEmpty ? Vector3.zero() : islands.first.foldedOffset;

  double get unfoldedYDisplacement =>
      islands.isEmpty ? 0 : islands.first.unfoldedYDisplacement;

  Iterable<TransformTreeNode> get allNodes =>
      islands.expand((i) => i.transformTree.nodes);

  /// Unfolded fill polygons, with each island's origin applied and coordinates
  /// multiplied by [scale] (see [worldScale]).
  List<List<Offset>> unfoldedFillPolygons({double scale = 1.0}) {
    if (isApplique) {
      return [
        for (final ring in appliqueSurfaces)
          if (ring.length >= 3)
            [for (final v in ring) Offset(v.x * scale, v.y * scale)],
      ];
    }
    return _islandPolygons(scale);
  }

  /// Part-fill polygons for overlaying under an applique step (same layout).
  List<List<Offset>> partOverlayPolygons({double scale = 1.0}) =>
      _islandPolygons(scale);

  List<List<Offset>> _islandPolygons(double scale) {
    final out = <List<Offset>>[];
    for (final island in islands) {
      for (final node in island.transformTree.nodes) {
        final verts = node.unfoldedPolygon2D;
        if (verts.length < 3) continue;
        out.add([
          for (final v in verts)
            Offset(
              (v.dx + island.originOffset.dx) * scale,
              (v.dy + island.originOffset.dy) * scale,
            ),
        ]);
      }
    }
    return out;
  }

  List<String> fillPolygonLayers() {
    if (isApplique) {
      return List.filled(appliqueSurfaces.where((r) => r.length >= 3).length, 'applique');
    }
    final layers = <String>[];
    for (final island in islands) {
      for (final node in island.transformTree.nodes) {
        if (node.unfoldedPolygon2D.length >= 3) layers.add(node.layer);
      }
    }
    return layers;
  }
}

// ---------------------------------------------------------------------------
// Matrix interpolation
// ---------------------------------------------------------------------------

/// Element-wise linear interpolation between two 4x4 matrices.
/// Matches the web viewer's `lerpMatrices` function.
Matrix4 lerpMatrix4(Matrix4 a, Matrix4 b, double t) {
  if (t <= 0) return a.clone();
  if (t >= 1) return b.clone();

  final result = Matrix4.zero();
  for (var i = 0; i < 4; i++) {
    for (var j = 0; j < 4; j++) {
      result.setEntry(
        i,
        j,
        a.entry(i, j) + (b.entry(i, j) - a.entry(i, j)) * t,
      );
    }
  }
  return result;
}
