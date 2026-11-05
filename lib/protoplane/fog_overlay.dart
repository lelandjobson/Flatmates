import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/scheduler.dart';
import '../rendering/scene/camera.dart';
import 'controller.dart';
import 'discovery.dart';
import 'fog_settings.dart';

class FogDiagnostics {
  static int shaderPaints = 0, fallbackPaints = 0;
  static Object? shaderError;
}

/// One mask rebuild per geographic/discovery change, never per camera frame.
class FogField {
  FogField(Iterable<WorldArea> definitions, Set<String> revealed)
    : areas = List.of(definitions),
      known = Set.of(revealed) {
    bounds = areas
        .map((a) => a.bounds)
        .reduce((a, b) => a.expandToInclude(b))
        .inflate(12);
  }
  final List<WorldArea> areas;
  final Set<String> known;
  late final Rect bounds;
  static const resolution = 256;
  static int builds = 0;
  double distance(Offset p) => distanceToDiscovered(areas, known, p);
  Future<ui.Image> image() async {
    builds++;
    final bytes = await compute(
      _fogPixels,
      this,
      debugLabel: 'Fog distance mask',
    );
    return _image(bytes, resolution, resolution);
  }

  Uint8List pixels() {
    final bytes = Uint8List(resolution * resolution * 4);
    for (var y = 0; y < resolution; y++) {
      for (var x = 0; x < resolution; x++) {
        final d = distance(
          Offset(
            bounds.left + (x + .5) * bounds.width / resolution,
            bounds.top + (y + .5) * bounds.height / resolution,
          ),
        );
        final value = (d.clamp(0, 32) / 32 * 65025).round();
        final i = (y * resolution + x) * 4;
        bytes[i] = value ~/ 255;
        bytes[i + 1] = value % 255;
        bytes[i + 3] = 255;
      }
    }
    return bytes;
  }
}

Uint8List _fogPixels(FogField field) => field.pixels();

Future<ui.Image> _image(Uint8List bytes, int width, int height) {
  final c = Completer<ui.Image>();
  ui.decodeImageFromPixels(
    bytes,
    width,
    height,
    ui.PixelFormat.rgba8888,
    c.complete,
  );
  return c.future;
}

Future<ui.Image> _noise() {
  const size = 128, coarse = 16;
  final random = math.Random(73019);
  final samples = List.generate(
    2,
    (_) => List.generate(coarse * coarse, (_) => random.nextDouble()),
  );
  final bytes = Uint8List(size * size * 4);
  double smooth(double t) => t * t * (3 - 2 * t);
  for (var y = 0; y < size; y++) {
    for (var x = 0; x < size; x++) {
      final fx = x / size * coarse, fy = y / size * coarse;
      final ix = fx.floor(),
          iy = fy.floor(),
          tx = smooth(fx - ix),
          ty = smooth(fy - iy);
      for (var channel = 0; channel < 2; channel++) {
        double at(int x, int y) =>
            samples[channel][(y % coarse) * coarse + x % coarse];
        final a = at(ix, iy) * (1 - tx) + at(ix + 1, iy) * tx;
        final b = at(ix, iy + 1) * (1 - tx) + at(ix + 1, iy + 1) * tx;
        bytes[(y * size + x) * 4 + channel] = ((a * (1 - ty) + b * ty) * 255)
            .round();
      }
      bytes[(y * size + x) * 4 + 3] = 255;
    }
  }
  return _image(bytes, size, size);
}

class FogOverlay extends StatefulWidget {
  const FogOverlay({
    super.key,
    required this.model,
    required this.camera,
    required this.settings,
    required this.cameraChanges,
    this.animate = true,
    this.useShader = true,
  });
  final ProtoplaneController model;
  final Camera camera;
  final FogSettings settings;
  final Listenable cameraChanges;
  final bool animate, useShader;
  @override
  State<FogOverlay> createState() => _FogOverlayState();
}

class _FogOverlayState extends State<FogOverlay>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final paintChanges = _FogRepaint();
  late final Ticker ticker = createTicker(_tick);
  ui.FragmentShader? shader;
  ui.Image? noise, mask, previousMask;
  FogField? field, previousField;
  String? signature;
  int generation = 0;
  double seconds = 0, revealStart = -1;
  Duration? lastTick;
  bool reduced = false, foreground = true;
  static final Future<ui.FragmentProgram> program =
      ui.FragmentProgram.fromAsset('shaders/discovery_fog.frag');
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.cameraChanges.addListener(_repaint);
    widget.model.addListener(_worldChanged);
    if (widget.useShader) unawaited(_load());
    _sync();
  }

  Future<void> _load() async {
    ui.FragmentShader? loaded;
    ui.Image? grain;
    try {
      loaded = (await program).fragmentShader();
      grain = await _noise();
      if (!mounted) {
        loaded.dispose();
        grain.dispose();
        return;
      }
      shader = loaded;
      noise = grain;
      _repaint();
      _animate();
    } catch (error) {
      FogDiagnostics.shaderError = error;
      loaded?.dispose();
      grain?.dispose();
    }
  }

  void _repaint() => paintChanges.repaint();
  void _worldChanged() {
    _sync();
    _repaint();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reduced =
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    _animate();
  }

  @override
  void didUpdateWidget(FogOverlay old) {
    super.didUpdateWidget(old);
    if (old.cameraChanges != widget.cameraChanges) {
      old.cameraChanges.removeListener(_repaint);
      widget.cameraChanges.addListener(_repaint);
    }
    if (old.model != widget.model) {
      old.model.removeListener(_worldChanged);
      widget.model.addListener(_worldChanged);
    }
    _sync();
    _animate();
    _repaint();
  }

  void _sync() {
    final known = widget.model.revealedAreas.toList()..sort();
    final next =
        '${widget.model.preset}/${widget.model.areas.values.map((a) => '${a.id}:${a.footprints.map((r) => r.outer).join()}').join()}/$known';
    if (next == signature || widget.model.areas.isEmpty) return;
    signature = next;
    final nextField = FogField(
      widget.model.areas.values,
      widget.model.revealedAreas,
    );
    final expanding =
        field != null &&
        nextField.known.containsAll(field!.known) &&
        nextField.known.length > field!.known.length;
    previousField = expanding ? field : nextField;
    field = nextField;
    if (!expanding) {
      previousMask?.dispose();
      previousMask = null;
      mask?.dispose();
      mask = null;
    }
    revealStart = expanding ? seconds : -1;
    final token = ++generation;
    unawaited(
      nextField
          .image()
          .then((image) {
            if (!mounted || token != generation) {
              image.dispose();
              return;
            }
            previousMask?.dispose();
            previousMask = expanding ? mask : null;
            if (!expanding) mask?.dispose();
            mask = image;
            if (expanding) revealStart = seconds;
            _repaint();
            _animate();
          })
          .catchError((Object error) {
            FogDiagnostics.shaderError = error;
          }),
    );
    _animate();
  }

  double get reveal => revealStart < 0 || reduced || !widget.animate
      ? 1
      : ((seconds - revealStart) / .8).clamp(0, 1);
  void _tick(Duration elapsed) {
    final last = lastTick;
    lastTick = elapsed;
    if (last != null) seconds += (elapsed - last).inMicroseconds / 1e6;
    if (reveal >= 1 && previousMask != null) {
      previousMask!.dispose();
      previousMask = null;
      previousField = null;
    }
    _repaint();
    _animate();
  }

  void _animate() {
    final moving =
        mounted &&
        foreground &&
        !reduced &&
        widget.animate &&
        widget.settings.enabled &&
        widget.settings.style.opacity > 0 &&
        (widget.settings.style.speed > 0 && shader != null && mask != null ||
            reveal < 1);
    if (moving && !ticker.isActive) {
      lastTick = null;
      ticker.start();
    }
    if (!moving && ticker.isActive) {
      ticker.stop();
      lastTick = null;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    foreground = state == AppLifecycleState.resumed;
    _animate();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: RepaintBoundary(
      child: CustomPaint(painter: _FogPainter(this, repaint: paintChanges)),
    ),
  );
  @override
  void dispose() {
    generation++;
    WidgetsBinding.instance.removeObserver(this);
    widget.cameraChanges.removeListener(_repaint);
    widget.model.removeListener(_worldChanged);
    ticker.dispose();
    shader?.dispose();
    noise?.dispose();
    mask?.dispose();
    previousMask?.dispose();
    paintChanges.dispose();
    super.dispose();
  }
}

class _FogRepaint extends ChangeNotifier {
  void repaint() => notifyListeners();
}

class _FogPainter extends CustomPainter {
  _FogPainter(this.state, {super.repaint});
  final _FogOverlayState state;
  @override
  void paint(Canvas canvas, Size size) {
    final field = state.field,
        s = state.widget.settings.style,
        camera = state.widget.camera;
    if (!state.widget.settings.enabled ||
        field == null ||
        size.isEmpty ||
        s.opacity == 0) {
      return;
    }
    final active = state.widget.model.activePlane;
    Rect? focusRect;
    if (active != null) {
      final points = active.region.outer.map((p) => active.point(p)).toList();
      focusRect = Rect.fromLTRB(
        points.map((p) => p.x).reduce(math.min),
        points.map((p) => -p.z).reduce(math.min),
        points.map((p) => p.x).reduce(math.max),
        points.map((p) => -p.z).reduce(math.max),
      );
    }
    final shader = state.shader;
    if (shader != null && state.mask != null && state.noise != null) {
      FogDiagnostics.shaderPaints++;
      final forward = camera.forward,
          right = camera.right,
          up = right.cross(forward).normalized();
      final floats = <double>[
        size.width,
        size.height,
        ...camera.position.storage,
        ...forward.storage,
        ...right.storage,
        ...up.storage,
        math.tan(camera.fovDegrees * math.pi / 360),
        field.bounds.left,
        field.bounds.top,
        field.bounds.width,
        field.bounds.height,
        s.base.r,
        s.base.g,
        s.base.b,
        s.highlight.r,
        s.highlight.g,
        s.highlight.b,
        s.opacity,
        s.margin,
        s.softness,
        s.scale,
        s.contrast,
        s.speed,
        s.depth,
        state.seconds,
        state.reveal,
        focusRect?.left ?? 0,
        focusRect?.top ?? 0,
        focusRect?.right ?? 0,
        focusRect?.bottom ?? 0,
        focusRect == null ? 0 : 1,
      ];
      for (var i = 0; i < floats.length; i++) {
        shader.setFloat(i, floats[i]);
      }
      shader.setImageSampler(0, state.previousMask ?? state.mask!);
      shader.setImageSampler(1, state.mask!);
      shader.setImageSampler(2, state.noise!);
      canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
      return;
    }
    // Shader-independent fallback. Interpolated vertex alpha gives a feathered
    // veil without rendering a captured scene or revealing undiscovered land.
    FogDiagnostics.fallbackPaints++;
    const divisions = 48;
    final positions = <Offset>[], colors = <Color>[], indices = <int>[];
    for (var y = 0; y <= divisions; y++) {
      for (var x = 0; x <= divisions; x++) {
        final screen = Offset(
          size.width * x / divisions,
          size.height * y / divisions,
        );
        final ground = camera.intersectGround(screen, size);
        double fog(FogField f) {
          final d = ground == null
              ? 32.0
              : f.distance(Offset(ground.x, -ground.z));
          final t = ((d - s.margin) / s.softness).clamp(0.0, 1.0);
          return t * t * (3 - 2 * t);
        }

        var a = fog(field),
            b = state.previousField == null ? a : fog(state.previousField!);
        if (focusRect != null && ground != null) {
          final x = math.max(
            0.0,
            math.max(focusRect.left - ground.x, ground.x - focusRect.right),
          );
          final y = math.max(
            0.0,
            math.max(focusRect.top + ground.z, -ground.z - focusRect.bottom),
          );
          final t = (math.sqrt(x * x + y * y) / .3).clamp(0.0, 1.0);
          final f = t * t * (3 - 2 * t);
          a = math.min(a, f);
          b = math.min(b, f);
        }
        positions.add(screen);
        colors.add(
          Color.lerp(
            s.base,
            s.highlight,
            .5,
          )!.withValues(alpha: (b + (a - b) * state.reveal) * s.opacity),
        );
        if (x < divisions && y < divisions) {
          final i = y * (divisions + 1) + x;
          indices.addAll([
            i,
            i + 1,
            i + divisions + 1,
            i + 1,
            i + divisions + 2,
            i + divisions + 1,
          ]);
        }
      }
    }
    final vertices = ui.Vertices(
      ui.VertexMode.triangles,
      positions,
      colors: colors,
      indices: indices,
    );
    canvas.drawVertices(
      vertices,
      BlendMode.srcOver,
      Paint()..color = Colors.white,
    );
    vertices.dispose();
  }

  @override
  bool shouldRepaint(_FogPainter old) => true;
}
