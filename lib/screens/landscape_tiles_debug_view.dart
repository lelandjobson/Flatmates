import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../landscape/landscape_generator.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_plane_painter.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/camera_controller.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/fm_slider.dart';

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
  bool _baking = false;
  int _bakeGen = 0;
  Timer? _debounce;
  String? _status;

  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _mouseButtons = 0;
  int _lastTouchPointerCount = 0;

  LandscapeMaterial? _expandedMaterial;

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

    _scheduleBake(immediate: true);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _atlas?.dispose();
    _orbit.dispose();
    super.dispose();
  }

  void _updateParams(LandscapeGenParams next) {
    setState(() => _params = next.clamped());
    _scheduleBake();
  }

  void _scheduleBake({bool immediate = false}) {
    _debounce?.cancel();
    if (immediate) {
      unawaited(_bake());
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 80), () {
      unawaited(_bake());
    });
  }

  Future<void> _bake() async {
    final genId = ++_bakeGen;
    final params = _params.clamped();
    setState(() {
      _baking = true;
      _status = 'Baking ${params.atlasEdge}² atlas…';
    });

    try {
      final image = await LandscapeGenerator(params).bakeAtlas();
      if (!mounted || genId != _bakeGen) {
        image.dispose();
        return;
      }
      setState(() {
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

  @override
  Widget build(BuildContext context) {
    final worldSize = _params.worldPixelsSide.toDouble();

    return FmScreen(
      background: Listener(
        onPointerDown: (event) {
          if (event.kind == PointerDeviceKind.mouse) {
            _mouseButtons = event.buttons;
          }
        },
        onPointerMove: (event) {
          if (event.kind == PointerDeviceKind.mouse) {
            _mouseButtons = event.buttons;
            if ((_mouseButtons & kSecondaryButton) != 0) {
              _orbit.pan(event.delta);
            } else if ((_mouseButtons & kPrimaryButton) != 0) {
              _orbit.orbit(event.delta);
            }
          }
        },
        onPointerUp: (_) => _mouseButtons = 0,
        onPointerCancel: (_) => _mouseButtons = 0,
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
          },
          onScaleUpdate: (details) {
            if (details.pointerCount != _lastTouchPointerCount) {
              _lastTouchFocalPoint = details.focalPoint;
              _lastTouchScale = details.scale;
              _lastTouchPointerCount = details.pointerCount;
            }
            final focalPoint = details.focalPoint;
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
          },
          child: CustomPaint(
            painter: LandscapePlanePainter(
              camera: _camera,
              orbit: _orbit,
              image: _atlas,
              worldSize: worldSize,
              tilesSide: _params.tilesSide,
              pixelsPerTile: _params.pixelsPerTile,
            ),
            isComplex: true,
            willChange: true,
            child: const SizedBox.expand(),
          ),
        ),
      ),
      overlays: [
        const FmDevBackButton(),
        _StatusChip(status: _status, baking: _baking),
        _ControlsPanel(
          params: _params,
          expandedMaterial: _expandedMaterial,
          onExpandMaterial: (m) => setState(() {
            _expandedMaterial = _expandedMaterial == m ? null : m;
          }),
          onChanged: _updateParams,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status, required this.baking});

  final String? status;
  final bool baking;

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
            color: baking ? Colors.amberAccent : Colors.white70,
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
  });

  final LandscapeGenParams params;
  final LandscapeMaterial? expandedMaterial;
  final ValueChanged<LandscapeMaterial> onExpandMaterial;
  final ValueChanged<LandscapeGenParams> onChanged;

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
                label: 'Pixels/tile ${params.pixelsPerTile}',
                value: params.pixelsPerTile.toDouble(),
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
                'Spawn weights',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 6),
              for (final m in LandscapeMaterial.values) ...[
                _labeledSlider(
                  label: '${m.label} ${params.weights[m]!.toStringAsFixed(0)}',
                  value: params.weights[m]!,
                  min: 0,
                  max: 40,
                  onChanged: (v) {
                    final next = Map<LandscapeMaterial, double>.from(
                      params.weights,
                    )..[m] = v;
                    onChanged(params.copyWith(weights: next));
                  },
                ),
              ],
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
