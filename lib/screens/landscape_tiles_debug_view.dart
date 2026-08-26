import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../landscape/landscape_ca.dart';
import '../landscape/landscape_generator.dart';
import '../landscape/landscape_grid.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_plane_painter.dart';
import '../theme/world_theme.dart';
import '../landscape/landscape_raycast.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/fm_slider.dart';

enum LandscapeTool { orbit, erase }

/// Debug experiment: procedural landscape material tiles with orbit view.
class LandscapeTilesDebugView extends StatefulWidget {
  const LandscapeTilesDebugView({super.key});

  @override
  State<LandscapeTilesDebugView> createState() =>
      _LandscapeTilesDebugViewState();
}

class _LandscapeTilesDebugViewState extends State<LandscapeTilesDebugView> {
  late LandscapeGenParams _params;
  late Camera _camera;
  late OrbitCameraController _orbit;

  ui.Image? _atlas;
  LandscapeGrid? _grid;
  LandscapeGenerator? _generator;
  bool _baking = false;
  int _bakeGen = 0;
  Timer? _debounce;
  Timer? _eraseDebounce;
  Timer? _caTimer;
  String? _status;

  LandscapeTool _tool = LandscapeTool.orbit;
  bool _playing = false;
  int _caGeneration = 0;
  int _eraserSize = 1;

  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _mouseButtons = 0;
  int _lastTouchPointerCount = 0;

  LandscapeMaterial? _expandedMaterial;
  int? _hoverWx;
  int? _hoverWy;
  Size _viewportSize = Size.zero;
  bool _erasing = false;

  @override
  void initState() {
    super.initState();
    _params = const LandscapeGenParams().clamped();

    const d = 420.0;
    _camera = Camera(
      name: 'LandscapeDebugCamera',
      position: Vector3(0, d, d * 0.08),
      target: Vector3.zero(),
      projection: ProjectionType.perspective,
      fovDegrees: 50,
      near: 1,
      far: d * 8,
    );
    _orbit = OrbitCameraController(
      camera: _camera,
      target: Vector3.zero(),
      minDistance: 40,
      maxDistance: 4000,
    );

    _scheduleFullBake(immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _eraseDebounce?.cancel();
    _caTimer?.cancel();
    _atlas?.dispose();
    _orbit.dispose();
    super.dispose();
  }

  bool get _canErase => _tool == LandscapeTool.erase && !_playing;

  void _updateParams(LandscapeGenParams next) {
    _pauseCa();
    setState(() => _params = next.clamped());
    _scheduleFullBake();
  }

  static String _formatHsl(HSLColor c) {
    return 'HSL(${c.hue.toStringAsFixed(1)}, '
        '${c.saturation.toStringAsFixed(3)}, '
        '${c.lightness.toStringAsFixed(3)}, a=${c.alpha.toStringAsFixed(3)})';
  }

  Future<void> _dumpSettings() async {
    final p = _params;
    final buf = StringBuffer()
      ..writeln('=== Landscape tiles debug settings ===')
      ..writeln('seed: ${p.seed}')
      ..writeln('tilesSide: ${p.tilesSide}')
      ..writeln('pixelsPerTile: ${p.pixelsPerTile}')
      ..writeln('sharpness: ${p.sharpness}')
      ..writeln('colorSigma: ${p.colorSigma.toStringAsFixed(3)}')
      ..writeln('noiseFrequency: ${p.noiseFrequency.toStringAsFixed(3)}')
      ..writeln()
      ..writeln('weights:');
    for (final m in [
      ...kLandscapeTerrainFlow,
      ...kLandscapeForage,
    ]) {
      buf.writeln('  ${m.name}: ${p.weights[m]!.toStringAsFixed(1)}');
    }
    buf
      ..writeln()
      ..writeln('gradients:');
    for (final m in LandscapeMaterial.values) {
      final g = p.gradients[m]!;
      buf.writeln(
        '  ${m.name}: ${_formatHsl(g.start)} → ${_formatHsl(g.end)}',
      );
    }
    final text = buf.toString();
    debugPrint(text);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _status = 'Settings copied to clipboard');
  }

  void _scheduleFullBake({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      unawaited(_fullBake());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 80), () {
      unawaited(_fullBake());
    });
  }

  Future<void> _fullBake() async {
    final genId = ++_bakeGen;
    final params = _params.clamped();
    setState(() {
      _baking = true;
      _status = 'Baking ${params.atlasEdge}² atlas…';
      _caGeneration = 0;
    });

    try {
      final generator = LandscapeGenerator(params);
      final grid = LandscapeGrid.fromGenerator(generator);
      final image = await generator.bakeAtlasFromGrid(
        grid,
        theme: WorldTheme.paperDiorama,
      );
      if (!mounted || genId != _bakeGen) {
        image.dispose();
        return;
      }
      setState(() {
        _generator = generator;
        _grid = grid;
        _atlas?.dispose();
        _atlas = image;
        _baking = false;
        final mb = (params.atlasPixelCount * 4) / (1024 * 1024);
        _status = params.exceedsSoftWarn
            ? 'Atlas ${params.atlasEdge}² (~${mb.toStringAsFixed(1)} MB) — soft warn'
            : 'Atlas ${params.atlasEdge}² (~${mb.toStringAsFixed(1)} MB)';
      });
    } catch (e) {
      if (!mounted || genId != _bakeGen) return;
      setState(() {
        _baking = false;
        _status = 'Bake failed: $e';
      });
    }
  }

  Future<void> _rebakeFromGrid({required String label}) async {
    final grid = _grid;
    final generator = _generator;
    if (grid == null || generator == null) return;
    final genId = ++_bakeGen;
    try {
      final image = await generator.bakeAtlasFromGrid(
        grid,
        theme: WorldTheme.paperDiorama,
      );
      if (!mounted || genId != _bakeGen) {
        image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = image;
        _status = label;
      });
    } catch (e) {
      if (!mounted || genId != _bakeGen) return;
      setState(() => _status = 'Bake failed: $e');
    }
  }

  void _scheduleEraseRebake() {
    _eraseDebounce?.cancel();
    _eraseDebounce = Timer(const Duration(milliseconds: 40), () {
      final empty = _grid?.emptyCount ?? 0;
      unawaited(_rebakeFromGrid(label: 'Erased · $empty empty'));
    });
  }

  void _setTool(LandscapeTool tool) {
    if (_playing && tool == LandscapeTool.erase) return;
    setState(() {
      _tool = tool;
      if (tool != LandscapeTool.erase) {
        _hoverWx = null;
        _hoverWy = null;
      }
    });
  }

  void _playCa() {
    if (_playing || _grid == null || _generator == null) return;
    setState(() {
      _playing = true;
      _tool = LandscapeTool.orbit;
      _hoverWx = null;
      _hoverWy = null;
    });
    _caTimer?.cancel();
    _caTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      _runCaGeneration();
    });
  }

  void _pauseCa() {
    _caTimer?.cancel();
    _caTimer = null;
    if (_playing) {
      setState(() => _playing = false);
    }
  }

  void _runCaGeneration() {
    final grid = _grid;
    final generator = _generator;
    if (grid == null || generator == null) return;
    final filled = LandscapeCA(generator).step(grid);
    _caGeneration++;
    unawaited(
      _rebakeFromGrid(
        label: filled == 0
            ? 'CA gen $_caGeneration · idle (${grid.emptyCount} empty)'
            : 'CA gen $_caGeneration · filled $filled (${grid.emptyCount} empty)',
      ),
    );
  }

  LandscapePixelHit? _hitAt(Offset local) {
    return LandscapeRaycast.hitPixel(
      screen: local,
      viewport: _viewportSize,
      camera: _camera,
      worldSize: _params.worldPixelsSide.toDouble(),
      worldPixelsSide: _params.worldPixelsSide,
    );
  }

  void _updateHover(Offset local) {
    if (!_canErase) return;
    final hit = _hitAt(local);
    setState(() {
      _hoverWx = hit?.wx;
      _hoverWy = hit?.wy;
    });
  }

  void _eraseAt(Offset local) {
    if (!_canErase) return;
    final grid = _grid;
    if (grid == null) return;
    final hit = _hitAt(local);
    if (hit == null) return;
    if (grid.eraseBrush(hit.wx, hit.wy, _eraserSize)) {
      setState(() {
        _hoverWx = hit.wx;
        _hoverWy = hit.wy;
      });
      _scheduleEraseRebake();
    }
  }

  @override
  Widget build(BuildContext context) {
    final worldSize = _params.worldPixelsSide.toDouble();

    return FmScreen(
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Listener(
            onPointerHover: (event) {
              if (_canErase) _updateHover(event.localPosition);
            },
            onPointerDown: (event) {
              if (event.kind == PointerDeviceKind.mouse) {
                _mouseButtons = event.buttons;
              }
              if (_canErase &&
                  (event.buttons & kPrimaryButton) != 0 &&
                  event.kind == PointerDeviceKind.mouse) {
                _erasing = true;
                _eraseAt(event.localPosition);
              }
            },
            onPointerMove: (event) {
              if (event.kind == PointerDeviceKind.mouse) {
                _mouseButtons = event.buttons;
                if (_erasing && _canErase && (_mouseButtons & kPrimaryButton) != 0) {
                  _eraseAt(event.localPosition);
                  return;
                }
                if ((_mouseButtons & kSecondaryButton) != 0) {
                  _orbit.pan(event.delta);
                } else if ((_mouseButtons & kPrimaryButton) != 0 && !_erasing) {
                  _orbit.orbit(event.delta);
                } else if (_canErase) {
                  _updateHover(event.localPosition);
                }
              }
            },
            onPointerUp: (_) {
              _mouseButtons = 0;
              _erasing = false;
            },
            onPointerCancel: (_) {
              _mouseButtons = 0;
              _erasing = false;
            },
            onPointerSignal: (signal) {
              if (signal is PointerScrollEvent) {
                _orbit.zoomByScroll(signal.scrollDelta.dy);
              }
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: (details) {
                _lastTouchFocalPoint = details.focalPoint;
                _lastTouchScale = 1.0;
                _lastTouchPointerCount = details.pointerCount;
                if (_canErase && details.pointerCount == 1) {
                  _erasing = true;
                  _eraseAt(details.localFocalPoint);
                }
              },
              onScaleUpdate: (details) {
                if (details.pointerCount != _lastTouchPointerCount) {
                  _lastTouchFocalPoint = details.focalPoint;
                  _lastTouchScale = details.scale;
                  _lastTouchPointerCount = details.pointerCount;
                }
                final focalPoint = details.focalPoint;
                if (_canErase && details.pointerCount == 1 && _erasing) {
                  _eraseAt(details.localFocalPoint);
                  _lastTouchFocalPoint = focalPoint;
                  _lastTouchScale = details.scale;
                  return;
                }
                if (_lastTouchFocalPoint != null) {
                  final delta = focalPoint - _lastTouchFocalPoint!;
                  if (details.pointerCount == 1) {
                    _orbit.orbit(delta);
                  } else if (details.pointerCount >= 2) {
                    _orbit.pan(delta);
                    final scaleChange = details.scale / _lastTouchScale;
                    if (scaleChange > 0 && scaleChange != 1.0) {
                      _orbit.zoomByScale(scaleChange);
                    }
                  }
                }
                _lastTouchFocalPoint = focalPoint;
                _lastTouchScale = details.scale;
              },
              onScaleEnd: (_) {
                _lastTouchFocalPoint = null;
                _lastTouchScale = 1.0;
                _lastTouchPointerCount = 0;
                _erasing = false;
              },
              child: CustomPaint(
                painter: LandscapePlanePainter(
                  camera: _camera,
                  listenable: _orbit,
                  image: _atlas,
                  worldSize: worldSize,
                  tilesSide: _params.tilesSide,
                  pixelsPerTile: _params.pixelsPerTile,
                  hoverWx: _canErase ? _hoverWx : null,
                  hoverWy: _canErase ? _hoverWy : null,
                  hoverBrushSize: _eraserSize,
                  backgroundColor: WorldTheme.paperDiorama.background,
                ),
                isComplex: true,
                willChange: true,
                child: const SizedBox.expand(),
              ),
            ),
          );
        },
      ),
      overlays: [
        const FmDevBackButton(),
        _ToolStrip(
          tool: _tool,
          playing: _playing,
          eraserSize: _eraserSize,
          onOrbit: () => _setTool(LandscapeTool.orbit),
          onErase: () => _setTool(LandscapeTool.erase),
          onPlay: _playCa,
          onPause: _pauseCa,
          onEraserSizeChanged: (v) => setState(() => _eraserSize = v),
        ),
        _StatusChip(status: _status, baking: _baking, playing: _playing),
        _ControlsPanel(
          params: _params,
          expandedMaterial: _expandedMaterial,
          onExpandMaterial: (m) => setState(() {
            _expandedMaterial = _expandedMaterial == m ? null : m;
          }),
          onChanged: _updateParams,
          onDumpSettings: _dumpSettings,
        ),
      ],
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.tool,
    required this.playing,
    required this.eraserSize,
    required this.onOrbit,
    required this.onErase,
    required this.onPlay,
    required this.onPause,
    required this.onEraserSizeChanged,
  });

  final LandscapeTool tool;
  final bool playing;
  final int eraserSize;
  final VoidCallback onOrbit;
  final VoidCallback onErase;
  final VoidCallback onPlay;
  final VoidCallback onPause;
  final ValueChanged<int> onEraserSizeChanged;

  static const int maxEraserSize = 25;

  @override
  Widget build(BuildContext context) {
    return FmSafePositioned(
      top: 48,
      left: 12,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _ToolButton(
                    label: 'Orbit',
                    selected: tool == LandscapeTool.orbit,
                    onTap: onOrbit,
                  ),
                  const SizedBox(width: 6),
                  _ToolButton(
                    label: 'Erase',
                    selected: tool == LandscapeTool.erase,
                    enabled: !playing,
                    onTap: onErase,
                  ),
                  const SizedBox(width: 10),
                  Container(width: 1, height: 22, color: Colors.white24),
                  const SizedBox(width: 10),
                  _ToolButton(
                    label: 'Play',
                    selected: playing,
                    enabled: !playing,
                    onTap: onPlay,
                  ),
                  const SizedBox(width: 6),
                  _ToolButton(
                    label: 'Pause',
                    selected: !playing,
                    enabled: playing,
                    onTap: onPause,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Eraser $eraserSize×$eraserSize',
                style: TextStyle(
                  color: playing ? Colors.white30 : Colors.white60,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 4),
              FmSlider(
                value: eraserSize.toDouble().clamp(1, maxEraserSize.toDouble()),
                min: 1,
                max: maxEraserSize.toDouble(),
                width: 220,
                height: 28,
                enabled: !playing,
                onChanged: playing
                    ? null
                    : (v) => onEraserSizeChanged(v.round().clamp(1, maxEraserSize)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  const _ToolButton({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bg = !enabled
        ? Colors.white10
        : selected
            ? Colors.white24
            : Colors.transparent;
    final fg = !enabled
        ? Colors.white30
        : selected
            ? Colors.white
            : Colors.white70;
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: enabled ? Colors.white24 : Colors.white10),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.status,
    required this.baking,
    required this.playing,
  });

  final String? status;
  final bool baking;
  final bool playing;

  @override
  Widget build(BuildContext context) {
    return FmSafePositioned(
      top: 12,
      left: 88,
      right: 300,
      child: IgnorePointer(
        child: Text(
          status ?? '',
          style: TextStyle(
            color: baking
                ? Colors.amberAccent
                : playing
                    ? Colors.lightGreenAccent
                    : Colors.white70,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

class _ControlsPanel extends StatelessWidget {
  const _ControlsPanel({
    required this.params,
    required this.expandedMaterial,
    required this.onExpandMaterial,
    required this.onChanged,
    required this.onDumpSettings,
  });

  final LandscapeGenParams params;
  final LandscapeMaterial? expandedMaterial;
  final ValueChanged<LandscapeMaterial> onExpandMaterial;
  final ValueChanged<LandscapeGenParams> onChanged;
  final VoidCallback onDumpSettings;

  @override
  Widget build(BuildContext context) {
    return FmSafePositioned(
      top: 12,
      right: 12,
      bottom: 12,
      child: SizedBox(
        width: 280,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white24),
          ),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
            children: [
              const Text(
                'Landscape tiles',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _limitsHint(params),
                style: const TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: GestureDetector(
                  onTap: onDumpSettings,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Text(
                      'Copy settings',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _labeledSlider(
                label: 'Seed ${params.seed}',
                value: params.seed.toDouble(),
                min: 0,
                max: 1000,
                onChanged: (v) => onChanged(params.copyWith(seed: v.round())),
              ),
              _labeledSlider(
                label: 'Tiles ${params.tilesSide}×${params.tilesSide}',
                value: params.tilesSide.toDouble(),
                min: 1,
                max: LandscapeGenParams.maxTilesSide.toDouble(),
                onChanged: (v) =>
                    onChanged(params.copyWith(tilesSide: v.round())),
              ),
              _labeledSlider(
                label: 'Subtiles/tile ${params.subtilesPerTile}',
                value: params.subtilesPerTile.toDouble(),
                min: 1,
                max: LandscapeGenParams.maxPixelsPerTile.toDouble(),
                onChanged: (v) =>
                    onChanged(params.copyWith(pixelsPerTile: v.round())),
              ),
              _labeledSlider(
                label: 'Sharpness ×${params.sharpness}',
                value: params.sharpness.toDouble(),
                min: 1,
                max: LandscapeGenParams.maxSharpness.toDouble(),
                onChanged: (v) =>
                    onChanged(params.copyWith(sharpness: v.round())),
              ),
              _labeledSlider(
                label: 'Color σ ${params.colorSigma.toStringAsFixed(2)}',
                value: params.colorSigma,
                min: 0.05,
                max: 0.6,
                onChanged: (v) => onChanged(params.copyWith(colorSigma: v)),
              ),
              _labeledSlider(
                label: 'Noise freq ${params.noiseFrequency.toStringAsFixed(3)}',
                value: params.noiseFrequency,
                min: 0.01,
                max: 0.35,
                onChanged: (v) => onChanged(params.copyWith(noiseFrequency: v)),
              ),
              const SizedBox(height: 8),
              const Text(
                'Terrain flow  water → dirt → grass → rock',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'One noise field. Weights are coverage along that continuum.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),
              for (final m in kLandscapeTerrainFlow)
                _weightSlider(params, m, onChanged),
              const SizedBox(height: 8),
              const Text(
                'Forage patches',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 4),
              const Text(
                'A second noise field stamped over the ground.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),
              for (final m in kLandscapeForage)
                _weightSlider(params, m, onChanged),
              const SizedBox(height: 8),
              const Text(
                'Color gradients',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              for (final m in LandscapeMaterial.values)
                _GradientEditor(
                  material: m,
                  gradient: params.gradients[m]!,
                  expanded: expandedMaterial == m,
                  onToggle: () => onExpandMaterial(m),
                  onChanged: (g) {
                    final next = Map<LandscapeMaterial, MaterialGradient>.from(
                      params.gradients,
                    )..[m] = g;
                    onChanged(params.copyWith(gradients: next));
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  static String _limitsHint(LandscapeGenParams p) {
    final world = p.worldPixelsSide;
    return 'World $world×$world px. Int overflow is not the limiter '
        '(64-bit). Prefer world < ~10k for noise precision; atlas edge '
        'clamped to ${LandscapeGenParams.maxAtlasEdge}.';
  }

  Widget _weightSlider(
    LandscapeGenParams params,
    LandscapeMaterial material,
    ValueChanged<LandscapeGenParams> onChanged,
  ) {
    return _labeledSlider(
      label: '${material.label} ${params.weights[material]!.toStringAsFixed(0)}',
      value: params.weights[material]!,
      min: 0,
      max: 40,
      onChanged: (v) {
        final next = Map<LandscapeMaterial, double>.from(params.weights)
          ..[material] = v;
        onChanged(params.copyWith(weights: next));
      },
    );
  }

  Widget _labeledSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 4),
          FmSlider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            width: 248,
            height: 28,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _GradientEditor extends StatelessWidget {
  const _GradientEditor({
    required this.material,
    required this.gradient,
    required this.expanded,
    required this.onToggle,
    required this.onChanged,
  });

  final LandscapeMaterial material;
  final MaterialGradient gradient;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<MaterialGradient> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: onToggle,
            child: Row(
              children: [
                Icon(
                  expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Text(
                  material.label,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            height: 14,
            width: 248,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              gradient: LinearGradient(
                colors: [gradient.start.toColor(), gradient.end.toColor()],
              ),
              border: Border.all(color: Colors.white24),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 6),
            _hslSliders(
              prefix: 'Start',
              color: gradient.start,
              onChanged: (c) => onChanged(gradient.copyWith(start: c)),
            ),
            _hslSliders(
              prefix: 'End',
              color: gradient.end,
              onChanged: (c) => onChanged(gradient.copyWith(end: c)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hslSliders({
    required String prefix,
    required HSLColor color,
    required ValueChanged<HSLColor> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$prefix H ${color.hue.round()}  S ${(color.saturation * 100).round()}  L ${(color.lightness * 100).round()}',
          style: const TextStyle(color: Colors.white38, fontSize: 10),
        ),
        FmSlider(
          value: color.hue,
          min: 0,
          max: 360,
          width: 248,
          height: 24,
          onChanged: (v) => onChanged(color.withHue(v)),
        ),
        FmSlider(
          value: color.saturation,
          min: 0,
          max: 1,
          width: 248,
          height: 24,
          onChanged: (v) => onChanged(color.withSaturation(v)),
        ),
        FmSlider(
          value: color.lightness,
          min: 0,
          max: 1,
          width: 248,
          height: 24,
          onChanged: (v) => onChanged(color.withLightness(v)),
        ),
      ],
    );
  }
}
