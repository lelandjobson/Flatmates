import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gameplay/flatmates/movement_assignment.dart';
import '../gameplay/flatmates/movement_profile.dart';
import '../gameplay/flatmates/movement_profile_io.dart';
import '../gameplay/friends/friend_eye_profile_io.dart';
import '../gameplay/friends/friend_facing.dart';
import '../gameplay/friends/friend_instance.dart';
import '../gameplay/friends/friend_instance_store.dart';
import '../gameplay/friends/friend_mesh_sync.dart';
import '../gameplay/friends/friend_thought_layout.dart';
import '../gameplay/friends/friend_trail.dart';
import '../gameplay/landscape_cover.dart';
import '../gameplay/paths/path_mesh.dart';
import '../gameplay/paths/path_outline.dart';
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
import '../ui/game/friend_trail_overlay.dart';
import '../ui/game/game_tool_sidebar.dart';
import '../ui/game/movement_curve_overlay.dart';
import '../user/friend_provider.dart';

/// 6×6 GameView-scale sandbox for tuning movement patterns on a loop track.
class MovementLabView extends StatefulWidget {
  const MovementLabView({super.key});

  @override
  State<MovementLabView> createState() => _MovementLabViewState();
}

class _MovementLabViewState extends State<MovementLabView>
    with TickerProviderStateMixin {
  static const _tilesSide = 6;
  static const _tileWorld = 8.0;

  final _volumes = VolumeStore(
    grid: const VolumeGrid(tilesSide: _tilesSide, tileSize: _tileWorld),
  );
  late final PathStore _paths = PathStore(grid: _volumes.grid);
  final _pathOutlines = PathOutlineStore();
  final _friends = FriendInstanceStore();
  final _trails = FriendTrailStore();
  late final LandscapeGenParams _params;

  late final Camera _camera;
  late final MapLookCameraController _look;
  late final Scene _scene;
  late final GridMotif _gridMotif;
  late final Ticker _ticker;

  MovementProfile _profile = MovementProfile.hop;
  MovementLabTrack _track = kMovementLabTracks.first;
  double _trailScale = 1;
  MovementAssignments _assignments = MovementAssignments.empty;
  FriendEyeProfiles _eyeProfiles = FriendEyeProfiles.empty;
  List<MovementProfile> _saved = const [];
  final _nameController = TextEditingController(text: 'Lab take');
  String? _status;
  String _selectedFriendId = kCubeboyFriend.id;
  final Set<String> _visibleFriendIds = {
    for (final friend in kBedroomFriendTemplates) friend.id,
  };

  bool _playing = true;
  bool _reversed = false;
  bool _showCurve = true;
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

  List<(int, int)> get _forwardTiles => List<(int, int)>.from(_track.tiles);

  List<(int, int)> get _reverseTiles => _reversedLoop(_track.tiles);

  List<(int, int)> get _activeTiles =>
      _reversed ? _reverseTiles : _forwardTiles;

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
      name: 'movement-lab-cam',
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
      distance: 48,
      minDistance: 18,
      maxDistance: 80,
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

    for (final tile in _track.tiles.toSet()) {
      _paths.placeAndJoin(tile.$1, tile.$2);
    }
    syncPathMeshes(
      _scene,
      _paths,
      _volumes,
      color: WorldTheme.paperDiorama.path,
    );
    _pathOutlines.rebuild(paths: _paths, volumes: _volumes);

    _ticker = createTicker(_onTick)..start();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _reloadSaved();
    _eyeProfiles = await FriendEyeProfileIo.load();
    await _selectFriend(_selectedFriendId, loadPattern: true);
    if (!mounted) return;
    _syncLabFriends();
    unawaited(_bakeLandscape());
  }

  String _labId(Friend friend) => 'lab-${friend.id}';

  FriendInstance _makeFriend(Friend friend) {
    final start = _volumes.grid.tileCenter(
      _track.tiles.first.$1,
      _track.tiles.first.$2,
    );
    start.y = FriendMeshLayout.sitOnGroundY(tileSize: _tileWorld);
    final instance = FriendInstance(
      id: _labId(friend),
      friend: friend,
      position: start,
    );
    instance.eyeProfile = _eyeProfiles.forFriend(friend);
    return instance;
  }

  Future<void> _reloadSaved() async {
    final list = await MovementProfileIo.list();
    final assignments = await MovementAssignmentIo.load();
    if (!mounted) return;
    setState(() {
      _saved = list;
      _assignments = assignments;
    });
  }

  MovementProfile _patternById(String? id) {
    if (id == null) return _fallbackPattern();
    for (final profile in _saved) {
      if (profile.id == id) return profile;
    }
    return _fallbackPattern();
  }

  MovementProfile _fallbackPattern() {
    for (final profile in _saved) {
      if (profile.id == 'default') return profile;
    }
    return MovementProfile.hop.copyWith(id: 'default', name: 'Default');
  }

  MovementProfile _liveProfileFor(Friend friend) {
    final assigned = _assignments.patternIdFor(friend.id);
    if (friend.id == _selectedFriendId || assigned == _profile.id) {
      return _profile;
    }
    return _patternById(assigned);
  }

  void _syncLabFriends({bool restart = false}) {
    final visible = [
      for (final friend in kBedroomFriendTemplates)
        if (_visibleFriendIds.contains(friend.id)) friend,
    ];
    final wanted = {for (final friend in visible) _labId(friend)};
    for (final instance in List<FriendInstance>.from(_friends.instances)) {
      if (!wanted.contains(instance.id)) _friends.remove(instance.id);
    }
    for (var i = 0; i < visible.length; i++) {
      final friend = visible[i];
      final id = _labId(friend);
      var instance = _friends.byId(id);
      final isNew = instance == null;
      if (isNew) {
        instance = _makeFriend(friend);
        _friends.add(instance);
      }
      final tilesChanged = !_sameTiles(instance.movement.tiles, _activeTiles);
      if (isNew || restart || tilesChanged) {
        final startFrom = Offset(instance.position.x, instance.position.z);
        instance.movement.start(
          _activeTiles,
          grid: _volumes.grid,
          profile: _liveProfileFor(friend),
          paths: _paths,
          seed: instance.id,
          loop: true,
          startFrom: startFrom,
        );
        if (visible.length > 1) {
          instance.movement.progress = i / visible.length;
          instance.movement.captureStartFrom(startFrom, entryAtDistance: true);
        }
      } else {
        instance.movement.applyProfile(
          _liveProfileFor(friend),
          _volumes.grid,
          paths: _paths,
        );
      }
      _applyPose(instance);
    }
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
  }

  void _startVisibleFriends() {
    for (final friend in _friends.instances) {
      friend.movement.requestStart(
        startFrom: Offset(friend.position.x, friend.position.z),
      );
      _applyPose(friend);
    }
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    setState(() {});
  }

  void _stopVisibleFriends() {
    for (final friend in _friends.instances) {
      friend.movement.requestStop();
      _applyPose(friend);
    }
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    setState(() {});
  }

  void _startFriend(String friendId) {
    final instance = _friends.byId(_labId(friendTemplateById(friendId)));
    if (instance == null) return;
    instance.movement.requestStart(
      startFrom: Offset(instance.position.x, instance.position.z),
    );
    _applyPose(instance);
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    setState(() {});
  }

  void _stopFriend(String friendId) {
    final instance = _friends.byId(_labId(friendTemplateById(friendId)));
    instance?.movement.requestStop();
    if (instance != null) _applyPose(instance);
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    setState(() {});
  }

  void _cycleTrack(int delta) {
    final i = kMovementLabTracks.indexWhere((t) => t.id == _track.id);
    final next = (i + delta) % kMovementLabTracks.length;
    _setTrack(kMovementLabTracks[next < 0 ? next + kMovementLabTracks.length : next]);
  }

  void _setTrack(MovementLabTrack track) {
    if (track.id == _track.id) return;
    setState(() => _track = track);
    _paths.restore(tiles: {}, edges: {});
    for (final tile in track.tiles.toSet()) {
      _paths.placeAndJoin(tile.$1, tile.$2);
    }
    syncPathMeshes(
      _scene,
      _paths,
      _volumes,
      color: WorldTheme.paperDiorama.path,
    );
    _pathOutlines.rebuild(paths: _paths, volumes: _volumes);
    _trails.clear();
    _syncLabFriends(restart: true);
    unawaited(_bakeLandscape());
  }

  void _rebuildCurves() {
    for (final instance in _friends.instances) {
      if (instance.movement.tiles.length < 2) continue;
      instance.movement.applyProfile(
        _liveProfileFor(instance.friend),
        _volumes.grid,
        paths: _paths,
      );
      _applyPose(instance);
    }
    syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
  }

  void _applyPose(FriendInstance friend) {
    final sitY = FriendMeshLayout.sitOnGroundY(tileSize: _tileWorld);
    if (friend.movement.tiles.isEmpty) return;
    friend.position.setFrom(
      friend.movement.worldPosition(
        _volumes.grid,
        sitY,
        swaySeed: friend.id,
        bodySize: FriendMeshLayout.worldSize(tileSize: _tileWorld),
        paths: _paths,
      ),
    );
    friend.travelYaw = friend.movement.facingYaw();
    friend.pitch = friend.movement.pitch;
    if (friend.position.y < sitY) friend.position.y = sitY;
  }

  void _onTick(Duration elapsed) {
    final last = _lastTick ?? elapsed;
    _lastTick = elapsed;
    final dt = (elapsed - last).inMicroseconds / 1e6;
    if (dt <= 0 || dt > 0.25) return;
    _trails.advance(dt);
    if (_playing) {
      for (final friend in _friends.instances) {
        friend.movement.advance(
          dt: dt,
          baseTilesPerSecond: _liveProfileFor(friend.friend).tileSpeed,
          onPath: _paths.contains,
          grid: _volumes.grid,
          paths: _paths,
        );
        _applyPose(friend);
        if (_trailScale > 0) _trails.record(friend);
        friend.expression.presenting = friend.presenting;
        friend.expression.tick(dt, moving: friend.movement.isMoving);
        friend.facing.tick(
          dt,
          moving: friend.movement.isMoving,
          travelYaw: friend.travelYaw,
          cameraYaw: FriendFacing.cameraFacingYaw(
            friend.position,
            _camera.position,
          ),
          rotationInertia: _liveProfileFor(friend.friend).rotationInertia,
        );
        friend.thought.tick(
          dt,
          inView: friendThoughtInView(
            friend: friend,
            camera: _camera,
            viewport: _viewportSize,
            tileSize: _tileWorld,
          ),
          hovered: _hoverFriendId == friend.id,
        );
      }
      syncFriendMeshes(_scene, _friends, tileSize: _tileWorld);
    }
    if (mounted && (_playing || !_trails.isEmpty)) setState(() {});
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

  void _setProfile(MovementProfile next) {
    _profile = next.clamped();
    _rebuildCurves();
    setState(() {});
  }

  Future<void> _selectFriend(
    String friendId, {
    required bool loadPattern,
  }) async {
    _selectedFriendId = friendId;
    if (loadPattern) {
      final assigned = _assignments.patternIdFor(friendId);
      final pattern = _patternById(assigned);
      _profile = pattern;
      _nameController.text = pattern.name;
    }
    if (mounted) setState(() {});
    _rebuildCurves();
  }

  Future<void> _saveProfile() async {
    final rawName = _nameController.text.trim();
    final name = rawName.isEmpty ? 'Lab take' : rawName;
    final profile = _profile.copyWith(
      id: movementProfileSlug(name),
      name: name,
    );
    try {
      final path = await MovementProfileIo.save(profile);
      _profile = profile;
      await _reloadSaved();
      if (!mounted) return;
      setState(() => _status = 'Saved $path');
      _rebuildCurves();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Save failed: $e');
    }
  }

  Future<void> _duplicatePattern() async {
    final taken = {for (final p in _saved) p.id};
    final id = movementPatternCopyId(_profile.id, taken);
    final copy = _profile.copyWith(
      id: id,
      name: movementPatternCopyName(_profile.name),
    );
    try {
      await MovementProfileIo.save(copy);
      _profile = copy;
      _nameController.text = copy.name;
      await _reloadSaved();
      if (!mounted) return;
      setState(() => _status = 'Duplicated as ${copy.name}');
      _rebuildCurves();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Duplicate failed: $e');
    }
  }

  Future<void> _assignFriend(String? friendId) async {
    try {
      await _saveProfile();
      var next = _assignments;
      if (friendId == null) {
        for (final id in _assignments.friendIdsFor(_profile.id)) {
          next = next.withoutFriend(id);
        }
        next = next.withoutFriend(_selectedFriendId);
      } else {
        next = next.assign(friendId: friendId, patternId: _profile.id);
        _selectedFriendId = friendId;
      }
      await MovementAssignmentIo.save(next);
      _assignments = next;
      if (!mounted) return;
      setState(() {
        _status = friendId == null
            ? 'Cleared default for ${_selectedFriend.name}'
            : '${friendTemplateById(friendId).name} uses ${_profile.name}';
      });
      _rebuildCurves();
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Assign failed: $e');
    }
  }

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Landscape bake failed: $e');
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _nameController.dispose();
    _look
      ..removeListener(_onCameraChanged)
      ..dispose();
    _gridMotif.dispose();
    _atlas?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final assignedIds = _assignments.friendIdsFor(_profile.id);
    final dropdownValue = assignedIds.contains(_selectedFriendId)
        ? _selectedFriendId
        : (assignedIds.isEmpty ? null : assignedIds.first);
    final overlayFriend =
        _friends.byId(_labId(_selectedFriend)) ??
        (_friends.instances.isEmpty ? null : _friends.instances.first);

    return FmScreen(
      backgroundColor: WorldTheme.paperDiorama.background,
      overlays: [
        const FmDevBackButton(),
        FmSafePositioned(
          top: 56,
          left: 12,
          child: _FriendCascade(
            selectedId: _selectedFriendId,
            visibleIds: _visibleFriendIds,
            assignments: _assignments,
            saved: _saved,
            canStart: {
              for (final friend in kBedroomFriendTemplates)
                friend.id:
                    _friends.byId(_labId(friend))?.movement.canRequestStart ??
                    false,
            },
            canStop: {
              for (final friend in kBedroomFriendTemplates)
                friend.id:
                    _friends.byId(_labId(friend))?.movement.canRequestStop ??
                    false,
            },
            onStart: _startFriend,
            onStop: _stopFriend,
            onSelect: (id) => _selectFriend(id, loadPattern: true),
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
          child: _LabPanel(
            profile: _profile,
            trackName: _track.name,
            trailScale: _trailScale,
            saved: _saved,
            nameController: _nameController,
            status: _status,
            playing: _playing,
            reversed: _reversed,
            showCurve: _showCurve,
            assignedFriendId: dropdownValue,
            onProfileChanged: _setProfile,
            onPlayPause: () => setState(() => _playing = !_playing),
            onStart: _startVisibleFriends,
            onStop: _stopVisibleFriends,
            onTrackPrev: () => _cycleTrack(-1),
            onTrackNext: () => _cycleTrack(1),
            onTrailScale: (v) => setState(() => _trailScale = v),
            onReverse: () {
              setState(() => _reversed = !_reversed);
              _syncLabFriends(restart: true);
            },
            onShowCurve: (v) => setState(() => _showCurve = v),
            onSave: _saveProfile,
            onDuplicate: _duplicatePattern,
            onAssignFriend: _assignFriend,
            onLoad: (profile) {
              _nameController.text = profile.name;
              _setProfile(profile);
              setState(() => _status = 'Loaded ${profile.name}');
            },
            onReset: () {
              final fallback = _fallbackPattern();
              _nameController.text = fallback.name;
              _setProfile(fallback);
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
      background: _buildViewport(overlayFriend),
    );
  }

  Widget _buildViewport(FriendInstance? overlayFriend) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        _look.setViewportSize(_viewportSize);
        return Listener(
          onPointerHover: (event) => _setPointer(event.localPosition),
          onPointerDown: (event) {
            _setPointer(event.localPosition);
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
                  groundOutlines: _pathOutlines.edges,
                ),
                FriendTrailOverlay(
                  trails: _trails,
                  camera: _camera,
                  viewport: _viewportSize,
                  tileSize: _tileWorld,
                  friends: _friends,
                  listenable: _scene,
                  scale: _trailScale,
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
                  tileSize: _tileWorld,
                  listenable: _scene,
                ),
                if (_showCurve)
                  MovementCurveOverlay(
                    curve: overlayFriend?.movement.curve,
                    camera: _camera,
                    viewport: _viewportSize,
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

class MovementLabTrack {
  const MovementLabTrack({
    required this.id,
    required this.name,
    required this.tiles,
  });

  final String id;
  final String name;
  final List<(int, int)> tiles;
}

const kDonutTrack = MovementLabTrack(
  id: 'donut',
  name: 'Donut',
  tiles: [
    (-2, -2),
    (-1, -2),
    (0, -2),
    (1, -2),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (-1, 1),
    (-2, 1),
    (-2, 0),
    (-2, -1),
    (-2, -2),
  ],
);

const kHairpinTrack = MovementLabTrack(
  id: 'hairpin',
  name: 'Hairpin',
  tiles: [
    (-2, -2),
    (-1, -2),
    (0, -2),
    (1, -2),
    (1, -1),
    (1, 0),
    (1, 1),
    (0, 1),
    (0, 0),
    (0, -1),
    (-1, -1),
    (-1, 0),
    (-1, 1),
    (-2, 1),
    (-2, 0),
    (-2, -1),
    (-2, -2),
  ],
);

const kMovementLabTracks = [kDonutTrack, kHairpinTrack];

bool _sameTiles(List<(int, int)> a, List<(int, int)> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

List<(int, int)> _reversedLoop(List<(int, int)> tiles) {
  if (tiles.length < 2) return List<(int, int)>.from(tiles);
  if (tiles.first == tiles.last) {
    final body = tiles.sublist(0, tiles.length - 1).reversed.toList();
    return [...body, body.first];
  }
  return tiles.reversed.toList();
}

class _FriendCascade extends StatelessWidget {
  const _FriendCascade({
    required this.selectedId,
    required this.visibleIds,
    required this.assignments,
    required this.saved,
    required this.canStart,
    required this.canStop,
    required this.onStart,
    required this.onStop,
    required this.onSelect,
    required this.onVisibleChanged,
  });

  final String selectedId;
  final Set<String> visibleIds;
  final MovementAssignments assignments;
  final List<MovementProfile> saved;
  final Map<String, bool> canStart;
  final Map<String, bool> canStop;
  final ValueChanged<String> onStart;
  final ValueChanged<String> onStop;
  final ValueChanged<String> onSelect;
  final void Function(String friendId, bool visible) onVisibleChanged;

  String _patternLabel(String friendId) {
    final id = assignments.patternIdFor(friendId);
    if (id == null) return 'No pattern';
    for (final profile in saved) {
      if (profile.id == id) return profile.name;
    }
    return id;
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 248),
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
              const SizedBox(height: 4),
              const Text(
                'Show in lab · tap to edit',
                style: TextStyle(color: Colors.white54, fontSize: 10),
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
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    friend.name,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  Text(
                                    _patternLabel(friend.id),
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (visibleIds.contains(friend.id))
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _miniIcon(
                                    Icons.play_arrow,
                                    enabled: canStart[friend.id] ?? false,
                                    onTap: () => onStart(friend.id),
                                  ),
                                  _miniIcon(
                                    Icons.stop,
                                    enabled: canStop[friend.id] ?? false,
                                    onTap: () => onStop(friend.id),
                                  ),
                                ],
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

  Widget _miniIcon(
    IconData icon, {
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: 28,
      height: 28,
      child: IconButton(
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        iconSize: 16,
        color: enabled ? Colors.white : Colors.white24,
        onPressed: enabled ? onTap : null,
        icon: Icon(icon),
      ),
    );
  }
}

class _LabPanel extends StatelessWidget {
  const _LabPanel({
    required this.profile,
    required this.trackName,
    required this.trailScale,
    required this.saved,
    required this.nameController,
    required this.status,
    required this.playing,
    required this.reversed,
    required this.showCurve,
    required this.assignedFriendId,
    required this.onProfileChanged,
    required this.onPlayPause,
    required this.onStart,
    required this.onStop,
    required this.onTrackPrev,
    required this.onTrackNext,
    required this.onTrailScale,
    required this.onReverse,
    required this.onShowCurve,
    required this.onSave,
    required this.onDuplicate,
    required this.onAssignFriend,
    required this.onLoad,
    required this.onReset,
  });

  final MovementProfile profile;
  final String trackName;
  final double trailScale;
  final List<MovementProfile> saved;
  final TextEditingController nameController;
  final String? status;
  final bool playing;
  final bool reversed;
  final bool showCurve;
  final String? assignedFriendId;
  final ValueChanged<MovementProfile> onProfileChanged;
  final VoidCallback onPlayPause;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onTrackPrev;
  final VoidCallback onTrackNext;
  final ValueChanged<double> onTrailScale;
  final VoidCallback onReverse;
  final ValueChanged<bool> onShowCurve;
  final VoidCallback onSave;
  final VoidCallback onDuplicate;
  final ValueChanged<String?> onAssignFriend;
  final ValueChanged<MovementProfile> onLoad;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320, maxHeight: 680),
      child: Material(
        color: Colors.black.withValues(alpha: 0.78),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white24),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Movement pattern',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  _chip(
                    playing ? 'Pause' : 'Play',
                    onPlayPause,
                    selected: playing,
                  ),
                  _chip('Start', onStart),
                  _chip('Stop', onStop),
                  _chip('Reverse', onReverse, selected: reversed),
                ],
              ),
              Row(
                children: [
                  _chip('⟨', onTrackPrev),
                  Expanded(
                    child: Text(
                      trackName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  _chip('⟩', onTrackNext),
                ],
              ),
              _slider(
                label: 'Trail scale',
                value: trailScale,
                onChanged: onTrailScale,
              ),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Show curve',
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ),
                  Switch(value: showCurve, onChanged: onShowCurve),
                ],
              ),
              const Text(
                'Default for',
                style: TextStyle(color: Colors.white70, fontSize: 11),
              ),
              DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  isExpanded: true,
                  isDense: true,
                  dropdownColor: const Color(0xFF1A1A1A),
                  value: assignedFriendId,
                  hint: const Text(
                    'Assign a friend',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                  iconEnabledColor: Colors.white70,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('None'),
                    ),
                    for (final friend in kBedroomFriendTemplates)
                      DropdownMenuItem<String?>(
                        value: friend.id,
                        child: Row(
                          children: [
                            FriendPortrait(friend: friend, size: 22),
                            const SizedBox(width: 8),
                            Text(friend.name),
                          ],
                        ),
                      ),
                  ],
                  onChanged: onAssignFriend,
                ),
              ),
              _slider(
                label: 'Tile ratio',
                value: profile.movementTileRatio,
                min: 0.25,
                max: 3,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(movementTileRatio: v)),
              ),
              _slider(
                label: 'Offset',
                value: profile.offset,
                onChanged: (v) => onProfileChanged(profile.copyWith(offset: v)),
              ),
              _slider(
                label: 'Jank',
                value: profile.jank,
                onChanged: (v) => onProfileChanged(profile.copyWith(jank: v)),
              ),
              _slider(
                label: 'Jank intensity',
                value: profile.jankIntensity,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(jankIntensity: v)),
              ),
              _slider(
                label: 'Smoothness',
                value: profile.smoothness,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(smoothness: v)),
              ),
              _slider(
                label: 'Bend slowdown',
                value: profile.bendSlowdown,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(bendSlowdown: v)),
              ),
              _slider(
                label: 'Hop height',
                value: profile.hopHeight,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(hopHeight: v)),
              ),
              _slider(
                label: 'Tile speed',
                value: profile.tileSpeed,
                min: 0.5,
                max: 6,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(tileSpeed: v)),
              ),
              _slider(
                label: 'Rotation inertia',
                value: profile.rotationInertia,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(rotationInertia: v)),
              ),
              _slider(
                label: 'Start backup',
                value: profile.startBackup,
                max: 0.5,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(startBackup: v)),
              ),
              _slider(
                label: 'Start seconds',
                value: profile.startSeconds,
                min: 0.05,
                max: 0.8,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(startSeconds: v)),
              ),
              _slider(
                label: 'Start tilt',
                value: profile.startTilt,
                max: 0.45,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(startTilt: v)),
              ),
              _slider(
                label: 'Stop slide',
                value: profile.stopSlide,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(stopSlide: v)),
              ),
              _slider(
                label: 'Stop seconds',
                value: profile.stopSeconds,
                min: 0.05,
                max: 1,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(stopSeconds: v)),
              ),
              _slider(
                label: 'Stop tilt',
                value: profile.stopTilt,
                max: 0.45,
                onChanged: (v) =>
                    onProfileChanged(profile.copyWith(stopTilt: v)),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: nameController,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  isDense: true,
                  labelText: 'Pattern name',
                  labelStyle: TextStyle(color: Colors.white54),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _chip('Save', onSave)),
                  const SizedBox(width: 6),
                  Expanded(child: _chip('Duplicate', onDuplicate)),
                ],
              ),
              const SizedBox(height: 6),
              _chip('Reset', onReset),
              if (saved.isNotEmpty) ...[
                const SizedBox(height: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    dropdownColor: const Color(0xFF1A1A1A),
                    value: saved.any((p) => p.id == profile.id)
                        ? profile.id
                        : saved.first.id,
                    iconEnabledColor: Colors.white70,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                    items: [
                      for (final item in saved)
                        DropdownMenuItem(
                          value: item.id,
                          child: Text(item.name),
                        ),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      for (final item in saved) {
                        if (item.id == id) onLoad(item);
                      }
                    },
                  ),
                ),
              ],
              if (status != null) ...[
                const SizedBox(height: 8),
                Text(
                  status!,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String label, VoidCallback onTap, {bool selected = false}) {
    return Material(
      color: selected ? Colors.white24 : Colors.white10,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ),
      ),
    );
  }

  Widget _slider({
    required String label,
    required double value,
    double min = 0,
    double max = 1,
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
