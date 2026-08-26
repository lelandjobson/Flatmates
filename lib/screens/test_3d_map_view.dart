import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../crafting/craft_step_meshes.dart';
import '../crafting/placed_paper.dart';
import '../gameplay/paint/face_paint_store.dart';
import '../gameplay/paint/ground_shadow_model.dart';
import '../gameplay/paint/plane_grain_model.dart';
import '../gameplay/paint/plane_shade_model.dart';
import '../gameplay/viewers/world_plane.dart';
import '../gameplay/volumes/volume.dart';
import '../gameplay/volumes/volume_box_mesh.dart';
import '../gameplay/volumes/volume_store.dart';
import '../landscape/landscape_generator.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_palette.dart';
import '../landscape/landscape_plane_painter.dart';
import '../theme/world_theme.dart';
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
import '../ui/game/frame_stats_hud.dart';
import '../ui/game/game_tool_sidebar.dart';
import '../ui/game/volume_face_paint_overlay.dart';
import '../ui/game/volume_ground_shadow_overlay.dart';

enum _MapToolbarTab { tools, colors, shade, grain, assets }

/// Test 3D map: perlin ground plane + assembly-style craft meshes.
///
/// World scale matches OBJ authorship: [IsoProjection.worldUnitsPerTile] (10)
/// model units = 1 tile. Camera is a locked down-looking perspective on a
/// diagonal; occupants stream in through a tile octree.
class Test3dMapView extends StatefulWidget {
  const Test3dMapView({super.key, this.craftName = 'house_foo'});

  final String craftName;

  @override
  State<Test3dMapView> createState() => _Test3dMapViewState();
}

class _Test3dMapViewState extends State<Test3dMapView>
    with TickerProviderStateMixin {
  static const _tilesSide = 16;

  late final Camera _camera;
  late final MapLookCameraController _look;
  late final Scene _scene;
  late LandscapeGenParams _params;
  late final MapOctree _octree;
  late final MapSceneStreamer _streamer;
  LandscapePalette _palette = LandscapePalette.paperDiorama;
  WorldTheme _theme = WorldTheme.paperDiorama;
  double _colorOpacity = LandscapePalette.paperDiorama.defaultOpacity;
  LandscapeMaterial? _expandedMaterial;
  Timer? _paletteDebounce;
  int _bakeGen = 0;

  late final VolumeStore _volumes;
  final FacePaintStore _facePaint = FacePaintStore();
  PlaneShadeModel _shade = WorldTheme.kPaperShade;
  PlaneGrainModel _grain = WorldTheme.paperDiorama.grain;
  GroundShadowModel _shadow = const GroundShadowModel();

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
    _params = LandscapeGenParams(
      tilesSide: _tilesSide,
      colorSigma: WorldTheme.paperDiorama.colorSigma,
      gradients: LandscapePalette.paperDiorama.gradientsAt(
        LandscapePalette.paperDiorama.defaultOpacity,
      ),
    ).clamped();

    final half = _mapHalf;
    _camera = Camera(
      name: 'test-3d-map-cam',
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
      ladderZoom: false,
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

    _volumes = VolumeStore(
      grid: VolumeGrid(
        tilesSide: _tilesSide,
        tileSize: _tileWorld,
        subtilesPerTile: VolumeGrid.defaultSubtilesPerTile,
      ),
    );

    _octree = MapOctree(
      bounds: MapAabb(Vector3(-half, 0, -half), Vector3(half, 24, half)),
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

    _seedPaintedBoxes();
    _bakeLandscape();
    _loadHouse();
    _refreshStatus();
  }

  void _seedPaintedBoxes() {
    const placements = <(int, int, PaperColor)>[
      (7, 7, PaperColor.pink),
      (8, 7, PaperColor.yellow),
      (7, 8, PaperColor.green),
    ];
    final volumes = <Volume>[];
    var id = 1;
    for (final (tx, ty, color) in placements) {
      final cell = VolumeCell(tx: tx, ty: ty, box: BoxPrimitive());
      final volume = Volume(id: id++, cells: [cell]);
      volumes.add(volume);
      _occupiedTiles.add(ty * _tilesSide + tx);
      for (final face in VolumeFace.values) {
        final canvas = _facePaint.canvasFor(
          volumeId: volume.id,
          cell: cell,
          face: face,
        );
        for (var y = 0; y < canvas.height; y++) {
          for (var x = 0; x < canvas.width; x++) {
            canvas.paint(x, y, color);
          }
        }
      }
    }
    _volumes.restore(
      volumes: volumes,
      draftIsGrow: false,
      phase: VolumeEditPhase.idle,
      nextId: id,
    );
    syncVolumeMeshes(
      _scene,
      _volumes,
      committed: _theme.volume,
      draftColor: _theme.volumeDraft,
    );
  }

  @override
  void dispose() {
    _paletteDebounce?.cancel();
    _look
      ..removeListener(_onCameraChanged)
      ..dispose();
    _scene.removeListener(_onSceneChanged);
    _atlas?.dispose();
    super.dispose();
  }

  void _applyPalette(LandscapePalette palette, {required double opacity}) {
    _palette = palette;
    _theme = WorldTheme.byId(palette.id);
    _colorOpacity = opacity.clamp(0.15, 1.0);
    _shade = _theme.shade;
    _grain = _theme.grain;
    _shadow = _shadow.copyWith(
      lightX: _theme.shade.lightX,
      lightY: _theme.shade.lightY,
      lightZ: _theme.shade.lightZ,
    );
    _params = _params.copyWith(
      colorSigma: _theme.colorSigma,
      gradients: palette.gradientsAt(_colorOpacity),
    );
  }

  void _onPaletteChanged(LandscapePalette palette) {
    _paletteDebounce?.cancel();
    setState(() => _applyPalette(palette, opacity: palette.defaultOpacity));
    unawaited(_bakeLandscape());
  }

  void _onOpacityChanged(double opacity) {
    setState(() {
      _colorOpacity = opacity.clamp(0.15, 1.0);
      _params = _params.copyWith(
        gradients: {
          for (final e in _params.gradients.entries)
            e.key: e.value.withOpacity(_colorOpacity),
        },
      );
    });
    _scheduleLandscapeBake();
  }

  void _onParamsChanged(LandscapeGenParams next) {
    setState(() => _params = next);
    _scheduleLandscapeBake();
  }

  void _scheduleLandscapeBake() {
    _paletteDebounce?.cancel();
    _paletteDebounce = Timer(const Duration(milliseconds: 80), () {
      unawaited(_bakeLandscape());
    });
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
    unawaited(_streamer.sync(lookTx: tx, lookTy: ty, drawRadius: _cullRadius));
  }

  void _refreshStatus() {
    if (_error != null) return;
    if (_baking || _loadingHouse) return;
    final (tx, ty) = _look.lookAtTile(
      tileSize: _tileWorld,
      tilesSide: _tilesSide,
    );
    _status =
        'Tile ($tx, $ty) · ${_look.zoomLabel} · '
        'cull ±$_cullRadius · '
        'drawn ${_streamer.drawnCount}/${_streamer.placedCount}';
  }

  Future<void> _bakeLandscape() async {
    final genId = ++_bakeGen;
    final first = _atlas == null;
    if (first) {
      setState(() {
        _baking = true;
        _status = 'Baking landscape…';
      });
    }
    try {
      final generator = LandscapeGenerator(_params);
      final image = await generator.bakeAtlas(theme: _theme);
      if (!mounted || genId != _bakeGen) {
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
      if (!mounted || genId != _bakeGen) return;
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
      final meshes = [for (final step in assembly.steps) ...step.meshes];
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

  String _formatHsl(HSLColor c) {
    return 'HSL(${c.hue.toStringAsFixed(1)}, '
        '${c.saturation.toStringAsFixed(3)}, '
        '${c.lightness.toStringAsFixed(3)}, a=${c.alpha.toStringAsFixed(3)})';
  }

  String _formatColor(Color c) {
    return '#${c.toARGB32().toRadixString(16).padLeft(8, '0')}';
  }

  Future<void> _dumpSettings() async {
    final buf = StringBuffer()
      ..writeln('=== Test3dMapView settings ===')
      ..writeln('theme: ${_theme.id} (${_theme.label})')
      ..writeln('palette: ${_palette.id} (${_palette.label})')
      ..writeln('opacity: ${_colorOpacity.toStringAsFixed(3)}')
      ..writeln('colorSigma: ${_params.colorSigma.toStringAsFixed(3)}')
      ..writeln('noiseFrequency: ${_params.noiseFrequency.toStringAsFixed(3)}')
      ..writeln('seed: ${_params.seed}')
      ..writeln()
      ..writeln('weights:');
    for (final m in [...kLandscapeTerrainFlow, ...kLandscapeForage]) {
      buf.writeln('  ${m.name}: ${_params.weights[m]!.toStringAsFixed(1)}');
    }
    buf
      ..writeln()
      ..writeln('gradients:');
    for (final m in LandscapeMaterial.values) {
      final g = _params.gradients[m]!;
      buf.writeln('  ${m.name}: ${_formatHsl(g.start)} → ${_formatHsl(g.end)}');
    }
    buf
      ..writeln()
      ..writeln('shade:')
      ..writeln(
        '  light: ${_shade.lightX.toStringAsFixed(3)}, '
        '${_shade.lightY.toStringAsFixed(3)}, '
        '${_shade.lightZ.toStringAsFixed(3)}',
      )
      ..writeln(
        '  minShade: ${_shade.minShade.toStringAsFixed(3)}  '
        'maxShade: ${_shade.maxShade.toStringAsFixed(3)}',
      )
      ..writeln('  tintStrength: ${_shade.tintStrength.toStringAsFixed(3)}')
      ..writeln(
        '  litTint: ${_formatColor(_shade.litTint)}  '
        'shadeTint: ${_formatColor(_shade.shadeTint)}',
      )
      ..writeln()
      ..writeln('grain:')
      ..writeln('  seed: ${_grain.seed}')
      ..writeln('  strength: ${_grain.strength.toStringAsFixed(3)}')
      ..writeln('  frequency: ${_grain.frequency.toStringAsFixed(3)}')
      ..writeln('  octaves: ${_grain.octaves}')
      ..writeln('  bias: ${_grain.bias.toStringAsFixed(3)}')
      ..writeln()
      ..writeln('groundShadow:')
      ..writeln('  mode: ${_shadow.mode.name}')
      ..writeln('  opacity: ${_shadow.opacity.toStringAsFixed(3)}')
      ..writeln('  blurSigma: ${_shadow.blurSigma.toStringAsFixed(2)}')
      ..writeln('  maxStretch: ${_shadow.maxStretch.toStringAsFixed(2)}')
      ..writeln(
        '  light: ${_shadow.lightX.toStringAsFixed(3)}, '
        '${_shadow.lightY.toStringAsFixed(3)}, '
        '${_shadow.lightZ.toStringAsFixed(3)}',
      );

    final text = buf.toString();
    debugPrint(text);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    setState(() => _status = 'Settings copied to clipboard');
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: _theme.background,
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
          palette: _palette,
          colorOpacity: _colorOpacity,
          onPaletteChanged: _onPaletteChanged,
          onOpacityChanged: _onOpacityChanged,
          shade: _shade,
          onShadeChanged: (shade) => setState(() {
            _shade = shade;
            _shadow = _shadow.copyWith(
              lightX: shade.lightX,
              lightY: shade.lightY,
              lightZ: shade.lightZ,
            );
          }),
          grain: _grain,
          onGrainChanged: (grain) => setState(() => _grain = grain),
          shadow: _shadow,
          onShadowChanged: (shadow) => setState(() => _shadow = shadow),
          params: _params,
          expandedMaterial: _expandedMaterial,
          onExpandMaterial: (m) => setState(() {
            _expandedMaterial = _expandedMaterial == m ? null : m;
          }),
          onParamsChanged: _onParamsChanged,
          onDumpSettings: _dumpSettings,
        ),
        _StatusChip(
          status: _error ?? _status,
          busy: _baking || _loadingHouse,
          isError: _error != null,
        ),
        const FrameStatsHud(),
        FmSafePositioned(
          bottom: 12,
          left: 12,
          child: GameViewRotateButton(
            clockwise: false,
            onPressed: _look.rotateCounterClockwise,
          ),
        ),
        FmSafePositioned(
          bottom: 12,
          right: 12,
          child: GameViewRotateButton(
            clockwise: true,
            onPressed: _look.rotateClockwise,
          ),
        ),
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
                    backgroundColor: _theme.background,
                  ),
                  isComplex: true,
                  willChange: true,
                  child: const SizedBox.expand(),
                ),
                Positioned.fill(
                  child: VolumeGroundShadowOverlay(
                    volumes: _volumes,
                    camera: _camera,
                    viewport: _viewportSize,
                    model: _shadow,
                    listenable: _look,
                  ),
                ),
                SizedBox.expand(child: SceneView(scene: _scene)),
                Positioned.fill(
                  child: VolumeFacePaintOverlay(
                    store: _facePaint,
                    volumes: _volumes,
                    camera: _camera,
                    viewport: _viewportSize,
                    listenable: _look,
                    shade: _shade,
                    grain: _grain,
                    theme: _theme,
                  ),
                ),
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
    required this.palette,
    required this.colorOpacity,
    required this.onPaletteChanged,
    required this.onOpacityChanged,
    required this.shade,
    required this.onShadeChanged,
    required this.grain,
    required this.onGrainChanged,
    required this.shadow,
    required this.onShadowChanged,
    required this.params,
    required this.expandedMaterial,
    required this.onExpandMaterial,
    required this.onParamsChanged,
    required this.onDumpSettings,
  });

  final _MapToolbarTab tab;
  final ValueChanged<_MapToolbarTab> onTab;
  final VoidCallback onPlaceHouse;
  final bool houseEnabled;
  final int cullRadius;
  final int maxCullRadius;
  final ValueChanged<int> onCullRadiusChanged;
  final LandscapePalette palette;
  final double colorOpacity;
  final ValueChanged<LandscapePalette> onPaletteChanged;
  final ValueChanged<double> onOpacityChanged;
  final PlaneShadeModel shade;
  final ValueChanged<PlaneShadeModel> onShadeChanged;
  final PlaneGrainModel grain;
  final ValueChanged<PlaneGrainModel> onGrainChanged;
  final GroundShadowModel shadow;
  final ValueChanged<GroundShadowModel> onShadowChanged;
  final LandscapeGenParams params;
  final LandscapeMaterial? expandedMaterial;
  final ValueChanged<LandscapeMaterial> onExpandMaterial;
  final ValueChanged<LandscapeGenParams> onParamsChanged;
  final VoidCallback onDumpSettings;

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
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _ToolButton(
                    label: 'Tools',
                    selected: tab == _MapToolbarTab.tools,
                    onTap: () => onTab(_MapToolbarTab.tools),
                  ),
                  _ToolButton(
                    label: 'Colors',
                    selected: tab == _MapToolbarTab.colors,
                    onTap: () => onTab(_MapToolbarTab.colors),
                  ),
                  _ToolButton(
                    label: 'Shade',
                    selected: tab == _MapToolbarTab.shade,
                    onTap: () => onTab(_MapToolbarTab.shade),
                  ),
                  _ToolButton(
                    label: 'Grain',
                    selected: tab == _MapToolbarTab.grain,
                    onTap: () => onTab(_MapToolbarTab.grain),
                  ),
                  _ToolButton(
                    label: 'Assets',
                    selected: tab == _MapToolbarTab.assets,
                    onTap: () => onTab(_MapToolbarTab.assets),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (tab == _MapToolbarTab.tools) ...[
                const _ToolButton(label: 'Pan', selected: true, onTap: _noop),
                const SizedBox(height: 8),
                Text(
                  'Cull ±$cullRadius tiles',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 4),
                FmSlider(
                  value: cullRadius.toDouble().clamp(
                    0,
                    maxCullRadius.toDouble(),
                  ),
                  min: 0,
                  max: maxCullRadius.toDouble(),
                  width: 220,
                  height: 28,
                  onChanged: (v) =>
                      onCullRadiusChanged(v.round().clamp(0, maxCullRadius)),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Map palette',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 4),
                _PaletteDropdown(palette: palette, onChanged: onPaletteChanged),
                const SizedBox(height: 6),
                _PaletteSwatches(palette: palette, opacity: colorOpacity),
                const SizedBox(height: 8),
                Text(
                  'Opacity ${(colorOpacity * 100).round()}%',
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                const SizedBox(height: 4),
                FmSlider(
                  value: colorOpacity.clamp(0.15, 1.0),
                  min: 0.15,
                  max: 1.0,
                  width: 220,
                  height: 28,
                  onChanged: onOpacityChanged,
                ),
                const SizedBox(height: 10),
                _ToolButton(
                  label: 'Copy settings',
                  selected: false,
                  onTap: onDumpSettings,
                ),
              ] else if (tab == _MapToolbarTab.colors)
                _MaterialColorControls(
                  params: params,
                  expandedMaterial: expandedMaterial,
                  onExpandMaterial: onExpandMaterial,
                  onChanged: onParamsChanged,
                )
              else if (tab == _MapToolbarTab.shade)
                _ShadeControls(
                  shade: shade,
                  onChanged: onShadeChanged,
                  shadow: shadow,
                  onShadowChanged: onShadowChanged,
                )
              else if (tab == _MapToolbarTab.grain)
                _GrainControls(grain: grain, onChanged: onGrainChanged)
              else
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

class _MaterialColorControls extends StatelessWidget {
  const _MaterialColorControls({
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
    final maxH = MediaQuery.sizeOf(context).height - 140;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH.clamp(180, 560)),
      child: SingleChildScrollView(
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Terrain flow',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 2),
              const Text(
                'Water → dirt → grass → rock on one noise field. Weights are coverage.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),
              for (final m in kLandscapeTerrainFlow)
                _weightSlider(params, m, onChanged),
              const SizedBox(height: 8),
              const Text(
                'Forage patches',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 2),
              const Text(
                'A second noise field stamped over the ground.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 6),
              for (final m in kLandscapeForage)
                _weightSlider(params, m, onChanged),
              const SizedBox(height: 8),
              const Text(
                'Material colors',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 4),
              const Text(
                'HSL range per landscape material.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 8),
              Text(
                'Color σ ${params.colorSigma.toStringAsFixed(2)}',
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
              const SizedBox(height: 4),
              FmSlider(
                value: params.colorSigma.clamp(0.05, 0.6),
                min: 0.05,
                max: 0.6,
                width: 220,
                height: 26,
                onChanged: (v) => onChanged(params.copyWith(colorSigma: v)),
              ),
              const SizedBox(height: 8),
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

  Widget _weightSlider(
    LandscapeGenParams params,
    LandscapeMaterial material,
    ValueChanged<LandscapeGenParams> onChanged,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${material.label} ${params.weights[material]!.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 4),
          FmSlider(
            value: params.weights[material]!.clamp(0, 40),
            min: 0,
            max: 40,
            width: 220,
            height: 26,
            onChanged: (v) {
              final next = Map<LandscapeMaterial, double>.from(params.weights)
                ..[material] = v;
              onChanged(params.copyWith(weights: next));
            },
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
            width: 220,
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
          width: 220,
          height: 22,
          onChanged: (v) => onChanged(color.withHue(v)),
        ),
        FmSlider(
          value: color.saturation,
          min: 0,
          max: 1,
          width: 220,
          height: 22,
          onChanged: (v) => onChanged(color.withSaturation(v)),
        ),
        FmSlider(
          value: color.lightness,
          min: 0,
          max: 1,
          width: 220,
          height: 22,
          onChanged: (v) => onChanged(color.withLightness(v)),
        ),
      ],
    );
  }
}

class _ShadeControls extends StatelessWidget {
  const _ShadeControls({
    required this.shade,
    required this.onChanged,
    required this.shadow,
    required this.onShadowChanged,
  });

  final PlaneShadeModel shade;
  final ValueChanged<PlaneShadeModel> onChanged;
  final GroundShadowModel shadow;
  final ValueChanged<GroundShadowModel> onShadowChanged;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height - 140;
    final litHsl = HSLColor.fromColor(shade.litTint);
    final shadeHsl = HSLColor.fromColor(shade.shadeTint);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH.clamp(180, 560)),
      child: SingleChildScrollView(
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Face shade',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 4),
              _TintBar(shadeTint: shade.shadeTint, litTint: shade.litTint),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _PresetChip(
                    label: 'Blue-purple',
                    selected:
                        shade.shadeTint.toARGB32() ==
                        const Color(0xFF7A74B8).toARGB32(),
                    onTap: () => onChanged(
                      shade.copyWith(
                        litTint: const Color(0xFFFFE08A),
                        shadeTint: const Color(0xFF7A74B8),
                      ),
                    ),
                  ),
                  _PresetChip(
                    label: 'Blue-green',
                    selected:
                        shade.shadeTint.toARGB32() ==
                        const Color(0xFF5E9A8E).toARGB32(),
                    onTap: () => onChanged(
                      shade.copyWith(
                        litTint: const Color(0xFFFFE08A),
                        shadeTint: const Color(0xFF5E9A8E),
                      ),
                    ),
                  ),
                  _PresetChip(
                    label: 'Neutral',
                    selected: shade.tintStrength < 0.02,
                    onTap: () => onChanged(shade.copyWith(tintStrength: 0)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              _labeledSlider(
                label: 'Min shade ${shade.minShade.toStringAsFixed(2)}',
                value: shade.minShade,
                min: 0.15,
                max: 1.0,
                onChanged: (v) => onChanged(shade.copyWith(minShade: v)),
              ),
              _labeledSlider(
                label: 'Max shade ${shade.maxShade.toStringAsFixed(2)}',
                value: shade.maxShade,
                min: 0.15,
                max: 1.0,
                onChanged: (v) => onChanged(shade.copyWith(maxShade: v)),
              ),
              _labeledSlider(
                label: 'Tint ${(shade.tintStrength * 100).round()}%',
                value: shade.tintStrength,
                min: 0,
                max: 0.7,
                onChanged: (v) => onChanged(shade.copyWith(tintStrength: v)),
              ),
              _labeledSlider(
                label: 'Light X ${shade.lightX.toStringAsFixed(2)}',
                value: shade.lightX,
                min: -1,
                max: 1,
                onChanged: (v) => onChanged(shade.copyWith(lightX: v)),
              ),
              _labeledSlider(
                label: 'Light Y ${shade.lightY.toStringAsFixed(2)}',
                value: shade.lightY,
                min: -1,
                max: 1,
                onChanged: (v) => onChanged(shade.copyWith(lightY: v)),
              ),
              _labeledSlider(
                label: 'Light Z ${shade.lightZ.toStringAsFixed(2)}',
                value: shade.lightZ,
                min: -1,
                max: 1,
                onChanged: (v) => onChanged(shade.copyWith(lightZ: v)),
              ),
              _labeledSlider(
                label: 'Lit hue ${litHsl.hue.round()}',
                value: litHsl.hue,
                min: 0,
                max: 360,
                onChanged: (v) => onChanged(
                  shade.copyWith(litTint: litHsl.withHue(v).toColor()),
                ),
              ),
              _labeledSlider(
                label: 'Shade hue ${shadeHsl.hue.round()}',
                value: shadeHsl.hue,
                min: 0,
                max: 360,
                onChanged: (v) => onChanged(
                  shade.copyWith(shadeTint: shadeHsl.withHue(v).toColor()),
                ),
              ),
              const SizedBox(height: 14),
              _ShadowControls(shadow: shadow, onChanged: onShadowChanged),
            ],
          ),
        ),
      ),
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
            width: 220,
            height: 26,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ShadowControls extends StatelessWidget {
  const _ShadowControls({required this.shadow, required this.onChanged});

  final GroundShadowModel shadow;
  final ValueChanged<GroundShadowModel> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ground shadow',
            style: TextStyle(color: Colors.white70, fontSize: 11),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final mode in GroundShadowMode.values)
                _PresetChip(
                  label: switch (mode) {
                    GroundShadowMode.off => 'Off',
                    GroundShadowMode.footprint => 'Footprint',
                    GroundShadowMode.cast => 'Cast',
                  },
                  selected: shadow.mode == mode,
                  onTap: () => onChanged(shadow.copyWith(mode: mode)),
                ),
            ],
          ),
          if (shadow.mode != GroundShadowMode.off) ...[
            const SizedBox(height: 8),
            _shadowSlider(
              label: 'Opacity ${(shadow.opacity * 100).round()}%',
              value: shadow.opacity,
              min: 0.04,
              max: 0.55,
              onChanged: (v) => onChanged(shadow.copyWith(opacity: v)),
            ),
            _shadowSlider(
              label: 'Blur ${shadow.blurSigma.toStringAsFixed(1)}',
              value: shadow.blurSigma,
              min: 0,
              max: 24,
              onChanged: (v) => onChanged(shadow.copyWith(blurSigma: v)),
            ),
            if (shadow.mode == GroundShadowMode.cast)
              _shadowSlider(
                label: 'Stretch ${shadow.maxStretch.toStringAsFixed(1)}',
                value: shadow.maxStretch,
                min: 2,
                max: 32,
                onChanged: (v) => onChanged(shadow.copyWith(maxStretch: v)),
              ),
          ],
        ],
      ),
    );
  }

  Widget _shadowSlider({
    required String label,
    required double value,
    required double min,
    required double max,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          FmSlider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            width: 220,
            height: 22,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _GrainControls extends StatelessWidget {
  const _GrainControls({required this.grain, required this.onChanged});

  final PlaneGrainModel grain;
  final ValueChanged<PlaneGrainModel> onChanged;

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height - 140;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH.clamp(180, 480)),
      child: SingleChildScrollView(
        child: SizedBox(
          width: 220,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Painterly grain',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 4),
              const Text(
                'Perlin dabs of black / white per subtile.',
                style: TextStyle(color: Colors.white38, fontSize: 10),
              ),
              const SizedBox(height: 8),
              _slider(
                label: 'Strength ${(grain.strength * 100).round()}%',
                value: grain.strength,
                min: 0,
                max: 0.45,
                onChanged: (v) => onChanged(grain.copyWith(strength: v)),
              ),
              _slider(
                label: 'Frequency ${grain.frequency.toStringAsFixed(2)}',
                value: grain.frequency,
                min: 0.05,
                max: 1.6,
                onChanged: (v) => onChanged(grain.copyWith(frequency: v)),
              ),
              _slider(
                label: 'Octaves ${grain.octaves}',
                value: grain.octaves.toDouble(),
                min: 1,
                max: 4,
                onChanged: (v) =>
                    onChanged(grain.copyWith(octaves: v.round().clamp(1, 4))),
              ),
              _slider(
                label: 'Bias ${grain.bias.toStringAsFixed(2)}',
                value: grain.bias,
                min: -0.6,
                max: 0.6,
                onChanged: (v) => onChanged(grain.copyWith(bias: v)),
              ),
              _slider(
                label: 'Seed ${grain.seed}',
                value: grain.seed.toDouble(),
                min: 0,
                max: 200,
                onChanged: (v) => onChanged(grain.copyWith(seed: v.round())),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _slider({
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
            width: 220,
            height: 26,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _TintBar extends StatelessWidget {
  const _TintBar({required this.shadeTint, required this.litTint});

  final Color shadeTint;
  final Color litTint;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 12,
      width: 220,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.white24),
        gradient: LinearGradient(colors: [shadeTint, litTint]),
      ),
    );
  }
}

class _PresetChip extends StatelessWidget {
  const _PresetChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? Colors.white24 : Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: selected ? Colors.white38 : Colors.white24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 11,
          ),
        ),
      ),
    );
  }
}

class _PaletteDropdown extends StatelessWidget {
  const _PaletteDropdown({required this.palette, required this.onChanged});

  final LandscapePalette palette;
  final ValueChanged<LandscapePalette> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<LandscapePalette>(
      initialValue: palette,
      color: const Color(0xFF1A1E22),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 280),
      onSelected: onChanged,
      itemBuilder: (context) => [
        for (final p in LandscapePalette.all)
          PopupMenuItem<LandscapePalette>(
            value: p,
            child: Row(
              children: [
                _PaletteSwatches(
                  palette: p,
                  opacity: p.defaultOpacity,
                  width: 72,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.label,
                    style: TextStyle(
                      color: p == palette ? Colors.white : Colors.white70,
                      fontSize: 12,
                      fontWeight: p == palette
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
      child: Container(
        width: 220,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white24),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                palette.label,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.expand_more, color: Colors.white54, size: 16),
          ],
        ),
      ),
    );
  }
}

class _PaletteSwatches extends StatelessWidget {
  const _PaletteSwatches({
    required this.palette,
    required this.opacity,
    this.width,
  });

  final LandscapePalette palette;
  final double opacity;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final colors = palette.previewColors(opacity: opacity);
    return SizedBox(
      width: width ?? 220,
      height: 10,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.white24),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Row(
            children: [
              for (final color in colors)
                Expanded(child: ColoredBox(color: color)),
            ],
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
