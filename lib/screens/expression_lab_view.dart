import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gameplay/friends/friend_desire.dart';
import '../gameplay/friends/friend_expression_pose.dart';
import '../gameplay/friends/friend_eye_profile.dart';
import '../gameplay/friends/friend_eye_profile_io.dart';
import '../gameplay/friends/friend_facing.dart';
import '../gameplay/friends/friend_feeling.dart';
import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../gameplay/friends/friend_thought.dart';
import '../gameplay/friends/friend_thought_display.dart';
import '../gameplay/friends/friend_thought_layout.dart';
import '../gameplay/landscape_cover.dart';
import '../gameplay/paths/path_store.dart';
import '../gameplay/volumes/volume.dart';
import '../gameplay/volumes/volume_store.dart';
import '../landscape/landscape_generator.dart';
import '../landscape/landscape_grid.dart';
import '../landscape/landscape_material.dart';
import '../landscape/landscape_plane_painter.dart';
import '../rendering/lights.dart';
import '../rendering/scene/camera.dart';
import '../rendering/scene/grid_motif.dart';
import '../rendering/scene/map_look_camera_controller.dart';
import '../rendering/scene/scene.dart';
import '../rendering/scene_view.dart';
import '../theme/world_theme.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/friend_eye_overlay.dart';
import '../ui/game/friend_portrait.dart';
import '../ui/game/friend_thought_overlay.dart';
import '../ui/game/game_tool_sidebar.dart';
import '../user/friend_provider.dart';

/// One-tile sandbox for iterating feelings, desires, and thought bubbles.
class ExpressionLabView extends StatefulWidget {
  const ExpressionLabView({super.key});

  @override
  State<ExpressionLabView> createState() => _ExpressionLabViewState();
}

class _ExpressionLabViewState extends State<ExpressionLabView>
    with TickerProviderStateMixin {
  static const _tilesSide = 1;
  static const _tileWorld = 8.0;

  static final _stand = <String, (double x, double z)>{
    kCubeboyFriend.id: (-1.7, 0.55),
    kFrogmanFriend.id: (1.7, 0.55),
    kConicoFriend.id: (0.0, -1.45),
  };

  final _volumes = VolumeStore(
    grid: const VolumeGrid(tilesSide: _tilesSide, tileSize: _tileWorld),
  );
  late final PathStore _paths = PathStore(grid: _volumes.grid);
  final _friends = FriendInstanceStore();
  late final LandscapeGenParams _params;

  late final Camera _camera;
  late final MapLookCameraController _look;
  late final Scene _scene;
  late final GridMotif _gridMotif;
  late final Ticker _ticker;

  String _selectedFriendId = kCubeboyFriend.id;
  final Set<String> _visibleFriendIds = {
    for (final friend in kBedroomFriendTemplates) friend.id,
  };
  bool _lockHover = false;
  FriendThoughtDisplay _thoughtDisplay = const FriendThoughtDisplay();
  FriendEyeProfiles _eyeProfiles = FriendEyeProfiles.empty;
  String? _eyeStatus;
  ui.Image? _atlas;
  Duration? _lastTick;
  Size _viewportSize = Size.zero;
  String? _hoverFriendId;

  Offset? _lastTouchFocalPoint;
  double _lastTouchScale = 1;
  int _mouseButtons = 0;
  int _lastTouchPointerCount = 0;
  bool _pinching = false;

  double get _worldSize => _tilesSide * _tileWorld;
  double get _mapHalf => _worldSize * 0.5;

  Friend get _selectedFriend => friendTemplateById(_selectedFriendId);

  @override
  void initState() {
    super.initState();
    _params = LandscapeGenParams(
      tilesSide: _tilesSide,
      colorSigma: WorldTheme.paperDiorama.colorSigma,
      gradients: WorldTheme.paperDiorama.gradients,
    ).clamped();

    final half = _mapHalf;
    _camera = Camera(
      name: 'expression-lab-cam',
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
      distance: 20,
      minDistance: 10,
      maxDistance: 40,
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
      );
    _gridMotif = GridMotif.subtileLines(worldSize: _volumes.grid.subtileSize);
    _ticker = createTicker(_onTick)..start();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    _eyeProfiles = await FriendEyeProfileIo.load();
    if (!mounted) return;
    _syncLabFriends();
    unawaited(_bakeLandscape());
    setState(() {});
  }

  String _labId(Friend friend) => 'expr-${friend.id}';

  FriendInstance _makeFriend(Friend friend) {
    final stand = _stand[friend.id] ?? (0.0, 0.0);
    final sitY = FriendMeshLayout.sitOnGroundY(tileSize: _tileWorld);
    final instance = FriendInstance(
      id: _labId(friend),
      friend: friend,
      position: Vector3(stand.$1, sitY, stand.$2),
    );
    instance.eyeProfile = _eyeProfiles.forFriend(friend);
    return instance;
  }

  void _syncLabFriends() {
    final visible = [
      for (final friend in kBedroomFriendTemplates)
        if (_visibleFriendIds.contains(friend.id)) friend,
    ];
    final wanted = {for (final friend in visible) _labId(friend)};
    for (final instance in List<FriendInstance>.from(_friends.instances)) {
      if (!wanted.contains(instance.id)) _friends.remove(instance.id);
    }
    for (final friend in visible) {
      if (_friends.byId(_labId(friend)) != null) continue;
      _friends.add(_makeFriend(friend));
    }
    applyEyeProfiles(_friends, _eyeProfiles);
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
  }

  void _setEyeProfile(FriendEyeProfile next) {
    final profile = next.clamped();
    _eyeProfiles = _eyeProfiles.withProfile(_selectedFriendId, profile);
    _selectedInstance?.eyeProfile = profile;
    _selectedInstance?.expression.play(FriendExpressionId.rest);
    setState(() => _eyeStatus = null);
  }

  Future<void> _saveEyeProfiles() async {
    try {
      await FriendEyeProfileIo.save(_eyeProfiles);
      if (!mounted) return;
      setState(() => _eyeStatus = 'Saved eye profiles');
    } catch (e) {
      if (!mounted) return;
      setState(() => _eyeStatus = 'Save failed: $e');
    }
  }

  void _selectHit(String? instanceId) {
    if (instanceId == null) return;
    for (final friend in kBedroomFriendTemplates) {
      if (_labId(friend) == instanceId) {
        setState(() => _selectedFriendId = friend.id);
        return;
      }
    }
  }

  FriendInstance? get _selectedInstance =>
      _friends.byId(_labId(_selectedFriend));

  Future<void> _bakeLandscape() async {
    try {
      final generator = LandscapeGenerator(_params);
      final grid = LandscapeGrid.fromGenerator(generator);
      syncGroundCoverage(
        grid: grid,
        volumes: _volumes,
        paths: _paths,
        generator: generator,
      );
      final image = await generator.bakeAtlasFromGrid(
        grid,
        theme: WorldTheme.paperDiorama,
      );
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _atlas?.dispose();
        _atlas = image;
      });
    } catch (_) {}
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick ?? elapsed;
    _lastTick = elapsed;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.25) return;
    for (final friend in _friends.instances) {
      friend.expression.presenting = true;
      friend.expression.tick(dt, moving: false);
      friend.facing.tick(
        dt,
        moving: false,
        travelYaw: friend.travelYaw,
        cameraYaw: FriendFacing.cameraFacingYaw(
          friend.position,
          _camera.position,
        ),
      );
      final hovered = _lockHover
          ? friend.id == _labId(_selectedFriend)
          : _hoverFriendId == friend.id;
      friend.thought.tick(
        dt,
        inView: friendThoughtInView(
          friend: friend,
          camera: _camera,
          viewport: _viewportSize,
          tileSize: _tileWorld,
        ),
        hovered: hovered,
      );
    }
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    if (mounted) setState(() {});
  }

  void _setPointer(Offset local) {
    final next = hitFriendId(
      screen: local,
      viewport: _viewportSize,
      camera: _camera,
      friends: _friends,
      tileSize: _tileWorld,
    );
    if (next != _hoverFriendId) {
      setState(() => _hoverFriendId = next);
    }
  }

  void _onCameraChanged() {
    _look.setViewportSize(_viewportSize);
    _scene.markNeedsPaint();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _ticker.dispose();
    _look
      ..removeListener(_onCameraChanged)
      ..dispose();
    _gridMotif.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: WorldTheme.paperDiorama.background,
      overlays: [
        const FmDevBackButton(),
        FmSafePositioned(
          top: 56,
          left: 12,
          child: _FriendPicker(
            selectedId: _selectedFriendId,
            visibleIds: _visibleFriendIds,
            onSelect: (id) => setState(() => _selectedFriendId = id),
            onVisibleChanged: (id, visible) {
              setState(() {
                if (visible) {
                  _visibleFriendIds.add(id);
                } else {
                  _visibleFriendIds.remove(id);
                }
              });
              _syncLabFriends();
            },
          ),
        ),
        FmSafePositioned(
          top: 12,
          right: 12,
          child: _ExpressionPanel(
            friendName: _selectedFriend.name,
            eye: _eyeProfiles.forKey(_selectedFriendId),
            eyeStatus: _eyeStatus,
            onEyeChanged: _setEyeProfile,
            onSaveEyes: _saveEyeProfiles,
            onResetEyes: () => _setEyeProfile(FriendEyeProfile.defaults),
            thought: _selectedInstance?.thought,
            display: _thoughtDisplay,
            onDisplayChanged: (next) => setState(() => _thoughtDisplay = next),
            lockHover: _lockHover,
            onLockHover: (v) => setState(() => _lockHover = v),
            onFeeling: (feeling) {
              _selectedInstance?.thought.setFeeling(feeling);
              setState(() {});
            },
            onDesire: (desire) {
              _selectedInstance?.thought.setDesire(desire);
              setState(() {});
            },
            onShowFeelingNow: () {
              _selectedInstance?.thought.showFeelingNow();
              setState(() {});
            },
          ),
        ),
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
          onPointerHover: (event) => _setPointer(event.localPosition),
          onPointerDown: (event) {
            _setPointer(event.localPosition);
            _selectHit(_hoverFriendId);
            if (event.kind == PointerDeviceKind.mouse) {
              _mouseButtons = event.buttons;
            }
          },
          onPointerMove: (event) {
            _setPointer(event.localPosition);
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
              _lastTouchScale = 1;
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
              final focal = details.focalPoint;
              if (_lastTouchFocalPoint != null) {
                _look.pan(focal - _lastTouchFocalPoint!);
                if (details.pointerCount >= 2) {
                  final scaleChange = details.scale / _lastTouchScale;
                  if (scaleChange > 0 && scaleChange != 1) {
                    _look.zoomByScale(scaleChange);
                  }
                }
              }
              _lastTouchFocalPoint = focal;
              _lastTouchScale = details.scale;
            },
            onScaleEnd: (_) {
              if (_pinching) {
                _look.endZoom();
                _pinching = false;
              }
              _lastTouchFocalPoint = null;
              _lastTouchScale = 1;
              _lastTouchPointerCount = 0;
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                CustomPaint(
                  painter: LandscapePlanePainter(
                    camera: _camera,
                    listenable: _scene,
                    image: _atlas,
                    worldSize: _worldSize,
                    tilesSide: _tilesSide,
                    pixelsPerTile: _volumes.grid.subtilesPerTile,
                    backgroundColor: WorldTheme.paperDiorama.background,
                    shade: WorldTheme.paperDiorama.shade,
                  ),
                  isComplex: true,
                  willChange: true,
                  child: const SizedBox.expand(),
                ),
                SceneView(
                  scene: _scene,
                  gridMotif: _gridMotif,
                ),
                FriendEyeOverlay(
                  friends: _friends,
                  camera: _camera,
                  viewport: _viewportSize,
                  tileSize: _tileWorld,
                  listenable: _scene,
                ),
                FriendThoughtOverlay(
                  friends: _friends,
                  camera: _camera,
                  viewport: _viewportSize,
                  display: _thoughtDisplay,
                  tileSize: _tileWorld,
                  listenable: _scene,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FriendPicker extends StatelessWidget {
  const _FriendPicker({
    required this.selectedId,
    required this.visibleIds,
    required this.onSelect,
    required this.onVisibleChanged,
  });

  final String selectedId;
  final Set<String> visibleIds;
  final ValueChanged<String> onSelect;
  final void Function(String friendId, bool visible) onVisibleChanged;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 228),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Friends',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              for (final friend in kBedroomFriendTemplates)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Material(
                    color: friend.id == selectedId
                        ? Colors.white24
                        : Colors.white10,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      onTap: () => onSelect(friend.id),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 8, 6),
                        child: Row(
                          children: [
                            Checkbox(
                              value: visibleIds.contains(friend.id),
                              onChanged: (v) =>
                                  onVisibleChanged(friend.id, v ?? false),
                              visualDensity: VisualDensity.compact,
                              side: const BorderSide(color: Colors.white54),
                            ),
                            FriendPortrait(
                              friend: friend,
                              size: 34,
                              selected: friend.id == selectedId,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              friend.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExpressionPanel extends StatelessWidget {
  const _ExpressionPanel({
    required this.friendName,
    required this.eye,
    required this.eyeStatus,
    required this.onEyeChanged,
    required this.onSaveEyes,
    required this.onResetEyes,
    required this.thought,
    required this.display,
    required this.onDisplayChanged,
    required this.lockHover,
    required this.onLockHover,
    required this.onFeeling,
    required this.onDesire,
    required this.onShowFeelingNow,
  });

  final String friendName;
  final FriendEyeProfile eye;
  final String? eyeStatus;
  final ValueChanged<FriendEyeProfile> onEyeChanged;
  final VoidCallback onSaveEyes;
  final VoidCallback onResetEyes;
  final FriendThought? thought;
  final FriendThoughtDisplay display;
  final ValueChanged<FriendThoughtDisplay> onDisplayChanged;
  final bool lockHover;
  final ValueChanged<bool> onLockHover;
  final ValueChanged<Feeling?> onFeeling;
  final ValueChanged<Desire?> onDesire;
  final VoidCallback onShowFeelingNow;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 280, maxHeight: 620),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white24),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Eyes · $friendName',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Click a friend, then tune and save.',
                style: TextStyle(color: Colors.white54, fontSize: 10),
              ),
              const SizedBox(height: 8),
              _slider(
                label: 'Distance',
                value: eye.spacing,
                min: 0.35,
                max: 2.2,
                onChanged: (v) => onEyeChanged(eye.copyWith(spacing: v)),
              ),
              _slider(
                label: 'Size',
                value: eye.size,
                min: 0.25,
                max: 2.8,
                onChanged: (v) => onEyeChanged(eye.copyWith(size: v)),
              ),
              _slider(
                label: 'Width',
                value: eye.width,
                min: 0.25,
                max: 2.8,
                onChanged: (v) => onEyeChanged(eye.copyWith(width: v)),
              ),
              _slider(
                label: 'Height',
                value: eye.height,
                min: 0.25,
                max: 2.8,
                onChanged: (v) => onEyeChanged(eye.copyWith(height: v)),
              ),
              _slider(
                label: 'Lift',
                value: eye.lift,
                min: -0.6,
                max: 0.6,
                onChanged: (v) => onEyeChanged(eye.copyWith(lift: v)),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onResetEyes,
                      child: const Text('Reset eyes'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: onSaveEyes,
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
              if (eyeStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  eyeStatus!,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Thoughts',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              _DisplayCheck(
                label: 'Show feelings',
                value: display.showFeelings,
                onChanged: (v) =>
                    onDisplayChanged(display.copyWith(showFeelings: v)),
              ),
              _DisplayCheck(
                label: 'Show desires',
                value: display.showDesires,
                onChanged: (v) =>
                    onDisplayChanged(display.copyWith(showDesires: v)),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Lock hover',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                  Switch(
                    value: lockHover,
                    onChanged: onLockHover,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              OutlinedButton(
                onPressed: !display.showFeelings || thought?.feeling == null
                    ? null
                    : onShowFeelingNow,
                child: const Text('Show feeling now'),
              ),
              const SizedBox(height: 12),
              const Text(
                'Feelings',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(
                    label: 'None',
                    selected: thought?.feeling == null,
                    onTap: () => onFeeling(null),
                  ),
                  for (final feeling in kFeelings)
                    _Chip(
                      label: '${feeling.icon} ${feeling.name}',
                      selected: thought?.feeling?.id == feeling.id,
                      onTap: () => onFeeling(feeling),
                    ),
                ],
              ),
              const SizedBox(height: 14),
              const Text(
                'Desires',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _Chip(
                    label: 'None',
                    selected: thought?.desire == null,
                    onTap: () => onDesire(null),
                  ),
                  for (final desire in kDesires)
                    _Chip(
                      label: '${desire.icon} ${desire.name}',
                      selected: thought?.desire?.id == desire.id,
                      onTap: () => onDesire(desire),
                    ),
                ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ),
            Text(
              value.toStringAsFixed(2),
              style: const TextStyle(color: Colors.white, fontSize: 11),
            ),
          ],
        ),
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.white70,
            inactiveTrackColor: Colors.white24,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _DisplayCheck extends StatelessWidget {
  const _DisplayCheck({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                fontSize: 12,
              ),
            ),
          ),
          SizedBox(
            height: 28,
            width: 36,
            child: Checkbox(
              value: value,
              onChanged: (v) => onChanged(v ?? false),
              visualDensity: VisualDensity.compact,
              side: const BorderSide(color: Colors.white54),
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white24;
                }
                return Colors.transparent;
              }),
              checkColor: Colors.white,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Colors.white24 : Colors.white10,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : Colors.white70,
              fontSize: 11,
            ),
          ),
        ),
      ),
    );
  }
}
