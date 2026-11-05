import 'dart:ui';
import '../rendering/mesh.dart';
import '../rendering/surface_edge_shading.dart';
import 'geometry.dart';
import 'models.dart';
import 'pencil.dart';

/// Tile rasterization depends on exact local geometry only, never the camera.
/// 32 × 256² RGBA = 8 MiB. Mesh bindings are released before eviction.
class PencilTextureCache {
  final _images = <String, Image>{};
  final _bound = <Mesh>[];
  final _used = <String>{};
  static const resolution = 256, capacity = 32, renderVersion = 2;
  int bakeCount = 0;
  int get retainedBytes => _images.length * resolution * resolution * 4;
  void beginFrame() {
    for (final mesh in _bound) {
      mesh.pencilShades = const {};
    }
    _bound.clear();
    _used.clear();
  }

  void attach(
    List<Mesh> meshes,
    CraftPlane source,
    Region region,
    double depth,
    List<PencilSegment> segments, {
    required double opacity,
  }) {
    if (segments.isEmpty) return;
    final tiles = <SurfaceEdgeShade>[];
    final bounds = region.bounds;
    for (var x = bounds.left.floor(); x < bounds.right.ceil(); x++) {
      for (var y = bounds.top.floor(); y < bounds.bottom.ceil(); y++) {
        final tile = Rect.fromLTWH(x.toDouble(), y.toDouble(), 1, 1);
        final parts = clipPencil(
          segments,
          Region([
            tile.topLeft,
            tile.topRight,
            tile.bottomRight,
            tile.bottomLeft,
          ]),
        );
        if (parts.isEmpty) continue;
        final key =
            '$renderVersion/${parts.map((s) => s.toJson().map((v) => (v * 1e7).round()).join(',')).join(';')}';
        var image = _images.remove(key);
        if (image == null) {
          if (_images.length >= capacity) {
            final victim = _images.keys
                .where((k) => !_used.contains(k))
                .firstOrNull;
            if (victim == null) {
              tiles.add(
                SurfaceEdgeShade.vector(
                  source.point(Offset.zero, depth),
                  source.u,
                  source.v,
                  tile,
                  (canvas) => paintPencil(canvas, parts),
                ),
              );
              continue;
            }
            _images.remove(victim)!.dispose();
          }
          final recorder = PictureRecorder();
          // Keep the recorder owning this canvas explicit for deterministic disposal.
          final tileCanvas = Canvas(recorder);
          tileCanvas.scale(resolution.toDouble());
          tileCanvas.translate(-x.toDouble(), -y.toDouble());
          paintPencil(tileCanvas, parts);
          final picture = recorder.endRecording();
          image = picture.toImageSync(resolution, resolution);
          picture.dispose();
          bakeCount++;
        }
        _images[key] = image;
        _used.add(key);
        tiles.add(
          SurfaceEdgeShade(
            image,
            source.point(Offset.zero, depth),
            source.u,
            source.v,
            tile,
            false,
          ),
        );
      }
    }
    for (final mesh in meshes) {
      final faces = <int, List<SurfaceEdgeShade>>{};
      for (var i = 0; i < mesh.geometry.faces.length; i++) {
        final face = mesh.geometry.faces[i];
        if (face.every(
          (v) =>
              ((mesh.geometry.vertices[v] - source.origin).dot(source.normal) -
                      depth)
                  .abs() <
              1e-6,
        )) {
          faces[i] = tiles;
        }
      }
      mesh.pencilShades = faces;
      mesh.pencilOpacity = opacity;
      _bound.add(mesh);
    }
  }

  void dispose() {
    beginFrame();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
  }
}

/// Coordinate-hashed ink stays stable across redraws, segment reversal and
/// clipping. Irregular knots alternate flat runs and small linear kinks.
double _inkNoise(int cell, int seed, int salt) {
  var n =
      (cell * 0x1f123bb5 ^ seed * 0x5f356495 ^ salt * 0x45d9f3b) & 0x7fffffff;
  n = ((n ^ (n >> 16)) * 0x45d9f3b) & 0x7fffffff;
  n = ((n ^ (n >> 16)) * 0x45d9f3b) & 0x7fffffff;
  return (n ^ (n >> 16)) / 0x7fffffff;
}

(Offset, double, double) graphiteSample(PencilSegment segment, Offset p) {
  var axis = (segment.b - segment.a) / segment.length;
  if (axis.dx < -geometryEpsilon ||
      (axis.dx.abs() < geometryEpsilon && axis.dy < 0)) {
    axis = -axis;
  }
  final normal = Offset(-axis.dy, axis.dx);
  final seed =
      ((p.dx * normal.dx + p.dy * normal.dy) * 100000).round() ^
      (axis.dx * 1000).round();
  final along = p.dx * axis.dx + p.dy * axis.dy;
  const spacing = .035;
  double knot(int cell) =>
      (cell + .15 + .55 * _inkNoise(cell, seed, 1)) * spacing;
  double offset(int cell) {
    final block = (cell / 4).floor();
    if (_inkNoise(block, seed, 2) < .45) {
      return (_inkNoise(block, seed, 3) * 2 - 1) * .0004;
    }
    return (_inkNoise(cell, seed, 4) * 2 - 1) * .0015;
  }

  var cell = (along / spacing).floor();
  if (along < knot(cell)) cell--;
  final t = ((along - knot(cell)) / (knot(cell + 1) - knot(cell))).clamp(
    0.0,
    1.0,
  );
  final jitter = offset(cell) * (1 - t) + offset(cell + 1) * t;
  final grainCell = (along / .006).floor();
  return (
    p + normal * jitter,
    .58 + .4 * _inkNoise(grainCell, seed, 5),
    .0028 + .0014 * _inkNoise(grainCell, seed, 6),
  );
}

void paintPencil(Canvas canvas, List<PencilSegment> segments) {
  final paint = Paint()..strokeCap = StrokeCap.round;
  for (final s in segments) {
    final d = s.b - s.a, length = d.distance;
    if (length < geometryEpsilon) continue;
    final steps = (length * 160).ceil();
    for (var i = 0; i < steps; i++) {
      final p = graphiteSample(s, s.a + d * (i / steps));
      final q = graphiteSample(s, s.a + d * ((i + 1) / steps));
      final ink = graphiteSample(s, s.a + d * ((i + .5) / steps));
      paint
        ..color = Color.fromRGBO(45, 45, 45, ink.$2)
        ..strokeWidth = ink.$3;
      canvas.drawLine(p.$1, q.$1, paint);
    }
  }
}
