import 'dart:ui';

import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/folded_geometry.dart';
import 'crafting_blueprint.dart';

/// Builds a [CraftingBlueprint] whose unfolded polygons match a live
/// [FoldedGeometry] net after [worldFromLocal] (mesh rotation + centering).
///
/// Vertex coordinates are craft **world** units (`coordinateSpace: world`) so
/// the craft view can display them 1:1 with the 3D unfold handoff — no
/// `minorGridSpacing` scale is applied.
CraftingBlueprint craftingBlueprintFromFoldedGeometry({
  required FoldedGeometry folded,
  required Matrix4 worldFromLocal,
  String craft = 'cube',
  int island = 0,
  String? foldedGeometryId,
}) {
  var nextId = 0;
  final nodes = <TransformTreeNode>[];

  Vector3 toCraft(Vector3 local) {
    final w = Vector3.copy(local);
    worldFromLocal.transform3(w);
    return Vector3(w.x, w.y, 0);
  }

  List<Vector3> closeRing(List<Vector3> ring) {
    if (ring.isEmpty) return ring;
    if ((ring.first - ring.last).length2 > 1e-8) {
      return [...ring, Vector3.copy(ring.first)];
    }
    return ring;
  }

  int walk(FoldFace face, int? parentId, FoldingTransform transform) {
    final id = nextId++;
    final childIds = <int>[];

    final unfolded = closeRing([
      for (final v in face.vertices) toCraft(v),
    ]);

    // Register children first so childIds are known, then emit this node.
    final childTransforms = <FoldingTransform>[];
    for (final attachment in face.children) {
      final axisStart = toCraft(face.vertices[attachment.parentEdgeStart]);
      final axisEnd = toCraft(face.vertices[attachment.parentEdgeEnd]);
      childTransforms.add(
        RotationTransform(
          axisStart: axisStart,
          axisEnd: axisEnd,
          angleRadians: attachment.foldAngleRadians,
        ),
      );
    }

    for (var i = 0; i < face.children.length; i++) {
      final childId = walk(
        face.children[i].child,
        id,
        childTransforms[i],
      );
      childIds.add(childId);
    }

    nodes.add(
      TransformTreeNode(
        id: id,
        faceIndex: face.originalFaceIndex ?? id,
        layer: 'GEO',
        parentId: parentId,
        childIds: childIds,
        foldedVertices: unfolded.map(Vector3.copy).toList(),
        unfoldedVertices: unfolded,
        transform: transform,
      ),
    );
    return id;
  }

  final rootId = walk(folded.root, null, const NoneTransform());

  // `walk` appends parents after children (post-order). Sort by id so the
  // transform tree lookup is stable; rootId is still correct.
  nodes.sort((a, b) => a.id.compareTo(b.id));

  return CraftingBlueprint(
    version: 7,
    craft: craft,
    island: island,
    originOffset: Offset.zero,
    foldedOffset: Vector3.zero(),
    unfoldedYDisplacement: 0,
    transformTree: TransformTree(rootId: rootId, nodes: nodes),
    coordinateSpace: BlueprintCoordinateSpace.world,
    foldedGeometryId: foldedGeometryId ?? folded.id,
  );
}

/// World matrix matching the object-focus Rx(+90°) + centering used in the
/// mixed-3D host: flat FoldedGeometry net (XZ / +Y) → craft XY / +Z.
Matrix4 craftAlignMatrixFromFoldedNet({
  required FoldedGeometry folded,
  double alignRx = 1.5707963267948966, // pi/2
}) {
  final flat = folded.toGeometry(foldValue: 0);
  final rx = Matrix4.rotationX(alignRx);
  final c = Vector3.zero();
  for (final v in flat.vertices) {
    c.add(v);
  }
  if (flat.vertices.isNotEmpty) {
    c.scale(1.0 / flat.vertices.length);
  }
  final wc = Vector3.copy(c);
  rx.transform3(wc);
  return Matrix4.identity()
    ..translate(Vector3(-wc.x, -wc.y, -wc.z))
    ..rotateX(alignRx);
}
