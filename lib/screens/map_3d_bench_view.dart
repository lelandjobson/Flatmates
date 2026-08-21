import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../crafting/craft_step_meshes.dart';
import '../landscape/landscape_generator.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_plane_painter.dart';
import '../rendering/iso/iso_projection.dart';
import '../rendering/lights.dart';
import '../rendering/map/map_aabb.dart';
import '../rendering/map/map_octree.dart';
import '../rendering/map/map_placement.dart';
import '../rendering/map/map_scene_streamer.dart';
import '../rendering/mesh.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/map_look_camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene_view.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/fm_slider.dart';

enum _MapToolbarTab { tools, assets }

/// 3D map benchmark: perlin ground plane + assembly-style craft meshes.
///
/// World scale matches OBJ authorship: [IsoProjection.worldUnitsPerTile] (10)
/// model units = 1 tile. Camera is a locked down-looking perspective on a
/// diagonal; occupants stream in through a tile octree.
class Map3dBenchView extends StatefulWidget {
  const Map3dBenchView({super.key, this.craftName = 'house_foo'});

  final String craftName;

  @override
  State<Map3dBenchView> createState() => _Map3dBenchViewState();
}

class _Map3dBenchViewState extends State<Map3dBenchView>
    with TickerProviderStateMixin {
  static const _tilesSide = 16;

  late final Camera _camera;
  late final MapLookCameraController _look;
  late final Scene _scene;
  late final LandscapeGenParams _params;
  late final MapOctree _octree;
  late final MapSceneStreamer _streamer;

  ui.Image? _atlas;
  List<Mesh> _houseTemplate = const [];
  final Set<int> _occupiedTiles = {};
  int _placeSeq = 0;

  bool _baking = false;
  bool _loadingHouse = false;
  String? _status;
  String? _error;

  _MapToolbarTab _tab = _MapToolbarTab.tools;

  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1.0;
  int _mouseButtons = 0;
  int _lastTouchPointerCount = 0;
  bool _pinching = false;
  Size _viewportSize = Size.zero;
  int _cullRadius = 4;

  double get _tileWorld => IsoProjection.worldUnitsPerTile;
  double get _worldSize => _tilesSide * _tileWorld;
  double get _mapHalf => _worldSize * 0.5;

  @override
  void initState() {
    super.initState();
    _params = const LandscapeGenParams(tilesSide: _tilesSide).clamped();

    final half = _mapHalf;
    _camera = Camera(
      name: 'map-3d-bench-cam',
      position: Vector3(0, half, 0),
      target: Vector3.zero(),
      projection: ProjectionType.perspective,
      fovDegrees: 50,
      near: 1,
      far: _worldSize * 8,
    );
    _look = MapLookCameraController(
      camera: _camera,
      vsync: this,
      lookAt: Vector3.zero(),
      minDistance: 28,
      maxDistance: _worldSize * 1.2,
      zoomStepCount: 3,
      boundsMin: Vector3(-half, 0, -half),
      boundsMax: Vector3(half, 0, half),
    )..addListener(_onCameraChanged);

    _scene = Scene(globalIllumination: 0.25)
      ..camera = _camera
      ..addLight(
        DirectionalLight(
          color: Colors.white,
          intensity: 0.95,
          direction: Vector3(-0.6, -1, -0.4),
        ),
      )
      ..addLight(
        DirectionalLight(
          color: Colors.white70,
          intensity: 0.35,
          direction: Vector3(0.4, -0.5, 0.6),
        ),
      )
      ..addListener(_onSceneChanged);

    _octree = MapOctree(
      bounds: MapAabb(
        Vector3(-half, 0, -half),
        Vector3(half, 24, half),
      ),
      minLeafSize: _tileWorld,
    );
    _streamer = MapSceneStreamer(
      scene: _scene,
      octree: _octree,
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
      loadPadding: 0,
      unloadPadding: 0,
    );

    _bakeLandscape();
    _loadHouse();
    _refreshStatus();
  }

  @override
  void dispose() {
    _look
      ..removeListener(_onCameraChanged)
      ..dispose();
    _scene.removeListener(_onSceneChanged);
    _atlas?.dispose();
    super.dispose();
  }

  void _onCameraChanged() {
    _look.setViewportSize(_viewportSize);
    _scene.markNeedsPaint();
    _scheduleStream();
    if (mounted) {
      setState(_refreshStatus);
    }
  }

  void _onSceneChanged() {
    if (mounted) setState(_refreshStatus);
  }

  void _scheduleStream() {
    final (tx, ty) = _look.lookAtTile(
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
    );
    unawaited(
      _streamer.sync(lookTx: tx, lookTy: ty, drawRadius: _cullRadius),
    );
  }

  void _refreshStatus() {
    if (_error != null) return;
    if (_baking || _loadingHouse) return;
    final (tx, ty) = _look.lookAtTile(
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
    );
    _status = 'Tile ($tx, $ty) · ${_look.zoomLabel} · '
        'cull ±$_cullRadius · '
        'drawn ${_streamer.drawnCount}/${_streamer.placedCount}';
  }

  Future<void> _bakeLandscape() async {
    setState(() {
      _baking = true;
      _status = 'Baking landscape…';
    });
    try {
      final generator = LandscapeGenerator(_params);
      final image = await generator.bakeAtlas();
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = image;
        _baking = false;
        _refreshStatus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _baking = false;
        _error = 'Landscape bake failed: $e';
      });
    }
  }

  Future<void> _loadHouse() async {
    setState(() => _loadingHouse = true);
    try {
      final assembly = await CraftStepAssembly.load(widget.craftName);
      final meshes = [
        for (final step in assembly.steps) ...step.meshes,
      ];
      _sitOnGround(meshes);
      if (!mounted) return;
      setState(() {
        _houseTemplate = meshes;
        _streamer.template = meshes;
        _loadingHouse = false;
        _refreshStatus();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHouse = false;
        _error = 'Failed to load ${widget.craftName}: $e';
      });
    }
  }

  /// After [CraftStepAssembly.centerAssembly], shift so the lowest vertex
  /// sits on the ground plane (Y = 0). XZ stays centered on the origin.
  static void _sitOnGround(List<Mesh> meshes) {
    var minY = double.infinity;
    for (final mesh in meshes) {
      for (final v in mesh.geometry.vertices) {
        minY = math.min(minY, v.y);
      }
    }
    if (!minY.isFinite) return;
    for (final mesh in meshes) {
      for (final v in mesh.geometry.vertices) {
        v.y -= minY;
      }
    }
  }

  Vector3 _tileCenter(int tx, int ty) {
    return Vector3(
      -_mapHalf + (tx + 0.5) * _tileWorld,
      0,
      -_mapHalf + (ty + 0.5) * _tileWorld,
    );
  }

  void _placeHouseOnRandomTile() {
    if (_houseTemplate.isEmpty) {
      setState(() => _status = 'House mesh still loading…');
      return;
    }
    final free = <int>[
      for (var i = 0; i < _tilesSide * _tilesSide; i++)
        if (!_occupiedTiles.contains(i)) i,
    ];
    if (free.isEmpty) {
      setState(() => _status = 'No free tiles left');
      return;
    }
    final key = free[math.Random().nextInt(free.length)];
    final tx = key % _tilesSide;
    final ty = key ~/ _tilesSide;
    final id = ++_placeSeq;
    _streamer.place(
      MapPlacement(
        id: id,
        tx: tx,
        ty: ty,
        craftName: widget.craftName,
        origin: _tileCenter(tx, ty),
      ),
    );
    _occupiedTiles.add(key);
    _scheduleStream();
    setState(_refreshStatus);
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: const Color(0xFF101418),
      overlays: [
        const FmDevBackButton(),
        _ToolStrip(
          tab: _tab,
          onTab: (tab) => setState(() => _tab = tab),
          onPlaceHouse: _placeHouseOnRandomTile,
          houseEnabled: !_loadingHouse && _houseTemplate.isNotEmpty,
          cullRadius: _cullRadius,
          maxCullRadius: _tilesSide,
          onCullRadiusChanged: (v) {
            setState(() => _cullRadius = v);
            _scheduleStream();
          },
        ),
        _StatusChip(
          status: _error ?? _status,
          busy: _baking || _loadingHouse,
          isError: _error != null,
        ),
        const _FpsChip(),
      ],
      background: _buildViewport(),
    );
  }

  Widget _buildViewport() {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _look.setViewportSize(_viewportSize);
        return Listener(
          onPointerDown: (event) {
            if (event.kind == PointerDeviceKind.mouse) {
              _mouseButtons = event.buttons;
            }
          },
          onPointerMove: (event) {
            if (event.kind == PointerDeviceKind.mouse) {
              _mouseButtons = event.buttons;
              if ((_mouseButtons & kPrimaryButton) != 0 ||
                  (_mouseButtons & kSecondaryButton) != 0) {
                _look.pan(event.delta);
              }
            }
          },
          onPointerUp: (_) => _mouseButtons = 0,
          onPointerCancel: (_) => _mouseButtons = 0,
          onPointerSignal: (signal) {
            if (signal is PointerScrollEvent) {
              _look.zoomByScroll(signal.scrollDelta.dy);
            }
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (details) {
              _lastTouchFocalPoint = details.focalPoint;
              _lastTouchScale = 1.0;
              _lastTouchPointerCount = details.pointerCount;
              if (details.pointerCount >= 2) {
                _look.beginZoom();
                _pinching = true;
              }
            },
            onScaleUpdate: (details) {
              if (details.pointerCount != _lastTouchPointerCount) {
                _lastTouchFocalPoint = details.focalPoint;
                _lastTouchScale = details.scale;
                _lastTouchPointerCount = details.pointerCount;
                if (details.pointerCount >= 2 && !_pinching) {
                  _look.beginZoom();
                  _pinching = true;
                }
              }
              final focalPoint = details.focalPoint;
              if (_lastTouchFocalPoint != null) {
                final delta = focalPoint - _lastTouchFocalPoint!;
                _look.pan(delta);
                if (details.pointerCount >= 2) {
                  final scaleChange = details.scale / _lastTouchScale;
                  if (scaleChange > 0 && scaleChange != 1.0) {
                    _look.zoomByScale(scaleChange);
                  }
                }
              }
              _lastTouchFocalPoint = focalPoint;
              _lastTouchScale = details.scale;
            },
            onScaleEnd: (_) {
              if (_pinching) {
                _look.endZoom();
                _pinching = false;
              }
              _lastTouchFocalPoint = null;
              _lastTouchScale = 1.0;
              _lastTouchPointerCount = 0;
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: LandscapePlanePainter(
                    camera: _camera,
                    listenable: _look,
                    image: _atlas,
                    worldSize: _worldSize,
                    tilesSide: _tilesSide,
                    pixelsPerTile: _tileWorld.round(),
                  ),
                  isComplex: true,
                  willChange: true,
                  child: const SizedBox.expand(),
                ),
                SizedBox.expand(child: SceneView(scene: _scene)),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ToolStrip extends StatelessWidget {
  const _ToolStrip({
    required this.tab,
    required this.onTab,
    required this.onPlaceHouse,
    required this.houseEnabled,
    required this.cullRadius,
    required this.maxCullRadius,
    required this.onCullRadiusChanged,
  });

  final _MapToolbarTab tab;
  final ValueChanged<_MapToolbarTab> onTab;
  final VoidCallback onPlaceHouse;
  final bool houseEnabled;
  final int cullRadius;
  final int maxCullRadius;
  final ValueChanged<int> onCullRadiusChanged;

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
                    label: 'Tools',
                    selected: tab == _MapToolbarTab.tools,
                    onTap: () => onTab(_MapToolbarTab.tools),
                  ),
                  const SizedBox(width: 6),
                  _ToolButton(
                    label: 'Assets',
                    selected: tab == _MapToolbarTab.assets,
                    onTap: () => onTab(_MapToolbarTab.assets),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (tab == _MapToolbarTab.tools) ...[
                const _ToolButton(
                  label: 'Pan',
                  selected: true,
                  onTap: _noop,
                ),
                const SizedBox(height: 8),
                Text(
                  'Cull ±$cullRadius tiles',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 4),
                FmSlider(
                  value: cullRadius.toDouble().clamp(0, maxCullRadius.toDouble()),
                  min: 0,
                  max: maxCullRadius.toDouble(),
                  width: 220,
                  height: 28,
                  onChanged: (v) =>
                      onCullRadiusChanged(v.round().clamp(0, maxCullRadius)),
                ),
              ] else
                _ToolButton(
                  label: 'House',
                  selected: false,
                  enabled: houseEnabled,
                  onTap: onPlaceHouse,
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _noop() {}
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
    required this.busy,
    required this.isError,
  });

  final String? status;
  final bool busy;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    return FmSafePositioned(
      top: 12,
      left: 88,
      right: 96,
      child: IgnorePointer(
        child: Text(
          status ?? '',
          style: TextStyle(
            color: isError
                ? Colors.redAccent
                : busy
                    ? Colors.amberAccent
                    : Colors.white70,
            fontSize: 12,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

/// Live frame-rate from [FrameTiming]s, independent of map setState.
class _FpsChip extends StatefulWidget {
  const _FpsChip();

  @override
  State<_FpsChip> createState() => _FpsChipState();
}

class _FpsChipState extends State<_FpsChip> {
  double _fps = 0;
  int _samples = 0;
  double _accumMs = 0;
  DateTime _lastUi = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    super.dispose();
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      final ms = t.totalSpan.inMicroseconds / 1000.0;
      if (ms <= 0) continue;
      _accumMs += ms;
      _samples++;
    }
    if (_samples < 4) return;
    final now = DateTime.now();
    if (now.difference(_lastUi) < const Duration(milliseconds: 250)) return;
    final fps = 1000.0 * _samples / _accumMs;
    _samples = 0;
    _accumMs = 0;
    _lastUi = now;
    if (!mounted) return;
    setState(() => _fps = fps);
  }

  @override
  Widget build(BuildContext context) {
    final fps = _fps;
    final color = fps >= 55
        ? Colors.lightGreenAccent
        : fps >= 30
            ? Colors.amberAccent
            : Colors.redAccent;
    return FmSafePositioned(
      top: 12,
      right: 12,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white24),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Text(
              fps <= 0 ? '— fps' : '${fps.toStringAsFixed(0)} fps',
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontFeatures: const [ui.FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
