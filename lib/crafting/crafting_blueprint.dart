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

  static Matrix4 _parseMatrix4(List rows) {
    final m = Matrix4.zero();
    for (var r = 0; r < 4; r++) {
      final row = rows[r] as List;
      for (var c = 0; c < 4; c++) {
        m.setEntry(r, c, (row[c] as num).toDouble());
      }
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
  });

  final int id;
  final int faceIndex;
  final String layer;
  final int? parentId;
  final List<int> childIds;
  final List<Vector3> foldedVertices;
  final List<Vector3> unfoldedVertices;
  final FoldingTransform transform;

  /// The unfolded polygon projected to 2D (dropping Z, which is ~0).
  List<Offset> get unfoldedPolygon2D =>
      unfoldedVertices.map((v) => Offset(v.x, v.y)).toList();

  /// The folded polygon projected to 2D (dropping Z).
  List<Offset> get foldedPolygon2D =>
      foldedVertices.map((v) => Offset(v.x, v.y)).toList();

  factory TransformTreeNode.fromJson(Map<String, dynamic> json) {
    return TransformTreeNode(
      id: json['id'] as int,
      faceIndex: json['faceIndex'] as int,
      layer: json['layer'] as String,
      parentId: json['parentId'] as int?,
      childIds: (json['childIds'] as List).cast<int>(),
      foldedVertices: _parseVec3List(json['foldedVertices'] as List),
      unfoldedVertices: _parseVec3List(json['unfoldedVertices'] as List),
      transform:
          FoldingTransform.fromJson(json['transform'] as Map<String, dynamic>),
    );
  }

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
    final leaves =
        all.where((n) => n.childIds.isEmpty).toList();
    final queue = Queue<TransformTreeNode>.from(leaves);

    while (queue.isNotEmpty) {
      final node = queue.removeFirst();
      if (visited.contains(node.id)) continue;

      final allChildrenDone =
          node.childIds.every((c) => visited.contains(c));
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
      rootId: json['rootId'] as int,
      nodes: nodesJson
          .map((n) =>
              TransformTreeNode.fromJson(n as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ---------------------------------------------------------------------------
// Blueprint (top-level)
// ---------------------------------------------------------------------------

/// How unfolded vertex coordinates in a [CraftingBlueprint] are interpreted.
enum BlueprintCoordinateSpace {
  /// Default: values are craft-grid cells; multiply by minorGridSpacing.
  grid,

  /// Values are already craft world units (same space as papers / 3D handoff).
  world,
}

class CraftingBlueprint {
  const CraftingBlueprint({
    required this.version,
    required this.craft,
    required this.island,
    required this.originOffset,
    required this.foldedOffset,
    required this.unfoldedYDisplacement,
    required this.transformTree,
    this.coordinateSpace = BlueprintCoordinateSpace.grid,
    this.foldedGeometryId,
  });

  final int version;

  /// Craft name (original Rhino group name casing).
  final String craft;

  /// Zero-based island index within the craft.
  final int island;

  /// Bbox min of flat layout subtracted from all unfolded coordinates.
  final Offset originOffset;

  /// Negated pre-unfold translation for folded mesh positioning.
  final Vector3 foldedOffset;

  /// Recommended Y displacement for visual separation during unfold.
  final double unfoldedYDisplacement;

  final TransformTree transformTree;

  /// When [BlueprintCoordinateSpace.world], skip minor-grid scaling on load.
  final BlueprintCoordinateSpace coordinateSpace;

  /// Optional link back to a [FoldedGeometry.id] for 3D↔craft handoff.
  final String? foldedGeometryId;

  /// Display name combining craft and island (e.g. "Group03" or "Group03 #1").
  String get displayName =>
      island == 0 ? craft : '$craft #$island';

  bool get isWorldSpace =>
      coordinateSpace == BlueprintCoordinateSpace.world;

  factory CraftingBlueprint.fromJson(Map<String, dynamic> json) {
    final oo = json['origin_offset'] as List;
    final fo = json['folded_offset'] as List? ?? [0, 0, 0];
    final spaceRaw = json['coordinateSpace'] as String?;
    final space = spaceRaw == 'world'
        ? BlueprintCoordinateSpace.world
        : BlueprintCoordinateSpace.grid;

    return CraftingBlueprint(
      version: json['version'] as int,
      craft: json['craft'] as String,
      island: json['island'] as int,
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
          (json['unfoldedYDisplacement'] as num).toDouble(),
      transformTree: TransformTree.fromJson(
          json['transformTree'] as Map<String, dynamic>),
      coordinateSpace: space,
      foldedGeometryId: json['foldedGeometryId'] as String?,
    );
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
      result.setEntry(i, j,
          a.entry(i, j) + (b.entry(i, j) - a.entry(i, j)) * t);
    }
  }
  return result;
}
