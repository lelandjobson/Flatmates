import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../papercut/camera.dart';
import 'craft_collection.dart';
import 'folded_model.dart';
import 'model_painter.dart';

const Color _kGroundColor = Color(0xFF2A2A3C);
const Color _kWallColor = Color(0xFF3B3B52);
const Color _kEdgeColor = Color(0x33FFFFFF);
const Color _kGroundLineColor = Color(0x14FFFFFF);

/// Ground lines run this far apart on level surfaces.
const double _kGroundLineSpacing = 2;

/// One craft standing in a craft collection.
class CollectionCraft {
  const CollectionCraft({
    required this.model,
    this.decals = const [],
    this.finished = false,
    this.hover = 0,
    this.opacity = 1,
  });

  final FoldedModel model;
  final List<Decal> decals;

  /// Every island is wrapped, so it draws as paper instead of a ghost.
  final bool finished;

  /// 0–1 highlight while the reticle or pointer is on it.
  final double hover;
  final double opacity;
}

/// A craft collection: its surfaces and crafts, back to front.
///
/// Surfaces that can never cover a craft draw first, then the crafts and
/// the other surfaces by depth, then occluding geo seen from behind, faded,
/// so the crafts past it show through.
class CraftCollectionPainter extends CustomPainter {
  CraftCollectionPainter({
    required this.camera,
    required this.surfaces,
    required this.crafts,
    this.opacity = 1,
  });

  final PapercutCamera camera;
  final List<CollectionSurface> surfaces;
  final List<CollectionCraft> crafts;

  /// Multiplies every surface. Crafts carry their own.
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final view = camera.camera.viewMatrix;
    final eye = camera.camera.position;
    final models = [for (final craft in crafts) craft.model];
    final background = <_Item>[];
    final middle = <_Item>[];
    final front = <_Item>[];
    for (final surface in surfaces) {
      final item = _Item(
        depth: _depth(view, surface.rings.first),
        paint: () => _paintSurface(canvas, size, view, surface, eye),
      );
      if (isBackground(surface, eye, models)) {
        background.add(item);
      } else if (surface.category == SurfaceCategory.occludingGeo &&
          surface.side(eye) < 0) {
        front.add(item);
      } else {
        middle.add(item);
      }
    }
    for (final craft in crafts) {
      middle.add(
        _Item(
          depth: view.transformed3(craft.model.center).z,
          paint: () => _paintCraft(canvas, size, craft),
        ),
      );
    }
    for (final group in [background, middle, front]) {
      group.sort((a, b) => a.depth.compareTo(b.depth));
      for (final item in group) {
        item.paint();
      }
    }
  }

  void _paintSurface(
    Canvas canvas,
    Size size,
    Matrix4 view,
    CollectionSurface surface,
    Vector3 eye,
  ) {
    final alpha = opacity * surfaceOpacity(surface, eye);
    if (alpha <= 0.002) return;
    final path = Path()..fillType = PathFillType.evenOdd;
    var any = false;
    for (final ring in surface.rings) {
      final clipped = clipToNearPlane(ring, view, camera.camera.near);
      final screen = [
        for (final point in clipped) camera.camera.projectToScreen(point, size),
      ];
      if (screen.length < 3 || screen.any((point) => point == null)) continue;
      final points = screen.cast<Offset>();
      path.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
      any = true;
    }
    if (!any) return;
    final level = surface.normal.z.abs() > 0.99;
    final toEye = eye - surface.origin;
    final facing = toEye.length2 < 1e-12
        ? 1.0
        : surface.normal.dot(toEye.normalized()).abs();
    final base = level ? _kGroundColor : _kWallColor;
    final shade = Color.lerp(Colors.black, base, 0.7 + 0.3 * facing)!;
    canvas.drawPath(
      path,
      Paint()..color = shade.withValues(alpha: shade.a * alpha),
    );
    if (level) _paintGroundLines(canvas, size, view, surface, path, alpha);
    canvas.drawPath(
      path,
      Paint()
        ..color = _kEdgeColor.withValues(alpha: _kEdgeColor.a * alpha)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _paintGroundLines(
    Canvas canvas,
    Size size,
    Matrix4 view,
    CollectionSurface surface,
    Path outline,
    double alpha,
  ) {
    final ring = surface.rings.first;
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final point in ring) {
      minX = math.min(minX, point.x);
      minY = math.min(minY, point.y);
      maxX = math.max(maxX, point.x);
      maxY = math.max(maxY, point.y);
    }
    final z = surface.origin.z;
    final paint = Paint()
      ..color = _kGroundLineColor.withValues(alpha: _kGroundLineColor.a * alpha)
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipPath(outline);
    void line(Vector3 a, Vector3 b) {
      final clipped = clipToNearPlane([a, b], view, camera.camera.near);
      if (clipped.length < 2) return;
      final from = camera.camera.projectToScreen(clipped.first, size);
      final to = camera.camera.projectToScreen(clipped.last, size);
      if (from == null || to == null) return;
      canvas.drawLine(from, to, paint);
    }

    for (
      var x = (minX / _kGroundLineSpacing).ceil() * _kGroundLineSpacing;
      x <= maxX;
      x += _kGroundLineSpacing
    ) {
      line(Vector3(x, minY, z), Vector3(x, maxY, z));
    }
    for (
      var y = (minY / _kGroundLineSpacing).ceil() * _kGroundLineSpacing;
      y <= maxY;
      y += _kGroundLineSpacing
    ) {
      line(Vector3(minX, y, z), Vector3(maxX, y, z));
    }
    canvas.restore();
  }

  void _paintCraft(Canvas canvas, Size size, CollectionCraft craft) {
    if (craft.opacity <= 0.002) return;
    final model = craft.model;
    final painter = ModelPainter(
      camera: camera,
      model: model,
      decals: craft.decals,
      paperPoses: craft.finished
          ? {
              for (var i = 0; i < model.faces.length; i++)
                i: model.faces[i].toWorld,
            }
          : const {},
      highlight: craft.hover <= 0
          ? const {}
          : {for (var i = 0; i < model.faces.length; i++) i: craft.hover},
    );
    if (craft.opacity >= 1) {
      painter.paint(canvas, size);
      return;
    }
    canvas.saveLayer(
      Offset.zero & size,
      Paint()..color = Colors.white.withValues(alpha: craft.opacity),
    );
    painter.paint(canvas, size);
    canvas.restore();
  }

  double _depth(Matrix4 view, List<Vector3> ring) {
    var sum = 0.0;
    for (final point in ring) {
      sum += view.transformed3(point).z;
    }
    return ring.isEmpty ? 0 : sum / ring.length;
  }

  @override
  bool shouldRepaint(covariant CraftCollectionPainter oldDelegate) => true;
}

/// Sutherland–Hodgman clip of a world-space ring, or a segment, to the part
/// in front of the camera's near plane. The view looks down −z.
List<Vector3> clipToNearPlane(List<Vector3> ring, Matrix4 view, double near) {
  final limit = -near;
  final zs = [for (final point in ring) view.transformed3(point).z];
  if (zs.every((z) => z <= limit)) return ring;
  final out = <Vector3>[];
  final closed = ring.length > 2;
  final count = closed ? ring.length : ring.length - 1;
  for (var i = 0; i < count; i++) {
    final j = (i + 1) % ring.length;
    final a = ring[i];
    final b = ring[j];
    final aIn = zs[i] <= limit;
    final bIn = zs[j] <= limit;
    if (!closed && i == 0 && aIn) out.add(a);
    if (aIn && bIn) {
      out.add(b);
    } else if (aIn != bIn) {
      final t = (limit - zs[i]) / (zs[j] - zs[i]);
      out.add(a + (b - a) * t);
      if (bIn) out.add(b);
    }
  }
  return out;
}

class _Item {
  const _Item({required this.depth, required this.paint});

  final double depth;
  final VoidCallback paint;
}
