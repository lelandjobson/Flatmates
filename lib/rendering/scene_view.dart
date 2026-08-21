import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/geometry.dart';
import 'lights.dart';
import 'mesh.dart';
import 'scene/camera.dart';
import 'scene/scene.dart';

class SceneView extends StatelessWidget {
  const SceneView({
    super.key,
    required this.scene,
    this.debugOptions = const SceneDebugOptions(),
  });

  final Scene scene;
  final SceneDebugOptions debugOptions;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: ScenePainter(scene: scene, debugOptions: debugOptions),
      isComplex: true,
      willChange: true,
    );
  }
}

class ScenePainter extends CustomPainter {
  ScenePainter({
    required Scene scene,
    this.debugOptions = const SceneDebugOptions(),
  }) : _scene = scene,
       super(repaint: scene);

  final Scene _scene;
  final SceneDebugOptions debugOptions;

  @override
  void paint(Canvas canvas, Size size) {
    final camera = _scene.camera;
    if (camera == null) {
      _drawPlaceholder(canvas, size);
      return;
    }

    canvas.clipRect(Offset.zero & size);

    final aspect = size.width / size.height;
    final projection = camera.projectionMatrix(aspect);
    final view = camera.viewMatrix;
    final viewProjection = projection * view;

    final facesToDraw = <_ProjectedFace>[];
    final normalsToDraw = <_ProjectedNormal>[];
    // Wireframe edges from original (non-tessellated) geometry of grouped
    // meshes. These are drawn separately so the clean object outlines are
    // visible without the tessellation subdivision lines.
    final wireframeEdges = <_ProjectedLine>[];

    final allMeshes = _scene.meshes;

    for (final mesh in allMeshes) {
      if (!mesh.visible) continue;
      final isDoubleSided = mesh.material.doubleSided;
      final world = mesh.transformMatrix;

      // Check if this mesh belongs to a render group.
      final group = _scene.renderGroupForMesh(mesh.id);
      final Geometry renderGeometry;
      final bool isTessellated;

      if (group != null) {
        renderGeometry = group.getTessellatedGeometry(mesh, allMeshes);
        isTessellated = !identical(renderGeometry, mesh.geometry);
      } else {
        renderGeometry = mesh.geometry;
        isTessellated = false;
      }

      // --- Fill pass: use (possibly tessellated) geometry ---
      _collectFaces(
        mesh: mesh,
        geometry: renderGeometry,
        world: world,
        view: view,
        viewProjection: viewProjection,
        camera: camera,
        size: size,
        isDoubleSided: isDoubleSided,
        isTessellated: isTessellated,
        facesToDraw: facesToDraw,
        normalsToDraw: normalsToDraw,
      );

      // --- Wireframe pass for tessellated meshes: use original geometry ---
      if (isTessellated &&
          debugOptions.showTessellationWireframe &&
          !debugOptions.wireframeOnly) {
        _collectWireframeEdges(
          mesh: mesh,
          world: world,
          view: view,
          viewProjection: viewProjection,
          camera: camera,
          size: size,
          wireframeEdges: wireframeEdges,
        );
      }
    }

    facesToDraw.sort((a, b) => a.depth.compareTo(b.depth));

    if (debugOptions.showWorldXyPlane) {
      _drawGrid(canvas, size, viewProjection);
    }

    // Paint pools: reuse Paint objects by color to reduce allocation.
    final fillPool = <Color, Paint>{};
    final seamPool = <Color, Paint>{};
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = debugOptions.wireframeOnly ? 1.5 : 1.2
      ..color = debugOptions.wireframeOnly ? Colors.white70 : Colors.white24;

    // Pool for colored edge strokes (wireframe & non-opaque materials).
    final edgePool = <Color, Paint>{};

    for (final face in facesToDraw) {
      final path = Path()..addPolygon(face.points, true);

      if (face.isWireframe) {
        // Wireframe material: faint fill + colored edge stroke.
        final faintColor = face.color.withOpacity(0.05);
        final faintPaint = fillPool.putIfAbsent(
          faintColor,
          () => Paint()
            ..style = PaintingStyle.fill
            ..color = faintColor,
        );
        canvas.drawPath(path, faintPaint);
        final wirePaint = edgePool.putIfAbsent(
          face.color,
          () => Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = face.color.withOpacity(0.7),
        );
        canvas.drawPath(path, wirePaint);
        continue;
      }

      // Fill (respects opacity already baked into face.color alpha).
      final fillPaint = fillPool.putIfAbsent(
        face.color,
        () => Paint()
          ..style = PaintingStyle.fill
          ..color = face.color,
      );
      canvas.drawPath(path, fillPaint);

      // Edge stroke.
      if (face.edgeColor != null) {
        // Non-opaque material: draw edges in the material's base colour.
        final coloredStroke = edgePool.putIfAbsent(
          face.edgeColor!,
          () => Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.0
            ..color = face.edgeColor!.withOpacity(0.8),
        );
        canvas.drawPath(path, coloredStroke);
      } else if (!face.strokeEdges) {
        // Fill only.
      } else if (face.isTessellated) {
        if (debugOptions.enableGrout) {
          final seamPaint = seamPool.putIfAbsent(
            face.color,
            () => Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.75
              ..color = face.color,
          );
          canvas.drawPath(path, seamPaint);
        }
      } else {
        canvas.drawPath(path, strokePaint);
      }
    }

    // Draw wireframe for tessellated meshes from their original edges.
    if (wireframeEdges.isNotEmpty) {
      for (final edge in wireframeEdges) {
        canvas.drawLine(edge.start, edge.end, strokePaint);
      }
    }

    if (debugOptions.showNormals && normalsToDraw.isNotEmpty) {
      final normalPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = Colors.amberAccent;

      for (final normal in normalsToDraw) {
        canvas.drawLine(normal.start, normal.end, normalPaint);
        _drawArrowHead(canvas, normal.start, normal.end, normalPaint);
      }
    }
  }

  /// Collect projected faces from a geometry into [facesToDraw].
  void _collectFaces({
    required Mesh mesh,
    required Geometry geometry,
    required Matrix4 world,
    required Matrix4 view,
    required Matrix4 viewProjection,
    required Camera camera,
    required Size size,
    required bool isDoubleSided,
    required bool isTessellated,
    required List<_ProjectedFace> facesToDraw,
    required List<_ProjectedNormal> normalsToDraw,
  }) {
    final faces = geometry.faces;

    for (var faceIndex = 0; faceIndex < faces.length; faceIndex++) {
      final face = faces[faceIndex];
      if (face.length < 3) continue;

      // Transform all vertices to world space.
      final worldVertices = <Vector3>[];
      for (final index in face) {
        final localVertex = geometry.vertices[index];
        final worldPos = Vector3.copy(localVertex);
        world.transform3(worldPos);
        worldVertices.add(worldPos);
      }

      // Clip the polygon against the near plane so that faces straddling
      // the plane are trimmed rather than discarded entirely.
      final clipped = _clipFaceToNearPlane(worldVertices, view, camera.near);
      if (clipped.length < 3) continue;

      // Project the clipped vertices.
      final points = <Offset>[];
      final depths = <double>[];
      var shouldDiscard = false;
      for (final wp in clipped) {
        final cs = Vector3.copy(wp);
        view.transform3(cs);
        depths.add(cs.z);

        final projected = _projectToScreen(wp, viewProjection, size);
        if (projected == null) {
          shouldDiscard = true;
          break;
        }
        points.add(projected);
      }

      if (shouldDiscard || points.length < 3) continue;

      // Compute face normal from the original (unclipped) vertices to avoid
      // degenerate normals from heavily clipped geometry.
      final normal = _faceNormal(worldVertices);

      final faceCenter = Vector3.zero();
      for (final vertex in worldVertices) {
        faceCenter.add(vertex);
      }
      faceCenter.scale(1 / worldVertices.length);

      final toCamera = (camera.position - faceCenter)..normalize();
      final faceDot = normal.dot(toCamera);
      final facingCamera = faceDot > 0;
      if (faceDot <= -0.15 && !isDoubleSided) continue;

      final shadingNormal = facingCamera ? normal : -normal;
      final shade = _shadeForFace(
        shadingNormal,
        _scene.lights,
        _scene.globalIllumination,
      );
      final depth = depths.reduce((a, b) => a + b) / depths.length;

      if (debugOptions.showNormals) {
        final centerScreen = _projectToScreen(faceCenter, viewProjection, size);
        final tipWorld = faceCenter + shadingNormal * 40;
        final tipScreen = _projectToScreen(tipWorld, viewProjection, size);
        if (centerScreen != null && tipScreen != null) {
          normalsToDraw.add(
            _ProjectedNormal(start: centerScreen, end: tipScreen),
          );
        }
      }

      final highlightColor = mesh.highlightColor;
      final baseColor = mesh.material.colorForFace(
        faceIndex,
        seed: mesh.geometry.colorSeed,
      );
      final litColor = _applyLighting(baseColor, shade);
      final materialOpacity = mesh.material.opacity.clamp(0.0, 1.0);
      final faceColor =
          highlightColor ??
          (debugOptions.wireframeOnly
              ? baseColor.withOpacity(0.12)
              : (materialOpacity < 1.0
                    ? litColor.withOpacity(
                        (litColor.opacity * materialOpacity).clamp(0.0, 1.0),
                      )
                    : litColor));

      facesToDraw.add(
        _ProjectedFace(
          points: points,
          color: faceColor,
          depth: depth,
          isTessellated: isTessellated,
          isWireframe: mesh.material.wireframe,
          opacity: materialOpacity,
          strokeEdges: mesh.material.strokeEdges,
          edgeColor: materialOpacity < 1.0 && mesh.material.strokeEdges
              ? baseColor
              : null,
        ),
      );
    }
  }

  /// Collect wireframe edges from a mesh's **original** geometry.
  /// Used for tessellated meshes so that the clean wireframe of the actual
  /// object shape is drawn rather than the subdivision lines.
  void _collectWireframeEdges({
    required Mesh mesh,
    required Matrix4 world,
    required Matrix4 view,
    required Matrix4 viewProjection,
    required Camera camera,
    required Size size,
    required List<_ProjectedLine> wireframeEdges,
  }) {
    final isDoubleSided = mesh.material.doubleSided;
    final faces = mesh.geometry.faces;
    final vertices = mesh.geometry.vertices;

    for (final face in faces) {
      if (face.length < 3) continue;

      // Back-face cull using original geometry.
      final worldVerts = <Vector3>[];
      for (final idx in face) {
        final wp = Vector3.copy(vertices[idx]);
        world.transform3(wp);
        worldVerts.add(wp);
      }

      final normal = _faceNormal(worldVerts);
      final faceCenter = Vector3.zero();
      for (final v in worldVerts) {
        faceCenter.add(v);
      }
      faceCenter.scale(1 / worldVerts.length);
      final toCamera = (camera.position - faceCenter)..normalize();
      if (normal.dot(toCamera) <= -0.15 && !isDoubleSided) continue;

      // Clip against near plane, then project.
      final clipped = _clipFaceToNearPlane(worldVerts, view, camera.near);
      if (clipped.length < 3) continue;

      final projected = <Offset>[];
      var valid = true;
      for (final wv in clipped) {
        final p = _projectToScreen(wv, viewProjection, size);
        if (p == null) {
          valid = false;
          break;
        }
        projected.add(p);
      }
      if (!valid || projected.length < 3) continue;

      for (var i = 0; i < projected.length; i++) {
        final j = (i + 1) % projected.length;
        wireframeEdges.add(
          _ProjectedLine(
            start: projected[i],
            end: projected[j],
            paint: Paint(), // paint is ignored; shared strokePaint used
          ),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant ScenePainter oldDelegate) =>
      oldDelegate._scene != _scene || oldDelegate.debugOptions != debugOptions;

  void _drawPlaceholder(Canvas canvas, Size size) {
    final textPainter = TextPainter(
      text: const TextSpan(
        text: 'Add a camera to the scene to begin rendering.',
        style: TextStyle(color: Colors.white70, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: size.width * 0.8);

    final offset = Offset(
      (size.width - textPainter.width) / 2,
      (size.height - textPainter.height) / 2,
    );
    textPainter.paint(canvas, offset);
  }
}

class _ProjectedFace {
  _ProjectedFace({
    required this.points,
    required this.color,
    required this.depth,
    this.isTessellated = false,
    this.isWireframe = false,
    this.opacity = 1.0,
    this.strokeEdges = true,
    this.edgeColor,
  });

  final List<Offset> points;
  final Color color;
  final double depth;

  /// True if this face comes from tessellated (subdivided) geometry.
  /// Tessellated faces skip wireframe stroke to avoid visual clutter.
  final bool isTessellated;

  /// True if the source mesh uses a wireframe material.
  final bool isWireframe;

  /// Fill opacity from the material (1.0 = fully opaque).
  final double opacity;

  /// When false, skip per-face edge strokes (silhouette overlays can replace them).
  final bool strokeEdges;

  /// When non-null, edges are drawn in this colour instead of the default
  /// white stroke.  Used for non-opaque and wireframe faces.
  final Color? edgeColor;
}

class _ProjectedNormal {
  const _ProjectedNormal({required this.start, required this.end});

  final Offset start;
  final Offset end;
}

class SceneDebugOptions {
  const SceneDebugOptions({
    this.showNormals = false,
    this.wireframeOnly = false,
    this.showTessellationWireframe = false,
    this.enableGrout = false,
    this.showWorldXyPlane = true,
  });

  final bool showNormals;
  final bool wireframeOnly;

  /// When true, the original-geometry wireframe edges of tessellated meshes
  /// are drawn on top of the filled faces. Off by default so tessellated
  /// objects appear clean unless explicitly requested.
  final bool showTessellationWireframe;

  /// When true, tessellated faces are drawn with a hairline same-color stroke
  /// to seal sub-pixel gaps between adjacent triangles. Off by default.
  final bool enableGrout;

  /// When true, draws the world XY plane grid behind the scene.
  final bool showWorldXyPlane;
}

Vector4 _transformPosition(Matrix4 matrix, Vector3 position) {
  final storage = matrix.storage;
  final x = position.x;
  final y = position.y;
  final z = position.z;
  return Vector4(
    storage[0] * x + storage[4] * y + storage[8] * z + storage[12],
    storage[1] * x + storage[5] * y + storage[9] * z + storage[13],
    storage[2] * x + storage[6] * y + storage[10] * z + storage[14],
    storage[3] * x + storage[7] * y + storage[11] * z + storage[15],
  );
}

Vector3 _faceNormal(List<Vector3> vertices) {
  final a = vertices[0];
  final b = vertices[1];
  final c = vertices[2];
  final edge1 = b - a;
  final edge2 = c - a;
  final normal = edge1.cross(edge2);
  if (normal.length2 == 0) {
    return Vector3.zero();
  }
  return normal.normalized();
}

/// Sutherland-Hodgman clip of a world-space polygon against the camera near
/// plane.  Returns the clipped vertices in world space (empty if the entire
/// face is behind the near plane).
///
/// Camera convention: looks along -Z, so objects in front have
/// cameraSpace.z < 0 and the near plane sits at z = -[nearDist].
List<Vector3> _clipFaceToNearPlane(
  List<Vector3> worldVertices,
  Matrix4 view,
  double nearDist,
) {
  final cameraZs = <double>[];
  for (final v in worldVertices) {
    final cs = Vector3.copy(v);
    view.transform3(cs);
    cameraZs.add(cs.z);
  }

  final output = <Vector3>[];
  final n = worldVertices.length;
  final planeZ = -nearDist;

  for (var i = 0; i < n; i++) {
    final j = (i + 1) % n;
    final zA = cameraZs[i];
    final zB = cameraZs[j];
    final a = worldVertices[i];
    final b = worldVertices[j];

    final aInside = zA <= planeZ;
    final bInside = zB <= planeZ;

    if (aInside && bInside) {
      output.add(b);
    } else if (aInside) {
      final t = (planeZ - zA) / (zB - zA);
      output.add(a + (b - a) * t);
    } else if (bInside) {
      final t = (planeZ - zA) / (zB - zA);
      output.add(a + (b - a) * t);
      output.add(b);
    }
  }

  return output;
}

double _shadeForFace(
  Vector3 normal,
  List<DirectionalLight> lights,
  double globalIllumination,
) {
  if (normal.length2 == 0) {
    return globalIllumination.clamp(0.0, 1.0);
  }

  final normalizedNormal = normal.normalized();
  var lightContribution = 0.0;

  for (final light in lights) {
    final dir = (-light.direction).normalized();
    final intensity = math.max(0, normalizedNormal.dot(dir)) * light.intensity;
    lightContribution += intensity;
  }

  return (globalIllumination + lightContribution).clamp(0.0, 1.0);
}

Color _applyLighting(Color base, double factor) {
  final r = (base.red * factor).clamp(0, 255).toInt();
  final g = (base.green * factor).clamp(0, 255).toInt();
  final b = (base.blue * factor).clamp(0, 255).toInt();
  return Color.fromARGB(base.alpha, r, g, b);
}

Offset? _projectToScreen(Vector3 worldPos, Matrix4 mvp, Size size) {
  final clip = _transformPosition(mvp, worldPos);
  // Reject vertices behind the camera (clip.w < 0) or on the camera plane.
  // The perspective matrix maps w = -cameraZ, so objects behind the camera
  // produce negative w, which would invert NDC and create twisted faces.
  if (!_vector4IsFinite(clip) || clip.w < 1e-3) {
    return null;
  }
  final ndcX = clip.x / clip.w;
  final ndcY = clip.y / clip.w;
  if (!ndcX.isFinite || !ndcY.isFinite) {
    return null;
  }
  final screenX = (ndcX * 0.5 + 0.5) * size.width;
  final screenY = (1 - (ndcY * 0.5 + 0.5)) * size.height;
  if (!screenX.isFinite || !screenY.isFinite) {
    return null;
  }
  return Offset(screenX, screenY);
}

void _drawArrowHead(Canvas canvas, Offset start, Offset end, Paint paint) {
  const double arrowSize = 6;
  final direction = (end - start);
  if (direction.distanceSquared == 0) return;
  final angle = math.atan2(direction.dy, direction.dx);
  final path = Path()
    ..moveTo(end.dx, end.dy)
    ..lineTo(
      end.dx - arrowSize * math.cos(angle - math.pi / 6),
      end.dy - arrowSize * math.sin(angle - math.pi / 6),
    )
    ..moveTo(end.dx, end.dy)
    ..lineTo(
      end.dx - arrowSize * math.cos(angle + math.pi / 6),
      end.dy - arrowSize * math.sin(angle + math.pi / 6),
    );
  canvas.drawPath(path, paint);
}

void _drawGrid(Canvas canvas, Size size, Matrix4 viewProjection) {
  const extent = 500.0;
  const spacing = 100.0;
  final lines = <_ProjectedLine>[];
  final basePaint = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.white12
    ..strokeWidth = 0.8;
  final axisPaintX = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.lightBlueAccent.withOpacity(0.4)
    ..strokeWidth = 1.2;
  final axisPaintY = Paint()
    ..style = PaintingStyle.stroke
    ..color = Colors.pinkAccent.withOpacity(0.5)
    ..strokeWidth = 1.8;

  for (double x = -extent; x <= extent; x += spacing) {
    final start = _projectToScreen(
      Vector3(x, -extent, 0),
      viewProjection,
      size,
    );
    final end = _projectToScreen(Vector3(x, extent, 0), viewProjection, size);
    if (start != null && end != null) {
      final paint = x.abs() < 1e-3 ? axisPaintX : basePaint;
      lines.add(_ProjectedLine(start: start, end: end, paint: paint));
    }
  }

  for (double y = -extent; y <= extent; y += spacing) {
    final start = _projectToScreen(
      Vector3(-extent, y, 0),
      viewProjection,
      size,
    );
    final end = _projectToScreen(Vector3(extent, y, 0), viewProjection, size);
    if (start != null && end != null) {
      final paint = y.abs() < 1e-3 ? axisPaintY : basePaint;
      lines.add(_ProjectedLine(start: start, end: end, paint: paint));
    }
  }

  for (final line in lines) {
    canvas.drawLine(line.start, line.end, line.paint);
  }
}

bool _vector4IsFinite(Vector4 value) {
  return value.x.isFinite &&
      value.y.isFinite &&
      value.z.isFinite &&
      value.w.isFinite;
}

class _ProjectedLine {
  _ProjectedLine({required this.start, required this.end, required this.paint});

  final Offset start;
  final Offset end;
  final Paint paint;
}
