import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors, makeOrthographicMatrix;

import '../../crafting/completed_craft.dart';
import '../../crafting/crafting_blueprint.dart';
import '../../crafting/crafting_material.dart';
import '../../data/crafting_state.dart';
import '../../geometry/geometry_algorithms.dart' show convexHull;
import '../../rendering/scene/camera.dart' as scene_camera show Camera, ProjectionType;
import 'iso_projection.dart';
import 'iso_sprite.dart';
import 'iso_vector_generator.dart' show worldViewAngles, cardinalIndices;

/// Generates isometric sprites from completed craft geometry by folding
/// blueprint regions into 3D and projecting from multiple view angles.
class CraftSpriteGenerator {
  CraftSpriteGenerator({
    this.spriteSize = 128.0,
    CraftingMaterialRegistry? materialRegistry,
  }) : _registry = materialRegistry ?? CraftingMaterialRegistry();

  final double spriteSize;
  final CraftingMaterialRegistry _registry;

  /// Generate sprites for [viewCount] iso view directions using folded 3D
  /// geometry. Keys are view indices aligned with [worldViewAngles].
  Map<int, VectorIsoSprite> generateAllViewSprites(CompletedCraft craft,
      {CraftingBlueprint? blueprint, int viewCount = 8}) {
    final angles = worldViewAngles(viewCount);
    final sprites = <int, VectorIsoSprite>{};
    for (var i = 0; i < viewCount; i++) {
      sprites[i] = _generateFoldedSprite(craft, angles[i],
          blueprint: blueprint);
    }
    return sprites;
  }

  /// Generate 4 cardinal sprites from a [viewCount]-step ring.
  /// Returns [NW, SW, SE, NE] matching [IsoAsset.sprites] order.
  List<VectorIsoSprite> generateCardinalSprites(CompletedCraft craft,
      {CraftingBlueprint? blueprint, int viewCount = 8}) {
    final angles = worldViewAngles(viewCount);
    final ci = cardinalIndices(viewCount);
    return [
      _generateFoldedSprite(craft, angles[ci[0]], blueprint: blueprint),
      _generateFoldedSprite(craft, angles[ci[1]], blueprint: blueprint),
      _generateFoldedSprite(craft, angles[ci[2]], blueprint: blueprint),
      _generateFoldedSprite(craft, angles[ci[3]], blueprint: blueprint),
    ];
  }

  VectorIsoSprite _generateFoldedSprite(CompletedCraft craft, double angleDeg,
      {CraftingBlueprint? blueprint}) {
    final angleRad = angleDeg * math.pi / 180.0;
    if (blueprint != null) {
      return _renderFoldedBlueprint(craft, blueprint, angleRad);
    }
    return _renderFlat2D(craft, angleRad);
  }

  /// Renders the fully-folded 3D blueprint from the given view angle.
  /// Uses the v7 transform tree: each node's foldedVertices are already in
  /// their folded 3D position, so we project directly (no hinge folding).
  ///
  /// Camera model matches [IsoVectorGenerator._generateVectorViewFromGeometry]:
  /// Y-up coordinate system, fixed elevation factor of 0.6, orthographic
  /// projection via scene [Camera], and a 128x64 sprite canvas.
  VectorIsoSprite _renderFoldedBlueprint(
      CompletedCraft craft, CraftingBlueprint blueprint, double azimuthRad) {
    final tree = blueprint.transformTree;

    final size = Size(IsoProjection.tileWidth, IsoProjection.tileHeight);

    // Collect all vertices to determine extents for ortho scale.
    final allVerts = <Vector3>[];
    for (final node in tree.nodes) {
      if (node.foldedVertices.length >= 3) {
        allVerts.addAll(node.foldedVertices);
      }
    }
    if (allVerts.isEmpty) return _emptySprite();

    // Blueprint geometry uses Z-up; rotate to Y-up to match structure pipeline.
    for (var i = 0; i < allVerts.length; i++) {
      final v = allVerts[i];
      allVerts[i] = Vector3(v.x, v.z, -v.y);
    }

    // Tight-fit ortho scale: frame the geometry so it fills the sprite canvas.
    // Unlike IsoVectorGenerator (which uses a fixed worldUnitsPerTile scale for
    // OBJ models), craft geometry has arbitrary extents, so we size the
    // orthographic viewport to tightly contain the content.
    double maxExtent = 0;
    for (final v in allVerts) {
      final ax = v.x.abs(), ay = v.y.abs(), az = v.z.abs();
      if (ax > maxExtent) maxExtent = ax;
      if (ay > maxExtent) maxExtent = ay;
      if (az > maxExtent) maxExtent = az;
    }
    if (maxExtent < 1e-6) return _emptySprite();
    final orthoScale = maxExtent * 1.15;

    // Camera orbit matching IsoVectorGenerator: Y-up, elevation = distance*0.6
    const distance = 200.0;
    final cameraPos = Vector3(
      distance * math.cos(azimuthRad),
      distance * 0.6,
      distance * math.sin(azimuthRad),
    );
    final camera = scene_camera.Camera(
      name: 'craft-cam',
      position: cameraPos,
      target: Vector3.zero(),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: orthoScale,
      near: 0.1,
      far: 1000,
    );

    final aspect = size.width / size.height;
    final viewProj = camera.projectionMatrix(aspect) * camera.viewMatrix;
    final viewMat = camera.viewMatrix;

    final allFaces = <_Face>[];
    final dominantColor = _dominantColor(craft);

    // Re-iterate nodes to project with the proper camera.
    var vertIdx = 0;
    for (final node in tree.nodes) {
      final origVerts = node.foldedVertices;
      if (origVerts.length < 3) continue;

      final screenPts = <Offset>[];
      double depthSum = 0;
      for (var j = 0; j < origVerts.length; j++) {
        final v = allVerts[vertIdx + j];
        final projected = _projectToScreen(v, viewProj, size);
        if (projected == null) {
          screenPts.clear();
          break;
        }
        screenPts.add(projected);
        final camSpace = Vector3.copy(v);
        viewMat.transform3(camSpace);
        depthSum += camSpace.z;
      }
      vertIdx += origVerts.length;
      if (screenPts.length < 3) continue;

      allFaces.add(_Face(
        screenPts,
        depthSum / screenPts.length,
        dominantColor,
      ));
    }

    if (allFaces.isEmpty) return _emptySprite();

    // Painter's algorithm: farthest first (most negative camera-space Z).
    allFaces.sort((a, b) => a.depth.compareTo(b.depth));

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    for (var i = 0; i < allFaces.length; i++) {
      final face = allFaces[i];
      final path = Path();
      for (var j = 0; j < face.points.length; j++) {
        if (j == 0) {
          path.moveTo(face.points[j].dx, face.points[j].dy);
        } else {
          path.lineTo(face.points[j].dx, face.points[j].dy);
        }
      }
      path.close();

      final depthFactor = (i / allFaces.length).clamp(0.0, 1.0);
      final shade = Color.lerp(
        face.color.withValues(alpha: 0.7),
        face.color.withValues(alpha: 1.0),
        depthFactor,
      )!;

      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.fill
          ..color = shade,
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5
          ..color = face.color.withValues(alpha: 0.4),
      );
    }

    final allScreenPoints = <Offset>[];
    for (final face in allFaces) {
      allScreenPoints.addAll(face.points);
    }
    final hull = allScreenPoints.length >= 3
        ? convexHull(allScreenPoints)
        : null;

    final combinedPicture = recorder.endRecording();

    // Compute groundPoint: project the bottom-center of the AABB (min Y).
    final groundPoint = _computeGroundPoint(allVerts, viewProj, size);

    return VectorIsoSprite(combinedPicture, size,
        outlinePolygon: hull != null && hull.length >= 3 ? hull : null,
        groundPoint: groundPoint);
  }

  /// Fallback flat 2D rendering using the same camera model as structures.
  ///
  /// Treats the 2D paper polygons as flat geometry on the Y=0 plane in
  /// the Y-up world, then projects via the standard IsoVectorGenerator
  /// camera (ortho, elevation 0.6).
  VectorIsoSprite _renderFlat2D(CompletedCraft craft, double azimuthRad) {
    final size = Size(IsoProjection.tileWidth, IsoProjection.tileHeight);

    final bounds = _computeBounds(craft);
    if (bounds == Rect.zero) return _emptySprite();

    final maxExtent = math.max(bounds.width, bounds.height);
    if (maxExtent <= 0) return _emptySprite();

    // Normalize craft vertices to fit within a known range for ortho camera.
    final normScale = 100.0 / maxExtent;
    final craftCenterX = bounds.center.dx;
    final craftCenterY = bounds.center.dy;

    // Tight-fit ortho scale for the normalized 100-unit geometry.
    const orthoScale = 100.0 * 1.15;
    const distance = 200.0;
    final cameraPos = Vector3(
      distance * math.cos(azimuthRad),
      distance * 0.6,
      distance * math.sin(azimuthRad),
    );
    final camera = scene_camera.Camera(
      name: 'craft-flat-cam',
      position: cameraPos,
      target: Vector3.zero(),
      projection: scene_camera.ProjectionType.orthographic,
      orthographicScale: orthoScale,
      near: 0.1,
      far: 1000,
    );

    final aspect = size.width / size.height;
    final viewProj = camera.projectionMatrix(aspect) * camera.viewMatrix;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final allScreenPoints = <Offset>[];

    for (final paper in craft.papers) {
      final color = _colorForPaper(paper);
      final vertices = _getPaperVertices(paper, craft.canvasSize);
      if (vertices.length < 3) continue;

      final path = Path();
      for (var i = 0; i < vertices.length; i++) {
        // Map 2D craft coords to Y-up world: X = craft X, Z = craft Y, Y = 0
        final wx = (vertices[i].dx - craftCenterX) * normScale;
        final wz = (vertices[i].dy - craftCenterY) * normScale;
        final worldPt = Vector3(wx, 0, wz);
        final projected = _projectToScreen(worldPt, viewProj, size);
        if (projected == null) continue;
        allScreenPoints.add(projected);
        if (i == 0) {
          path.moveTo(projected.dx, projected.dy);
        } else {
          path.lineTo(projected.dx, projected.dy);
        }
      }
      path.close();

      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.fill
        ..color = color.withValues(alpha: 0.9));
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = color.withValues(alpha: 0.5));
    }

    final hull = allScreenPoints.length >= 3
        ? convexHull(allScreenPoints)
        : null;

    final combinedPicture = recorder.endRecording();

    // Ground point: project the origin (flat on Y=0 plane).
    final groundPoint = _projectToScreen(Vector3.zero(), viewProj, size);

    return VectorIsoSprite(combinedPicture, size,
        outlinePolygon: hull != null && hull.length >= 3 ? hull : null,
        groundPoint: groundPoint);
  }

  // ---------------------------------------------------------------------------
  // Projection helpers (matching IsoVectorGenerator)
  // ---------------------------------------------------------------------------

  Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
    final v4 = Vector4(worldPos.x, worldPos.y, worldPos.z, 1.0);
    mvp.transform(v4);
    if (v4.w.abs() <= 1e-3) return null;

    final ndcX = v4.x / v4.w;
    final ndcY = v4.y / v4.w;
    if (!ndcX.isFinite || !ndcY.isFinite) return null;

    final screenX = (ndcX * 0.5 + 0.5) * size.width;
    final screenY = (1 - (ndcY * 0.5 + 0.5)) * size.height;
    if (!screenX.isFinite || !screenY.isFinite) return null;

    return Offset(screenX, screenY);
  }

  /// Project the bottom-center of the AABB (min Y in Y-up space).
  Offset? _computeGroundPoint(
      List<Vector3> vertices, Matrix4 viewProj, Size size) {
    if (vertices.isEmpty) return null;
    double minX = double.infinity, maxX = double.negativeInfinity;
    double minY = double.infinity;
    double minZ = double.infinity, maxZ = double.negativeInfinity;
    for (final v in vertices) {
      if (v.x < minX) minX = v.x;
      if (v.x > maxX) maxX = v.x;
      if (v.y < minY) minY = v.y;
      if (v.z < minZ) minZ = v.z;
      if (v.z > maxZ) maxZ = v.z;
    }
    return _projectToScreen(
      Vector3((minX + maxX) / 2, minY, (minZ + maxZ) / 2),
      viewProj,
      size,
    );
  }

  // ---------------------------------------------------------------------------
  // Flat 2D helpers
  // ---------------------------------------------------------------------------

  Rect _computeBounds(CompletedCraft craft) {
    double minX = double.infinity, minY = double.infinity;
    double maxX = double.negativeInfinity, maxY = double.negativeInfinity;
    for (final paper in craft.papers) {
      final verts = _getPaperVertices(paper, craft.canvasSize);
      for (final v in verts) {
        minX = math.min(minX, v.dx);
        minY = math.min(minY, v.dy);
        maxX = math.max(maxX, v.dx);
        maxY = math.max(maxY, v.dy);
      }
    }
    if (minX == double.infinity) return Rect.zero;
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  List<Offset> _getPaperVertices(CraftingPaperState paper, double canvasSize) {
    if (paper.localVertices != null && paper.localVertices!.isNotEmpty) {
      final cosR = math.cos(paper.rotationDeg * math.pi / 180);
      final sinR = math.sin(paper.rotationDeg * math.pi / 180);
      return paper.localVertices!.map((v) {
        final rx = v.dx * cosR - v.dy * sinR;
        final ry = v.dx * sinR + v.dy * cosR;
        return Offset(paper.positionX + rx, paper.positionY + ry);
      }).toList();
    }
    final half = paper.sizeLevel * (canvasSize / 4) / 2;
    final cosR = math.cos(paper.rotationDeg * math.pi / 180);
    final sinR = math.sin(paper.rotationDeg * math.pi / 180);
    final corners = [
      Offset(-half, -half),
      Offset(half, -half),
      Offset(half, half),
      Offset(-half, half),
    ];
    return corners.map((c) {
      final rx = c.dx * cosR - c.dy * sinR;
      final ry = c.dx * sinR + c.dy * cosR;
      return Offset(paper.positionX + rx, paper.positionY + ry);
    }).toList();
  }

  Color _colorForPaper(CraftingPaperState paper) {
    if (paper.materialId != null) {
      return _registry.colorFor(paper.materialId!);
    }
    return paper.paperColor.color;
  }

  Color _dominantColor(CompletedCraft craft) {
    if (craft.papers.isEmpty) return Colors.grey;
    final first = craft.papers.first;
    return _colorForPaper(first);
  }

  VectorIsoSprite _emptySprite() {
    final size = Size(IsoProjection.tileWidth, IsoProjection.tileHeight);
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..color = Colors.transparent,
    );
    return VectorIsoSprite(recorder.endRecording(), size);
  }
}

class _Face {
  _Face(this.points, this.depth, this.color);
  final List<Offset> points;
  final double depth;
  final Color color;
}
