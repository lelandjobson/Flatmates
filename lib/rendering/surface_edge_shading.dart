import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:vector_math/vector_math_64.dart';

import '../geometry/geometry.dart';
import 'mesh.dart';

/// Soft, local edge shading, not scene-wide ambient occlusion. Coplanar faces
/// share one outline so triangulation/slab seams never receive a shadow.
class SurfaceEdgeShade {
  SurfaceEdgeShade(
    this.image,
    this.origin,
    this.u,
    this.v,
    this.bounds,
    this.rectangular,
  ) : vectorPaint = null;
  SurfaceEdgeShade.vector(
    this.origin,
    this.u,
    this.v,
    this.bounds,
    this.vectorPaint,
  ) : image = null,
      rectangular = false;
  final void Function(ui.Canvas)? vectorPaint;
  final ui.Image? image;
  final Vector3 origin, u, v;
  final ui.Rect bounds;
  final bool rectangular;

  Matrix4 get basis => Matrix4.identity()
    ..setColumn(0, Vector4(u.x, u.y, u.z, 0))
    ..setColumn(1, Vector4(v.x, v.y, v.z, 0))
    ..setColumn(3, Vector4(origin.x, origin.y, origin.z, 1));

  void paint(ui.Canvas canvas, double opacity) {
    if (image == null) {
      canvas.saveLayer(
        bounds,
        ui.Paint()..color = ui.Color.fromRGBO(255, 255, 255, opacity),
      );
      canvas.clipRect(bounds);
      vectorPaint!(canvas);
      canvas.restore();
      return;
    }
    final paint = ui.Paint()
      ..color = ui.Color.fromRGBO(255, 255, 255, opacity)
      ..filterQuality = ui.FilterQuality.low;
    if (rectangular) {
      // Nine-slicing preserves a world-space band width as a cap is extruded.
      // All rectangular caps and sidewalls share this single 48×48 texture.
      const scale = SurfaceEdgeShadingCache.bandWidth / 16;
      canvas.save();
      canvas.scale(scale);
      canvas.drawImageNine(
        image!,
        const ui.Rect.fromLTRB(16, 16, 32, 32),
        ui.Rect.fromLTRB(
          bounds.left / scale,
          bounds.top / scale,
          bounds.right / scale,
          bounds.bottom / scale,
        ),
        paint,
      );
      canvas.restore();
    } else {
      canvas.drawImageRect(
        image!,
        ui.Rect.fromLTWH(
          0,
          0,
          image!.width.toDouble(),
          image!.height.toDouble(),
        ),
        bounds,
        paint,
      );
    }
  }
}

/// Owned by a view, not the renderer's paint loop. Camera motion and material
/// changes reuse masks. Geometry edits rebuild only changed surface profiles.
/// Unused images are released on synchronization; irregular masks have an 8 MiB
/// budget, and each dimension is capped at 512 pixels.
class SurfaceEdgeShadingCache {
  SurfaceEdgeShadingCache({this.maxBytes = 8 * 1024 * 1024});
  static const bandWidth = .025;
  final int maxBytes;
  final _meshes = <String, (String, List<_Surface>)>{};
  final _masks = <String, ui.Image>{};
  List<Mesh> _boundMeshes = [];
  ui.Image? _rectangle;
  int bakedMasks = 0;
  int get retainedBytes =>
      _masks.values.fold(
        0,
        (sum, image) => sum + image.width * image.height * 4,
      ) +
      (_rectangle == null ? 0 : 48 * 48 * 4);

  void synchronize(Iterable<Mesh> meshes) {
    for (final mesh in _boundMeshes) {
      mesh.edgeShades = const {};
    }
    final enabled = meshes.where((m) => m.shadeEdges).toList();
    _boundMeshes = enabled;
    final ids = <String>{}, used = <String>{};
    for (final mesh in enabled) {
      ids.add(mesh.id);
      final geometry = mesh.geometry;
      final signature =
          '${geometry.vertices.map((v) => '${v.x},${v.y},${v.z}').join(';')}/${geometry.faces.map((f) => f.join(',')).join(';')}';
      if (_meshes[mesh.id]?.$1 != signature) {
        _meshes[mesh.id] = (signature, _surfaces(geometry));
      }
      for (final surface in _meshes[mesh.id]!.$2) {
        if (!surface.rectangular) used.add(surface.key);
      }
    }
    _meshes.removeWhere((id, _) => !ids.contains(id));
    _masks.removeWhere((key, image) {
      if (used.contains(key)) return false;
      image.dispose();
      return true;
    });
    for (final mesh in enabled) {
      final shades = <int, SurfaceEdgeShade>{};
      for (final surface in _meshes[mesh.id]!.$2) {
        ui.Image? image;
        if (surface.rectangular) {
          image = _rectangle ??= _bake(
            ui.Path()..addRect(const ui.Rect.fromLTWH(0, 0, 48, 48)),
            const ui.Rect.fromLTWH(0, 0, 48, 48),
            48,
            48,
            16,
          );
        } else {
          image = _masks[surface.key];
          if (image == null) {
            final bounds = surface.bounds;
            final w = (bounds.width * 384).ceil().clamp(16, 512);
            final h = (bounds.height * 384).ceil().clamp(16, 512);
            if (retainedBytes + w * h * 4 > maxBytes) continue;
            var outline = ui.Path();
            for (final polygon in surface.polygons) {
              outline = ui.Path.combine(
                ui.PathOperation.union,
                outline,
                ui.Path()..addPolygon(polygon, true),
              );
            }
            image = _masks[surface.key] = _bake(
              outline,
              bounds,
              w,
              h,
              bandWidth,
            );
          }
        }
        final shade = SurfaceEdgeShade(
          image,
          surface.origin,
          surface.u,
          surface.v,
          surface.bounds,
          surface.rectangular,
        );
        for (final face in surface.faces) {
          shades[face] = shade;
        }
      }
      mesh.edgeShades = shades;
    }
    if (enabled.isEmpty) {
      _rectangle?.dispose();
      _rectangle = null;
    }
  }

  ui.Image _bake(ui.Path outline, ui.Rect bounds, int w, int h, double width) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)
      ..scale(w / bounds.width, h / bounds.height)
      ..translate(-bounds.left, -bounds.top)
      ..clipPath(outline, doAntiAlias: false);
    // Blur is paid once per outline, never on a camera frame. The narrow band
    // at the actual material boundary leaves the face's interior unchanged.
    canvas.drawPath(
      outline,
      ui.Paint()
        ..color = const ui.Color(0x990b1018)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = width * .45
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, width * .28),
    );
    final picture = recorder.endRecording();
    final image = picture.toImageSync(w, h);
    picture.dispose();
    bakedMasks++;
    return image;
  }

  void clear() {
    for (final mesh in _boundMeshes) {
      mesh.edgeShades = const {};
    }
    _boundMeshes = [];
    for (final image in _masks.values) {
      image.dispose();
    }
    _masks.clear();
    _meshes.clear();
    _rectangle?.dispose();
    _rectangle = null;
  }

  void dispose() => clear();
}

class _Surface {
  _Surface(this.origin, this.u, this.v);
  Vector3 origin;
  final Vector3 u, v;
  final faces = <int>[];
  List<List<ui.Offset>> polygons = [];
  late ui.Rect bounds;
  late String key;
  bool rectangular = false;

  void finish() {
    bounds = ui.Rect.fromPoints(polygons.first.first, polygons.first.first);
    for (final point in polygons.expand((p) => p)) {
      bounds = bounds.expandToInclude(ui.Rect.fromPoints(point, point));
    }
    final offset = bounds.topLeft;
    origin += u * offset.dx + v * offset.dy;
    polygons = [
      for (final polygon in polygons)
        [for (final point in polygon) point - offset],
    ];
    bounds = ui.Offset.zero & bounds.size;
    // A single axis-aligned quadrilateral can use the shared nine-slice mask.
    // Other shapes use their union, including concavity and all cutout edges.
    rectangular =
        polygons.length == 1 &&
        polygons.single.length == 4 &&
        polygons.single.every(
          (p) =>
              (p.dx.abs() < 1e-7 || (p.dx - bounds.width).abs() < 1e-7) &&
              (p.dy.abs() < 1e-7 || (p.dy - bounds.height).abs() < 1e-7),
        );
    key = polygons
        .map(
          (p) => p
              .map(
                (v) => '${v.dx.toStringAsFixed(6)},${v.dy.toStringAsFixed(6)}',
              )
              .join(';'),
        )
        .join('/');
  }
}

List<_Surface> _surfaces(Geometry geometry) {
  final groups = <String, _Surface>{};
  for (var i = 0; i < geometry.faces.length; i++) {
    final points = geometry.faces[i].map((j) => geometry.vertices[j]).toList();
    if (points.length < 3) continue;
    var normal = Vector3.zero();
    for (var j = 1; j + 1 < points.length; j++) {
      normal = (points[j] - points.first).cross(points[j + 1] - points.first);
      if (normal.length2 > 1e-14) break;
    }
    if (normal.length2 < 1e-14) continue;
    normal.normalize();
    // Opposite winding on a coplanar face still belongs to the same surface.
    final axis = normal.x.abs() >= math.max(normal.y.abs(), normal.z.abs())
        ? 0
        : normal.y.abs() >= normal.z.abs()
        ? 1
        : 2;
    if (normal[axis] < 0) normal = -normal;
    final distance = normal.dot(points.first);
    String quantize(double n) => (n.abs() < 1e-6 ? 0.0 : n).toStringAsFixed(6);
    final key =
        '${quantize(normal.x)}/${quantize(normal.y)}/${quantize(normal.z)}/${quantize(distance)}';
    final surface = groups.putIfAbsent(key, () {
      final u = (points[1] - points.first).normalized();
      return _Surface(normal * distance, u, normal.cross(u).normalized());
    });
    surface.faces.add(i);
    surface.polygons.add([
      for (final point in points)
        ui.Offset(point.dot(surface.u), point.dot(surface.v)),
    ]);
  }
  return groups.values.toList()..removeWhere((surface) {
    surface.finish();
    return surface.bounds.width < 1e-7 || surface.bounds.height < 1e-7;
  });
}
