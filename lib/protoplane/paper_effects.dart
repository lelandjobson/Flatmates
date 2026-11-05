import 'dart:math' as math;
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;
import '../rendering/scene/scene.dart';
import 'completion.dart';
import 'models.dart';
import 'meshes.dart';

/// Material-specific overrides can be registered without changing gestures.
class PaperEffectProfile {
  const PaperEffectProfile({
    this.fallPixels = 80,
    this.tiltMin = 10,
    this.tiltMax = 30,
    this.shakePixels = 2,
  });
  final double fallPixels, tiltMin, tiltMax, shakePixels;
}

typedef PaperEffectResolver =
    PaperEffectProfile Function(PaperAction, PaperMaterial);

class PaperEffects extends ChangeNotifier {
  PaperEffects(
    TickerProvider vsync, {
    math.Random? random,
    PaperEffectResolver? resolve,
  }) : random = random ?? math.Random(),
       resolve = resolve ?? ((_, _) => const PaperEffectProfile()) {
    _ticker = vsync.createTicker(_tick);
    _program = ui.FragmentProgram.fromAsset(
      'shaders/paper_reveal.frag',
    ).then<ui.FragmentProgram?>((value) => value, onError: (Object _) => null);
  }
  final math.Random random;
  final PaperEffectResolver resolve;
  late final Ticker _ticker;
  late final Future<ui.FragmentProgram?> _program;
  final List<_Effect> _active = [];
  final Map<int, PaperCompletion> _pending = {};
  int _nextTicket = 0;
  int bakedSurfaces = 0;
  int _generation = 0;
  bool _disposed = false;
  Duration _elapsed = Duration.zero;
  Set<String> get hiddenIds => {
    for (final p in _pending.values) ...p.placedIds,
    for (final e in _active) ...e.completion.placedIds,
  };
  int get activeCount => _active.length;
  Offset get shake {
    var x = 0.0, y = 0.0;
    for (final e in _active) {
      final ms = (_elapsed - e.start).inMicroseconds / 1000;
      if (!e.shake || ms > 140) continue;
      final t = ms / 140;
      final a = e.profile.shakePixels * (1 - t) * (1 - t);
      x += math.sin(t * math.pi * 8) * a;
      y += math.sin(t * math.pi * 11) * a * .6;
    }
    return Offset(x.clamp(-2, 2), y.clamp(-2, 2));
  }

  Future<void> play(
    PaperCompletion completion, {
    required Duration duration,
    required bool shake,
    required bool reducedMotion,
  }) async {
    final generation = _generation;
    final ticket = _nextTicket++;
    bool conflicts(PaperCompletion prior) =>
        prior.placedIds.any(completion.affectedIds.contains);
    _active.removeWhere((e) {
      if (!conflicts(e.completion)) return false;
      e.dispose();
      return true;
    });
    _pending.removeWhere((_, prior) => conflicts(prior));
    final material =
        completion.paper.firstOrNull?.material ??
        completion.harvest?.patches.firstOrNull?.color ??
        PaperMaterial.paperWhite;
    final profile = resolve(completion.action, material);
    _pending[ticket] = completion;
    notifyListeners();
    if (completion.action == PaperAction.placement &&
        completion.paper.every((paper) => paper.kind != CraftKind.screen)) {
      // Placement is a screen-directed double wipe, with no baking or shader
      // startup delay. Existing removal/split effects keep their own behavior.
      if (!_ticker.isActive) {
        _elapsed = Duration.zero;
        _ticker.start();
      }
      _pending.remove(ticket);
      _active.add(
        _Effect(
          completion,
          [],
          _elapsed,
          const Duration(milliseconds: 200),
          profile,
          0,
          0,
          false,
          reducedMotion,
        ),
      );
      notifyListeners();
      return;
    }
    final surfaces = <_Surface>[];
    final batches = <List<_Surface>>[];
    try {
      final program = await _program;
      if (program == null) throw StateError('Paper effect shader unavailable');
      if (_disposed ||
          generation != _generation ||
          !_pending.containsKey(ticket)) {
        return;
      }
      final task = TimelineTask()..start('PaperEffectBake');
      try {
        final parts =
            completion.action == PaperAction.removal &&
                completion.paper.length > 1
            ? [
                for (final paper in completion.paper)
                  PaperCompletion(
                    action: completion.action,
                    plane: completion.frameFor(paper),
                    trace: completion.trace,
                    paper: [paper],
                  ),
              ]
            : [completion];
        for (final part in parts) {
          final batch = await _bake(part, program);
          if (part.harvest != null) {
            batches.addAll(batch.map((surface) => [surface]));
          } else {
            batches.add(batch);
          }
          surfaces.addAll(batch);
        }
        bakedSurfaces += surfaces.length;
      } finally {
        task.finish();
      }
      if (_disposed ||
          generation != _generation ||
          !_pending.containsKey(ticket)) {
        for (final surface in surfaces) {
          surface.dispose();
        }
        return;
      }
      if (!_ticker.isActive) {
        _elapsed = Duration.zero;
        _ticker.start();
      }
      _pending.remove(ticket);
      for (final batch in batches) {
        _active.add(
          _Effect(
            completion,
            batch,
            _elapsed,
            reducedMotion ? const Duration(milliseconds: 100) : duration,
            profile,
            (profile.tiltMin +
                    random.nextDouble() * (profile.tiltMax - profile.tiltMin)) *
                math.pi /
                180,
            random.nextDouble() * math.pi * 2,
            shake && !reducedMotion,
            reducedMotion,
          ),
        );
      }
      notifyListeners();
    } catch (_) {
      for (final surface in surfaces) {
        surface.dispose();
      }
      if (!_disposed && generation == _generation) {
        _pending.remove(ticket);
        notifyListeners();
      }
    }
  }

  void _tick(Duration elapsed) {
    _elapsed = elapsed;
    _active.removeWhere((e) {
      if (elapsed - e.start < e.duration) return false;
      e.dispose();
      return true;
    });
    if (_active.isEmpty) _ticker.stop();
    notifyListeners();
  }

  void clear() {
    _generation++;
    for (final e in _active) {
      e.dispose();
    }
    _active.clear();
    _pending.clear();
    _ticker.stop();
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    clear();
    _ticker.dispose();
    super.dispose();
  }
}

class _Effect {
  _Effect(
    this.completion,
    this.surfaces,
    this.start,
    this.duration,
    this.profile,
    this.angle,
    this.axis,
    this.shake,
    this.reduced,
  );
  final PaperCompletion completion;
  final List<_Surface> surfaces;
  final Duration start, duration;
  final PaperEffectProfile profile;
  final double angle, axis;
  final bool shake, reduced;
  void dispose() {
    for (final surface in surfaces) {
      surface.dispose();
    }
  }
}

class _Polygon {
  _Polygon(this.points, this.material, this.color);
  final List<Offset> points;
  final PaperMaterial material;
  final Color color;
}

class _Group {
  _Group(this.origin, this.u, this.v, this.normal);
  final Vector3 origin, u, v, normal;
  final List<_Polygon> polygons = [];
}

class _Surface {
  _Surface(this.group, this.bounds, this.image, this.mask, this.shader);
  final _Group group;
  final Rect bounds;
  final ui.Image image, mask;
  final ui.FragmentShader shader;
  void dispose() {
    shader.dispose();
    image.dispose();
    mask.dispose();
  }
}

Future<List<_Surface>> _bake(
  PaperCompletion completion,
  ui.FragmentProgram program,
) async {
  final groups = <String, _Group>{};
  void add(List<Vector3> vertices, PaperMaterial material, Color color) {
    if (vertices.length < 3) return;
    final normal = completion.harvest != null
        ? Vector3.copy(completion.plane.normal)
        : (vertices[1] - vertices[0]).cross(vertices[2] - vertices[0]);
    if (normal.length2 < 1e-14) return;
    normal.normalize();
    // Coplanar slabs share one reveal field; keep material UV orientation.
    final d = normal.dot(vertices.first);
    final key =
        '${(normal.x.abs() < 1e-6 ? 0.0 : normal.x).toStringAsFixed(5)}/${(normal.y.abs() < 1e-6 ? 0.0 : normal.y).toStringAsFixed(5)}/${(normal.z.abs() < 1e-6 ? 0.0 : normal.z).toStringAsFixed(5)}/${d.toStringAsFixed(5)}';
    final group = groups.putIfAbsent(key, () {
      var u = Vector3.copy(completion.plane.u);
      u -= normal * normal.dot(u);
      if (u.length2 < 1e-8) {
        u = normal.x.abs() < .9 ? Vector3(1, 0, 0) : Vector3(0, 1, 0);
        u -= normal * normal.dot(u);
      }
      u.normalize();
      return _Group(normal * d, u, normal.cross(u)..normalize(), normal);
    });
    group.polygons.add(
      _Polygon(
        [for (final p in vertices) Offset(p.dot(group.u), p.dot(group.v))],
        material,
        color,
      ),
    );
  }

  if (completion.harvest case final harvest?) {
    for (final patch in harvest.patches) {
      add(
        patch.region.outer.map((p) => completion.plane.point(p, .001)).toList(),
        patch.color,
        patch.color.base,
      );
    }
  } else {
    for (final paper in completion.paper) {
      for (final mesh in objectMeshes(paper, completion.frameFor(paper))) {
        for (final face in mesh.geometry.faces) {
          add(
            face.map((i) => mesh.geometry.vertices[i]).toList(),
            paper.material,
            paper.material.base,
          );
        }
      }
    }
  }
  final surfaces = <_Surface>[];
  ui.Image? pendingImage, pendingMask;
  try {
    for (final group in groups.values) {
      var bounds = Rect.fromPoints(
        group.polygons.first.points.first,
        group.polygons.first.points.first,
      );
      for (final polygon in group.polygons) {
        for (final p in polygon.points) {
          bounds = bounds.expandToInclude(Rect.fromPoints(p, p));
        }
      }
      if (bounds.width < 1e-7 || bounds.height < 1e-7) continue;
      final w = (bounds.width * 256).ceil().clamp(16, 512);
      final h = (bounds.height * 256).ceil().clamp(16, 512);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)
        ..scale(w / bounds.width, h / bounds.height)
        ..translate(-bounds.left, -bounds.top);
      for (final polygon in group.polygons) {
        canvas.drawPath(
          Path()..addPolygon(polygon.points, true),
          Paint()
            ..isAntiAlias = false
            ..color = polygon.color,
        );
      }
      final picture = recorder.endRecording();
      final image = picture.toImageSync(w, h);
      pendingImage = image;
      picture.dispose();
      if (completion.action == PaperAction.removal) {
        final harvest = completion.harvest;
        final partial =
            harvest != null &&
            harvest.patches.fold<double>(
                  0,
                  (sum, patch) => sum + patch.region.area,
                ) <
                harvest.outline.area - 1e-7;
        final pieces = partial
            ? await _rasterPieces(image, bounds)
            : [(image, bounds)];
        for (final piece in pieces) {
          final emptyRecorder = ui.PictureRecorder();
          Canvas(emptyRecorder).drawColor(Colors.white, BlendMode.src);
          final emptyPicture = emptyRecorder.endRecording();
          final mask = emptyPicture.toImageSync(1, 1);
          emptyPicture.dispose();
          surfaces.add(
            _Surface(group, piece.$2, piece.$1, mask, program.fragmentShader()),
          );
        }
        pendingImage = null;
        continue;
      }
      // Raster coverage removes internal slab boundaries; a distance transform
      // is baked once, including hole boundaries, not evaluated per frame.
      final rgba = await image.toByteData();
      if (rgba == null) {
        image.dispose();
        pendingImage = null;
        continue;
      }
      final distances = Float32List(w * h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          distances[i] = rgba.getUint8(i * 4 + 3) == 0
              ? 0
              : math
                    .min(math.min(x + 1, w - x), math.min(y + 1, h - y))
                    .toDouble();
        }
      }
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          if (x > 0) {
            distances[i] = math.min(distances[i], distances[i - 1] + 1);
          }
          if (y > 0) {
            distances[i] = math.min(distances[i], distances[i - w] + 1);
          }
          if (x > 0 && y > 0) {
            distances[i] = math.min(
              distances[i],
              distances[i - w - 1] + math.sqrt2,
            );
          }
          if (x + 1 < w && y > 0) {
            distances[i] = math.min(
              distances[i],
              distances[i - w + 1] + math.sqrt2,
            );
          }
        }
      }
      for (var y = h - 1; y >= 0; y--) {
        for (var x = w - 1; x >= 0; x--) {
          final i = y * w + x;
          if (x + 1 < w) {
            distances[i] = math.min(distances[i], distances[i + 1] + 1);
          }
          if (y + 1 < h) {
            distances[i] = math.min(distances[i], distances[i + w] + 1);
          }
          if (x + 1 < w && y + 1 < h) {
            distances[i] = math.min(
              distances[i],
              distances[i + w + 1] + math.sqrt2,
            );
          }
          if (x > 0 && y + 1 < h) {
            distances[i] = math.min(
              distances[i],
              distances[i + w - 1] + math.sqrt2,
            );
          }
        }
      }
      final maxDistance = distances.fold<double>(1, math.max);
      final bytes = Uint8List(w * h * 4);
      for (var i = 0; i < distances.length; i++) {
        bytes[i * 4] = (distances[i] / maxDistance * 255).round();
        bytes[i * 4 + 3] = 255;
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: w,
        height: h,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final mask = (await codec.getNextFrame()).image;
      pendingMask = mask;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      surfaces.add(
        _Surface(group, bounds, image, mask, program.fragmentShader()),
      );
      pendingImage = pendingMask = null;
    }
    return surfaces;
  } catch (_) {
    pendingImage?.dispose();
    pendingMask?.dispose();
    for (final surface in surfaces) {
      surface.dispose();
    }
    rethrow;
  }
}

/// Separate islands in a partially harvested sheet using its baked coverage.
/// This is visual-only raster topology; exact polygon areas still award inventory.
Future<List<(ui.Image, Rect)>> _rasterPieces(
  ui.Image image,
  Rect bounds,
) async {
  final data = await image.toByteData();
  if (data == null) return [(image, bounds)];
  final w = image.width, h = image.height;
  final seen = Uint8List(w * h);
  final components = <List<int>>[];
  for (var start = 0; start < seen.length; start++) {
    if (seen[start] != 0 || data.getUint8(start * 4 + 3) == 0) continue;
    final queue = <int>[start];
    seen[start] = 1;
    for (var head = 0; head < queue.length; head++) {
      final i = queue[head], x = i % w, y = i ~/ w;
      for (final next in [
        if (x > 0) i - 1,
        if (x + 1 < w) i + 1,
        if (y > 0) i - w,
        if (y + 1 < h) i + w,
      ]) {
        if (seen[next] != 0 || data.getUint8(next * 4 + 3) == 0) continue;
        seen[next] = 1;
        queue.add(next);
      }
    }
    components.add(queue);
  }
  if (components.length < 2) return [(image, bounds)];
  final result = <(ui.Image, Rect)>[];
  try {
    for (final pixels in components) {
      var left = w, top = h, right = 0, bottom = 0;
      for (final i in pixels) {
        left = math.min(left, i % w);
        right = math.max(right, i % w);
        top = math.min(top, i ~/ w);
        bottom = math.max(bottom, i ~/ w);
      }
      final width = right - left + 1, height = bottom - top + 1;
      final bytes = Uint8List(width * height * 4);
      for (final i in pixels) {
        final dest = ((i ~/ w - top) * width + i % w - left) * 4;
        for (var c = 0; c < 4; c++) {
          bytes[dest + c] = data.getUint8(i * 4 + c);
        }
      }
      final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
      final descriptor = ui.ImageDescriptor.raw(
        buffer,
        width: width,
        height: height,
        pixelFormat: ui.PixelFormat.rgba8888,
      );
      final codec = await descriptor.instantiateCodec();
      final piece = (await codec.getNextFrame()).image;
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
      result.add((
        piece,
        Rect.fromLTWH(
          bounds.left + left / w * bounds.width,
          bounds.top + top / h * bounds.height,
          width / w * bounds.width,
          height / h * bounds.height,
        ),
      ));
    }
    image.dispose();
    return result;
  } catch (_) {
    for (final piece in result) {
      piece.$1.dispose();
    }
    rethrow;
  }
}

class PaperEffectsPainter extends CustomPainter {
  PaperEffectsPainter(
    this.effects,
    this.scene, {
    Color? lineColor,
    this.landscapeFilter,
    this.craftedFilter,
  }) : _lineColor = lineColor,
       super(repaint: Listenable.merge([effects, scene]));
  final PaperEffects effects;
  final Scene scene;
  final ColorFilter? landscapeFilter, craftedFilter;
  final Color? _lineColor;
  Color get lineColor => _lineColor ?? const Color(0xff7fff00);
  @override
  void paint(Canvas canvas, Size size) {
    Timeline.startSync('PaperEffectsPainter');
    try {
      _paint(canvas, size);
    } finally {
      Timeline.finishSync();
    }
  }

  void _paint(Canvas canvas, Size size) {
    final camera = scene.camera;
    if (camera == null || size.isEmpty) return;
    final vp =
        camera.projectionMatrix(size.width / size.height) * camera.viewMatrix;
    final viewport = Matrix4.identity()
      ..setEntry(0, 0, size.width / 2)
      ..setEntry(1, 1, -size.height / 2)
      ..setEntry(0, 3, size.width / 2)
      ..setEntry(1, 3, size.height / 2);
    for (final effect in effects._active) {
      final t =
          ((effects._elapsed - effect.start).inMicroseconds /
                  effect.duration.inMicroseconds)
              .clamp(0.0, 1.0);
      if (effect.completion.action == PaperAction.placement &&
          effect.surfaces.isEmpty) {
        for (final paper in effect.completion.paper) {
          final path = Path()..fillType = PathFillType.evenOdd;
          for (final ring in paper.region.rings) {
            final points = <Offset>[];
            for (final point in ring) {
              final screen = camera.projectToScreen(
                effect.completion
                    .frameFor(paper)
                    .point(point, paper.depth + .003),
                size,
              );
              if (screen != null) points.add(screen);
            }
            if (points.length >= 3) path.addPolygon(points, true);
          }
          final bounds = path.getBounds();
          if (bounds.isEmpty) continue;
          final color = paperColors[paper.color] ?? paper.material.base;
          canvas.save();
          canvas.clipPath(path);
          if (effect.reduced) {
            canvas.drawPath(
              path,
              Paint()
                ..color = Color.lerp(Colors.white, color, t)!
                ..colorFilter = craftedFilter,
            );
          } else {
            void fill(Color color, double progress, {ColorFilter? filter}) {
              canvas.drawRect(
                Rect.fromLTRB(
                  bounds.left,
                  bounds.bottom - bounds.height * progress,
                  bounds.right,
                  bounds.bottom,
                ),
                Paint()
                  ..color = color
                  ..colorFilter = filter,
              );
            }

            fill(Colors.white, (t * 2).clamp(0.0, 1.0));
            if (t >= .5) {
              fill(
                color,
                ((t - .5) * 2).clamp(0.0, 1.0),
                filter: craftedFilter,
              );
            }
          }
          canvas.restore();
        }
        continue;
      }
      if (effect.completion.action == PaperAction.split) {
        final path = Path();
        for (final (i, point) in effect.completion.trace.indexed) {
          final screen = camera.projectToScreen(
            effect.completion.plane.point(point, .01),
            size,
          );
          if (screen == null) continue;
          if (i == 0) {
            path.moveTo(screen.dx, screen.dy);
          } else {
            path.lineTo(screen.dx, screen.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = lineColor.withValues(alpha: 1 - t)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
        );
        continue;
      }
      final removal = effect.completion.action == PaperAction.removal;
      final center = Vector3.zero();
      for (final surface in effect.surfaces) {
        center.add(
          surface.group.origin +
              surface.group.u * surface.bounds.center.dx +
              surface.group.v * surface.bounds.center.dy,
        );
      }
      if (effect.surfaces.isNotEmpty) center.scale(1 / effect.surfaces.length);
      final transform = Matrix4.identity()..translateByVector3(center);
      if (removal && !effect.reduced) {
        transform.rotate(
          Vector3(math.cos(effect.axis), 0, math.sin(effect.axis)),
          effect.angle * Curves.easeIn.transform(t),
        );
      }
      transform.translateByVector3(-center);
      final opacity = removal
          ? (effect.reduced ? 1 - t : (1 - (t - .3) / .7).clamp(0.0, 1.0))
          : 1.0;
      final surfaces = effect.surfaces.toList()
        ..sort((a, b) {
          final ac = transform.transformed3(
            a.group.origin +
                a.group.u * a.bounds.center.dx +
                a.group.v * a.bounds.center.dy,
          );
          final bc = transform.transformed3(
            b.group.origin +
                b.group.u * b.bounds.center.dx +
                b.group.v * b.bounds.center.dy,
          );
          return camera.viewMatrix
              .transformed3(ac)
              .z
              .compareTo(camera.viewMatrix.transformed3(bc).z);
        });
      canvas.save();
      final appearance = effect.completion.harvest != null
          ? landscapeFilter
          : craftedFilter;
      if (appearance != null) {
        canvas.saveLayer(Offset.zero & size, Paint()..colorFilter = appearance);
      }
      if (removal && !effect.reduced) {
        canvas.translate(0, effect.profile.fallPixels * t * t);
      }
      for (final surface in surfaces) {
        final g = surface.group, bounds = surface.bounds;
        final origin = g.origin + g.u * bounds.left + g.v * bounds.top;
        final basis = Matrix4.identity()
          ..setColumn(
            0,
            Vector4(
              g.u.x * bounds.width / surface.image.width,
              g.u.y * bounds.width / surface.image.width,
              g.u.z * bounds.width / surface.image.width,
              0,
            ),
          )
          ..setColumn(
            1,
            Vector4(
              g.v.x * bounds.height / surface.image.height,
              g.v.y * bounds.height / surface.image.height,
              g.v.z * bounds.height / surface.image.height,
              0,
            ),
          )
          ..setColumn(3, Vector4(origin.x, origin.y, origin.z, 1));
        final world = transform * basis;
        final view = camera.viewMatrix * world;
        if ([
          Offset.zero,
          Offset(surface.image.width.toDouble(), 0),
          Offset(0, surface.image.height.toDouble()),
          Offset(
            surface.image.width.toDouble(),
            surface.image.height.toDouble(),
          ),
        ].any(
          (p) => view.transformed3(Vector3(p.dx, p.dy, 0)).z > -camera.near,
        )) {
          continue;
        }
        var normal =
            transform.transformed3(g.normal) -
            transform.transformed3(Vector3.zero());
        if (normal.dot(camera.position - origin) < 0) normal = -normal;
        var shade = scene.globalIllumination;
        for (final light in scene.lights) {
          shade += math.max(0, normal.dot(-light.direction)) * light.intensity;
        }
        shade = shade.clamp(0, 1);
        canvas.save();
        canvas.transform((viewport * vp * world).storage);
        if (removal || effect.reduced) {
          canvas.drawImage(
            surface.image,
            Offset.zero,
            Paint()
              ..color = Colors.white.withValues(
                alpha: opacity * (removal ? 1 : t),
              )
              ..colorFilter = ColorFilter.mode(
                Color.fromRGBO(
                  (shade * 255).round(),
                  (shade * 255).round(),
                  (shade * 255).round(),
                  1,
                ),
                BlendMode.modulate,
              )
              ..filterQuality = FilterQuality.low,
          );
        } else {
          surface.shader
            ..setFloat(0, surface.image.width.toDouble())
            ..setFloat(1, surface.image.height.toDouble())
            ..setFloat(2, t)
            ..setFloat(3, shade)
            ..setImageSampler(0, surface.image)
            ..setImageSampler(1, surface.mask);
          canvas.drawRect(
            Rect.fromLTWH(
              0,
              0,
              surface.image.width.toDouble(),
              surface.image.height.toDouble(),
            ),
            Paint()..shader = surface.shader,
          );
        }
        canvas.restore();
      }
      if (appearance != null) canvas.restore();
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(PaperEffectsPainter old) =>
      old.lineColor != lineColor ||
      old.effects != effects ||
      old.scene != scene ||
      old.landscapeFilter != landscapeFilter ||
      old.craftedFilter != craftedFilter;
}
