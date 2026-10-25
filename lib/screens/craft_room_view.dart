import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../asmr/asmr_desk_chrome.dart';
import '../asmr/asmr_desk_painter.dart';
import '../asmr/asmr_dev.dart';
import '../asmr/asmr_flight.dart';
import '../asmr/asmr_mapping.dart';
import '../asmr/asmr_model_paper.dart';
import '../asmr/asmr_net.dart';
import '../asmr/asmr_paper.dart';
import '../asmr/asmr_piece.dart';
import '../asmr/asmr_scrub.dart';
import '../asmr/asmr_straight_edge.dart';
import '../asmr/hologram_painter.dart';
import '../asmr/hologram_selection.dart';
import '../craftroom/attach.dart';
import '../craftroom/bench_paper.dart';
import '../craftroom/craft_bench_painter.dart';
import '../craftroom/craft_theme.dart';
import '../craftroom/room_crafts.dart';
import '../craftroom/scissors.dart';
import '../craftroom/selection_group.dart';
import '../craftroom/snap_panel.dart';
import '../craftroom/snap_rules.dart';
import '../craftroom/workview.dart';
import '../craftroom/workview_panel.dart';
import '../gridcraft/craft_collection.dart';
import '../gridcraft/craft_collection_painter.dart';
import '../gridcraft/edit.dart' show marqueePick;
import '../gridcraft/fold.dart';
import '../gridcraft/folded_model.dart';
import '../gridcraft/model_painter.dart';
import '../gridcraft/wrap_cut.dart' show FaceNeighbor, faceAdjacency;
import '../papercut/camera.dart';
import '../papercut/paper.dart';
import '../ui/craft_palette.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';

/// How much of the desk workview is still showing when the bench is dropped
/// on the way out, and the fly back to the room begins.
const double kBenchDropAt = 0.1;

/// The fly between the room and a craft, either way.
const Duration kCraftFlyDuration = Duration(milliseconds: 800);

/// How long the bench waits after the orbit, while the level loads.
const Duration kLevelLoadDelay = Duration(milliseconds: 750);

/// The desk workview's fade in once the level has loaded, and its fade out
/// on the way out.
const Duration kDeskFadeDuration = Duration(milliseconds: 380);

/// One turn around a finished craft, ending on the angle it was entered at.
const Duration kCraftSpinDuration = Duration(milliseconds: 1400);

/// Loads the craft the room just orbited into.
///
/// A placeholder wait until the level is read. The desk workview fades in
/// when this finishes.
Future<void> loadCraftLevel() => Future<void>.delayed(kLevelLoadDelay);

/// Scrap slots in the inventory, shared by every group of a craft.
const int kScrapSlots = 3;

/// The straight edge's width, in grid squares.
const double kStraightEdgeSquares = 3;

enum _Phase {
  room,
  flyingIn,
  loading,
  rising,
  bench,
  leaving,
  spinning,
  flyingOut,
}

enum _Tool { select, exacto, straight, scissors, folder, arrange }

enum _ModelTool { orbit, select }

enum _Drag {
  none,
  room,
  orbit,
  pan,
  marquee,
  cut,
  straight,
  scissors,
  fold,
  move,
  rotate,
  deskPan,
  edgeSlide,
  edgeTurn,
  island,
}

const double _kReticleBox = 24;
const double _kTapSlop = 8;
const Duration _kTapTime = Duration(milliseconds: 350);
const double _kOrbitPerPixel = 0.008;
const double _kMaxTilt = 85 * math.pi / 180;
const double _kModelTurn = -1.0;
const double _kModelTilt = 0.5;
const double _kFraming = 1.7;
const Offset _kKnifeLift = Offset(0, -56);
const double _kHandleLift = 30;
const double _kHandleRadius = 22;
const double _kHistoryPad = 32 * 1.5 - 8 - 16;
const int _kHistoryDepth = 40;
const double _kDeskSpan = 28;
const double _kStrokeSpacing = 0.1;
const double _kHoverFill = 0.55;
const Duration _kPreselectFade = Duration(milliseconds: 180);
const Duration _kOutlineFade = Duration(milliseconds: 250);
const Duration _kFlashFade = Duration(milliseconds: 600);
const Duration _kStraightEdgeFly = Duration(milliseconds: 450);
const Duration _kFoldHold = Duration(milliseconds: 750);
const double _kFoldHoldSlop = 12;
const double _kFoldBarHalf = 96;
const Duration _kFoldSettle = Duration(milliseconds: 280);
const double _kRoomSlop = 10;
const Duration _kThemeFade = Duration(milliseconds: 300);
const Duration _kStowFlight = Duration(milliseconds: 450);
const Duration _kNoteFade = Duration(milliseconds: 2400);
const double _kGroupChip = 40;

/// Room left at the bottom of the screen for the trash, and for the tool
/// carousel and hint.
const double _kTrashClear = 84;
const double _kToolsClear = 128;

final Vector3 _kUp = Vector3(0, 0, 1);

/// The craft room: a room of crafts that flies into one on a tap. The orbit
/// finishes first, the level loads, and then the bench fades in: the craft
/// and the crafting grid as two full-screen workviews, one over the other.
/// A double-tap on empty space switches which one is active. Paper cut out
/// exactly to a net island of the open selection folds onto the craft by
/// itself.
class CraftRoomView extends StatefulWidget {
  const CraftRoomView({
    super.key,
    this.collection,
    this.settings,
    this.snapSettings,
    this.workviewSettings,
  });

  /// The room. Null loads [kCraftRoomAsset].
  final CraftCollection? collection;

  /// Saved DevTools values. Null uses the file in the home directory.
  final AsmrDevSettings? settings;

  /// Saved snap rules. Null uses the file in the home directory.
  final SnapSettings? snapSettings;

  /// Saved look of the inactive workview. Null uses the file in the home
  /// directory.
  final WorkviewSettings? workviewSettings;

  @override
  State<CraftRoomView> createState() => _CraftRoomViewState();
}

class _Placed {
  const _Placed({
    required this.spot,
    required this.craft,
    required this.placed,
  });

  final CraftSpot spot;
  final RoomCraft craft;
  final FoldedModel placed;
}

class _Step {
  const _Step({
    required this.groups,
    required this.none,
    required this.open,
    required this.extra,
    required this.bound,
    required this.slots,
    required this.nextPaper,
  });

  final List<CraftGroup> groups;
  final CraftGroup none;
  final int? open;
  final List<HologramPick> extra;
  final List<AsmrPiece> bound;
  final List<BenchPaper?> slots;
  final int nextPaper;
}

/// One craft's bench, kept while the app is open so going back in finds it
/// as it was left.
class _Bench {
  _Bench(this.model) : adjacency = faceAdjacency(model);

  final FoldedModel model;
  final List<List<FaceNeighbor?>> adjacency;

  /// Saved groups, A to E. No face is in two of them.
  List<CraftGroup> groups = [];

  /// The null group: the desk while nothing is selected.
  CraftGroup none = CraftGroup.none;

  /// Letter of the open group, or null.
  int? open;

  /// Selected faces in no group: a new group to save, or faces to add to
  /// the open one. Their desk is empty until something is done on it.
  List<HologramPick> extra = const [];
  AsmrNet extraNet = AsmrNet.empty;
  List<AsmrPiece> bound = [];
  List<BenchPaper?> slots = List.filled(kScrapSlots, null);
  int nextPaper = 0;
  Offset deskMiddle = Offset.zero;
  double? deskScale;
  final List<_Step> undo = [];
  final List<_Step> redo = [];
}

class _HoloEdge {
  _HoloEdge(this.edge);

  final AsmrNetEdge edge;
}

class _Settle {
  _Settle(this.paper, this.from, this.to, {required this.preview});

  final String paper;
  final double from;
  final double to;

  /// The fold is the preview joint, not yet on the paper.
  final bool preview;
  double t = 0;
}

class _CraftRoomViewState extends State<CraftRoomView>
    with SingleTickerProviderStateMixin {
  final PapercutCamera _camera = PapercutCamera();
  final AsmrPaperTiles _tiles = AsmrPaperTiles();
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _slotKeys = [
    for (var i = 0; i < kScrapSlots; i++) GlobalKey(),
  ];
  final GlobalKey _trashKey = GlobalKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Size _size = Size.zero;
  double _clock = 0;

  late final AsmrDevSettings _settings = widget.settings ?? AsmrDevSettings();
  AsmrDevSettings? _ownedSettings;
  late final SnapSettings _snap = widget.snapSettings ?? SnapSettings();
  SnapSettings? _ownedSnap;
  late final WorkviewSettings _looks =
      widget.workviewSettings ?? WorkviewSettings();
  WorkviewSettings? _ownedLooks;
  bool _devToolsOpen = false;

  // Room ---------------------------------------------------------------------
  CraftCollection? _collection;
  final List<_Placed> _crafts = [];
  final Map<int, _Bench> _benches = {};
  final Set<int> _finished = {};
  bool _roomPosed = false;
  int? _hoverCraft;
  Offset? _roomGrab;

  _Phase _phase = _Phase.room;
  int? _entered;
  Matrix4? _craftTransform;
  CameraPose? _roomPose;
  double _flyT = 0;
  double _upT = 0;
  double _downT = 0;

  /// How much of the desk workview is showing when it starts to fade out. 1
  /// from the open bench, less when leaving while it is still fading in.
  double _leaveFrom = 1;

  /// The fall is a finished craft: after the desk is gone, spin back to the
  /// entry angle, then fly home. Back skips the spin.
  bool _spinAfter = false;
  double _spinT = 0;
  int _loadToken = 0;
  double _benchHalf = 1;

  // Bench ----------------------------------------------------------------------
  final HologramSelection _selection = HologramSelection();

  /// Face tints on the model ease from [_tintFrom] to [_tintTo]. The blueprint
  /// takes its theme at once.
  Map<int, Color> _tintFrom = {};
  Map<int, Color> _tintTo = {};
  double _tintT = 1;

  /// A short message over the desk, fading out.
  String _note = '';
  double _noteShown = 0;
  final Map<String, _HoloEdge> _holoEdges = {};
  final Map<int, double> _faceFill = {};
  final List<AsmrFlight> _flights = [];
  final List<_StowFlight> _stowFlights = [];
  Map<int, double> _coverage = {};
  bool _complete = false;
  double _completeShown = 0;

  /// The workview that takes input and is drawn on top.
  Workview _active = Workview.model;

  /// How active each workview looks: 1 at full strength, 0 at the inactive
  /// look. Eases toward [_active].
  final Map<Workview, double> _activeShown = {
    Workview.model: 1,
    Workview.desk: 0,
  };
  final WorkviewDoubleTap _doubleTap = WorkviewDoubleTap();

  /// A second finger came down during the gesture, so it is no tap.
  bool _manyFingers = false;
  Offset _deskOrigin = Offset.zero;
  double _deskScale = 10;

  _Tool _tool = _Tool.select;
  _ModelTool _modelTool = _ModelTool.orbit;
  final Set<String> _selectedIds = {};
  double _selectedOutline = 0;
  final Map<String, double> _flash = {};
  int? _bin;

  final Map<int, Offset> _pointers = {};
  PointerDeviceKind _lastKind = PointerDeviceKind.touch;
  Offset? _hover;
  int? _hoverFace;
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  Duration _dragStartTime = Duration.zero;
  bool _dragMoved = false;
  double _lastSpan = 0;
  Offset _lastFocal = Offset.zero;
  Offset _deskStart = Offset.zero;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;

  /// The open group and extra faces before the marquee, to give back.
  ({int? open, List<HologramPick> extra})? _marqueeHome;
  _Step? _gestureBefore;
  final Map<int, AsmrScrub> _scrubs = {};
  final AsmrScrub _focalScrub = AsmrScrub();

  /// Papers in hand and where they were picked up.
  Map<String, BenchPaper> _moveFrom = {};
  String? _movePrimary;
  double _rotateFrom = 0;
  Offset _rotatePivot = Offset.zero;

  /// Exacto.
  List<Offset>? _rawStroke;
  List<Offset>? _stroke;
  Offset? _tipDesk;
  Offset? _finger;
  int? _knifeSide;

  /// Straight cut and scissors, on the desk.
  Offset? _segmentStart;
  Offset? _segmentEnd;
  Offset? _snapShown;

  /// Folder.
  String? _foldPaper;
  FolderGuide? _foldGuide;
  (Offset, Offset)? _foldLine;
  Offset? _foldFlap;
  (Offset, Offset)? _unfoldLine;
  double _holdSince = 0;
  bool _folding = false;
  Offset _foldAnchor = Offset.zero;
  Offset? _foldAxis;
  double _foldSigned = 0;
  FoldJoint? _previewJoint;
  _Settle? _settle;

  /// Arrange.
  int? _island;
  AsmrNet? _islandFrom;

  /// Straight edge, on the desk.
  Offset? _edgeAnchor;
  double _edgeAngle = 0;
  bool _edgeOn = false;
  double _edgeShown = 0;
  int _edgeFlySide = 1;
  Offset _edgeDragAnchor = Offset.zero;
  double _edgeDragAngle = 0;
  double _edgeTurnFrom = 0;
  double _edgeTurnBase = 0;
  Offset _edgePivot = Offset.zero;
  Offset? _edgeHome;
  double _edgeHomeAngle = 0;

  @override
  void initState() {
    super.initState();
    if (widget.settings == null) _ownedSettings = _settings;
    if (widget.snapSettings == null) _ownedSnap = _snap;
    if (widget.workviewSettings == null) _ownedLooks = _looks;
    _settings.addListener(_onSettings);
    _snap.addListener(_onSettings);
    _looks.addListener(_onSettings);
    _settings.load();
    _snap.load();
    _looks.load();
    _camera.setFocal(PapercutCamera.perspectiveFocalMm);
    _ticker = createTicker(_onTick)..start();
    final collection = widget.collection;
    if (collection != null) {
      _setCollection(collection);
    } else {
      _loadCollection();
    }
  }

  @override
  void dispose() {
    _loadToken++;
    _settings.removeListener(_onSettings);
    _snap.removeListener(_onSettings);
    _looks.removeListener(_onSettings);
    _ownedSettings?.dispose();
    _ownedSnap?.dispose();
    _ownedLooks?.dispose();
    _ticker.dispose();
    _camera.dispose();
    _tiles.dispose();
    super.dispose();
  }

  void _onSettings() {
    if (mounted) setState(() {});
  }

  SnapRules get _rules => _snap.rules;

  // -------------------------------------------------------------------------
  // Room
  // -------------------------------------------------------------------------

  Future<void> _loadCollection() async {
    final text = await rootBundle.loadString(kCraftRoomAsset);
    if (!mounted) return;
    setState(() {
      _setCollection(
        CraftCollection.fromJson(jsonDecode(text) as Map<String, dynamic>),
      );
    });
  }

  /// Stands each craft the room knows in [collection].
  void _setCollection(CraftCollection collection) {
    _collection = collection;
    _crafts.clear();
    for (final spot in collection.crafts) {
      final craft = roomCraft(spot.puzzleId);
      if (craft == null) continue;
      _crafts.add(
        _Placed(
          spot: spot,
          craft: craft,
          placed: placedCraft(craft.model, spot),
        ),
      );
    }
    _roomPosed = false;
    _poseRoom();
  }

  void _poseRoom() {
    final collection = _collection;
    if (collection == null || _roomPosed || _phase != _Phase.room) return;
    if (_size.width < 2 || _size.height < 2) return;
    _roomPosed = true;
    final camera = collection.camera;
    final half =
        camera.halfHeight ??
        _camera
            .frameSphere(
              camera.at,
              collection.groundBounds.size.longestSide / 2,
              _size,
            )
            .halfHeight;
    _camera.beginFly(_poseAlong(camera.at, camera.direction, half));
    _camera.setFly(1);
    _refreshHover();
  }

  CameraPose _poseAlong(Vector3 target, Vector3 direction, double halfHeight) =>
      CameraPose(
        lookAt: Offset(target.x, target.y),
        lookAtZ: target.z,
        halfHeight: halfHeight,
      ).withAngles(_camera.anglesAlong(direction, up: _kUp));

  Vector3 _turntableDirection(double turn, double tilt) => Vector3(
    math.cos(tilt) * math.cos(turn),
    math.cos(tilt) * math.sin(turn),
    math.sin(tilt),
  );

  bool get _inRoomView =>
      _phase == _Phase.room ||
      _phase == _Phase.flyingIn ||
      _phase == _Phase.flyingOut;

  bool get _inBench => _phase == _Phase.bench;

  /// 1 with the room shown, toward 0 while flying into a craft.
  double get _roomShown => switch (_phase) {
    _Phase.room => 1,
    _Phase.flyingIn => 1 - Curves.easeInOutCubic.transform(_flyT),
    _Phase.flyingOut => Curves.easeInOutCubic.transform(_flyT),
    _Phase.loading ||
    _Phase.rising ||
    _Phase.bench ||
    _Phase.leaving ||
    _Phase.spinning => 0,
  };

  int? _craftAt(Offset screen) {
    final collection = _collection;
    if (collection == null || _viewport.height < 2) return null;
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return null;
    return pickCraft(
      [for (final craft in _crafts) craft.placed],
      collection.surfaces,
      ray.origin,
      ray.direction,
    )?.craft;
  }

  /// Flies to the craft's opening view, carried into room space, framed for
  /// the full screen the 3D workview fills.
  void _enterCraft(int index) {
    if (_phase != _Phase.room) return;
    final craft = _crafts[index];
    final raw = craft.craft.model;
    final by = craftPlacement(raw, craft.spot);
    _benchHalf = _camera
        .frameSphere(raw.center, raw.radius * _kFraming, _viewport)
        .halfHeight;
    final view = carryView(
      by,
      raw.center,
      _turntableDirection(_kModelTurn, _kModelTilt),
    );
    _roomPose = _camera.pose;
    _craftTransform = by;
    _camera.beginFly(_poseAlong(view.target, view.direction, _benchHalf));
    _benches.putIfAbsent(index, () => _Bench(raw));
    _entered = index;
    _phase = _Phase.flyingIn;
    _flyT = 0;
    _hoverCraft = null;
    HapticFeedback.selectionClick();
  }

  /// Swaps room space for the craft's own at the same image, then waits for
  /// the level to load before the desk workview fades in.
  void _arrive() {
    final bench = _benches[_entered];
    if (bench == null) return;
    _phase = _Phase.loading;
    _upT = 0;
    _active = Workview.model;
    _activeShown[Workview.model] = 1;
    _activeShown[Workview.desk] = 0;
    _doubleTap.reset();
    _camera.beginFly(
      _poseAlong(
        bench.model.center,
        _turntableDirection(_kModelTurn, _kModelTilt),
        _benchHalf,
      ),
    );
    _camera.setFly(1);
    _deskScale = bench.deskScale ?? _size.shortestSide / _kDeskSpan;
    _deskOrigin = _deskCenter - bench.deskMiddle * _deskScale;
    _holoEdges.clear();
    _syncSelection();
    _aimFaceTints(instant: true);
    _faceFill.clear();
    _selectedIds.clear();
    _flash.clear();
    _flights.clear();
    _tool = _Tool.select;
    _modelTool = _ModelTool.orbit;
    _refreshCoverage();
    _refreshHover();
    final token = ++_loadToken;
    loadCraftLevel().then((_) {
      if (!mounted || token != _loadToken || _phase != _Phase.loading) return;
      setState(() {
        _phase = _Phase.rising;
        _upT = 0;
      });
    });
  }

  /// Back to the room: the 3D workview becomes active, the desk fades out,
  /// the bench is dropped just before it is gone, and the view flies back to
  /// where it entered. Leaving while the level is still loading skips the
  /// fade, since the desk is not showing yet.
  void _leave() {
    if (_phase == _Phase.loading) {
      _loadToken++;
      _leaveFrom = 0;
      _dropBench();
      return;
    }
    if (_phase == _Phase.rising) {
      _leaveFrom = Curves.easeIn.transform(_upT);
    } else if (_phase == _Phase.bench) {
      _leaveFrom = 1;
    } else {
      return;
    }
    _cancelGesture(quiet: true);
    _active = Workview.model;
    _spinAfter = false;
    _phase = _Phase.leaving;
    _downT = 0;
  }

  /// A finished craft: the 3D workview becomes active and the desk fades
  /// out, the view spins once around the model back to the angle it had on
  /// the way in, then flies back to the room.
  void _finishCraft() {
    if (_phase != _Phase.bench && _phase != _Phase.rising) return;
    _cancelGesture(quiet: true);
    _active = Workview.model;
    _leaveFrom = _phase == _Phase.bench ? 1 : Curves.easeIn.transform(_upT);
    _spinAfter = true;
    _phase = _Phase.leaving;
    _downT = 0;
  }

  /// One full turn that lands on the craft's entry angle and framing, the
  /// pose the fly-in ended on before the desk faded in.
  void _beginSpin() {
    final bench = _benches[_entered];
    if (bench == null) return;
    for (final flight in _stowFlights) {
      bench.slots[flight.slot] = flight.paper;
    }
    _stowFlights.clear();
    final entry = _camera.anglesAlong(
      _turntableDirection(_kModelTurn, _kModelTilt),
      up: _kUp,
    );
    var turn = entry.azimuth - _camera.azimuth;
    final tau = math.pi * 2;
    turn %= tau;
    if (turn < 0) turn += tau;
    if (turn < 1e-3) turn = tau;
    final center = bench.model.center;
    _camera.beginFly(
      CameraPose(
        lookAt: Offset(center.x, center.y),
        lookAtZ: center.z,
        halfHeight: _benchHalf,
        azimuth: _camera.azimuth + turn,
        elevation: entry.elevation,
        roll: entry.roll,
      ),
    );
    _spinT = 0;
    _phase = _Phase.spinning;
  }

  void _dropBench() {
    final bench = _benches[_entered];
    final by = _craftTransform;
    final back = _roomPose;
    if (bench == null || by == null || back == null) return;
    for (final flight in _flights) {
      bench.bound.add(flight.piece);
    }
    _flights.clear();
    for (final flight in _stowFlights) {
      bench.slots[flight.slot] = flight.paper;
    }
    _stowFlights.clear();
    bench.deskMiddle = _toDesk(_deskCenter);
    bench.deskScale = _deskScale;
    final view = carryView(by, _camera.target, _camera.viewDirection);
    final up = by.getRotation().transformed(_camera.camera.up).normalized();
    _camera.beginFly(
      CameraPose(
        lookAt: Offset(view.target.x, view.target.y),
        lookAtZ: view.target.z,
        halfHeight: _camera.framedHalfHeightMm,
      ).withAngles(_camera.anglesAlong(view.direction, up: up)),
    );
    _camera.setFly(1);
    _camera.beginFly(back, turn: true);
    _phase = _Phase.flyingOut;
    _flyT = 0;
  }

  void _panRoom(Offset screen) {
    final collection = _collection;
    final grab = _roomGrab;
    if (collection == null || grab == null) return;
    final at = _camera.planePoint(screen, _viewport);
    if (at == null) return;
    final bounds = collection.groundBounds;
    final from = _camera.lookAt;
    final next = from + (grab - at);
    final clamped = Offset(
      next.dx.clamp(bounds.left, bounds.right),
      next.dy.clamp(bounds.top, bounds.bottom),
    );
    _camera.shiftTarget(Vector3(clamped.dx - from.dx, clamped.dy - from.dy, 0));
  }

  // -------------------------------------------------------------------------
  // Layout and camera
  // -------------------------------------------------------------------------

  /// How present the desk workview is: 0 with no bench on screen, 1 once it
  /// has faded in. Its opacity is multiplied by this.
  double get _benchShown => switch (_phase) {
    _Phase.room || _Phase.flyingIn || _Phase.loading || _Phase.spinning => 0,
    _Phase.rising => Curves.easeIn.transform(_upT),
    _Phase.bench => 1,
    _Phase.leaving ||
    _Phase.flyingOut => _leaveFrom * (1 - Curves.easeIn.transform(_downT)),
  };

  Size get _viewport =>
      Size(math.max(1, _size.width), math.max(1, _size.height));

  Offset get _deskCenter => _size.center(Offset.zero);

  Offset get _modelCenter => _size.center(Offset.zero);

  bool get _deskShown =>
      _phase == _Phase.rising ||
      _phase == _Phase.bench ||
      _phase == _Phase.leaving;

  bool get _modelActive => _active == Workview.model;

  bool get _deskActive => _active == Workview.desk;

  void _onLayout(Size size) {
    if (size == _size) return;
    final before = _deskCenter;
    _size = size;
    if (_deskShown) _deskOrigin += _deskCenter - before;
    _poseRoom();
  }

  /// Makes [view] the workview that takes input. It eases to full strength
  /// over the one it replaces.
  void _setActive(Workview view) {
    if (_active == view) return;
    _cancelGesture(quiet: true);
    _active = view;
    _marqueeStart = null;
    _marqueeEnd = null;
    _tipDesk = null;
    _finger = null;
    _doubleTap.reset();
    _refreshHover();
    HapticFeedback.selectionClick();
  }

  /// Whether [screen] is empty space in the active workview: no face on the
  /// model, or nothing on the desk to act on.
  bool _emptyAt(Offset screen) {
    if (_modelActive) {
      final aim = _aimFace(screen);
      return aim.face == null && !aim.blocked;
    }
    final desk = _toDesk(screen);
    if (_paperAt(desk) != null || _onHandle(screen)) return false;
    final edge = _liveEdge;
    final handle = _edgeHandle;
    if (edge != null && edge.contains(screen)) return false;
    if (handle != null && (screen - handle).distance <= _kHandleRadius) {
      return false;
    }
    return netFaceAt(_net, desk) == null;
  }

  void _turntable(double dTurn, double dTilt) {
    final n = _camera.viewDirection;
    final turn = math.atan2(n.y, n.x) + dTurn;
    final tilt = (math.asin(n.z.clamp(-1.0, 1.0)) + dTilt).clamp(
      -_kMaxTilt,
      _kMaxTilt,
    );
    _camera.orbitTo(_turntableDirection(turn, tilt), up: _kUp);
  }

  bool get _aimsWithCursor =>
      _lastKind == PointerDeviceKind.mouse ||
      _lastKind == PointerDeviceKind.trackpad;

  /// Where the 3D view is aimed: the cursor, else the screen's middle on
  /// touch. Null while the desk workview is active.
  Offset? get _aim {
    if (_inBench && !_modelActive) return null;
    if (!_aimsWithCursor) return _modelCenter;
    return _hover;
  }

  /// The face under the aim in 3D. With the desk active, the face whose net
  /// face is under the cursor or finger, so the model lights it from behind.
  void _refreshHover() {
    final aim = _aim;
    if (_inBench) {
      final touch =
          _hover ?? (_pointers.length == 1 ? _pointers.values.first : null);
      _hoverFace = _modelActive
          ? (aim == null ? null : _faceAt(aim))
          : (touch == null ? null : netFaceAt(_net, _toDesk(touch)));
      _hoverCraft = null;
      return;
    }
    _hoverFace = null;
    _hoverCraft = _phase == _Phase.room && aim != null ? _craftAt(aim) : null;
  }

  // -------------------------------------------------------------------------
  // Bench state
  // -------------------------------------------------------------------------

  _Bench get _bench => _benches[_entered]!;

  FoldedModel get _model => _bench.model;

  CraftGroup? _groupOf(int? letter) {
    if (letter == null) return null;
    for (final group in _bench.groups) {
      if (group.letter == letter) return group;
    }
    return null;
  }

  /// The selected faces in no group, as a group not saved yet.
  CraftGroup get _pending =>
      CraftGroup(picks: _bench.extra, net: _bench.extraNet);

  /// The group whose desk is showing: the open one, a selection not saved
  /// yet with an empty desk, or the null group while nothing is selected.
  CraftGroup get _group {
    final open = _groupOf(_bench.open);
    if (open != null) return open;
    if (_bench.extra.isNotEmpty) return _pending;
    return _bench.none;
  }

  /// Whether a desk action would first make a group, or add to one.
  bool get _hasPending => _bench.extra.isNotEmpty;

  void _setGroup(CraftGroup group) {
    if (!group.saved) {
      if (group.picks.isEmpty) _bench.none = group;
      return;
    }
    final groups = _bench.groups;
    final i = groups.indexWhere((g) => g.letter == group.letter);
    if (i >= 0) groups[i] = group;
  }

  List<BenchPaper> get _papers => _group.papers;

  set _papers(List<BenchPaper> papers) =>
      _setGroup(_group.copyWith(papers: papers));

  /// The net on the desk. With faces to add, the open group's net shows
  /// them where adding would put them.
  AsmrNet get _net {
    final open = _groupOf(_bench.open);
    if (open != null && _hasPending) return mergeGroups(open, _pending).net;
    return _group.net;
  }

  /// The theme of the blueprint on the desk: the open group, the group a new
  /// selection would become, or the plain desk. The background stays plain.
  CraftTheme get _targetTheme {
    final open = _groupOf(_bench.open);
    if (open != null) return open.theme;
    if (_hasPending) {
      final letter = nextLetter(_bench.groups);
      return letter == null ? kCraftNoneTheme : craftGroupTheme(letter);
    }
    return kCraftNoneTheme;
  }

  /// The blueprint's theme. It changes with the group in one step.
  CraftTheme get _theme => _targetTheme;

  /// Each group's tint over its faces in 3D: stronger for the open group,
  /// and for the group under the aim.
  Map<int, Color> get _faceTints {
    final hovered = _owners[_hoverFace]?.letter;
    return {
      for (final group in _bench.groups)
        for (final face in group.faces)
          face: group.letter == _bench.open || group.letter == hovered
              ? group.theme.openFaceTint
              : group.theme.faceTint,
    };
  }

  /// The face tints actually drawn, easing toward [_faceTints].
  Map<int, Color> get _shownFaceTints {
    final t = Curves.easeInOut.transform(_tintT.clamp(0.0, 1.0));
    final faces = {..._tintFrom.keys, ..._tintTo.keys};
    final shown = <int, Color>{};
    for (final face in faces) {
      final color = Color.lerp(
        _tintFrom[face] ?? const Color(0x00000000),
        _tintTo[face] ?? const Color(0x00000000),
        t,
      )!;
      if (color.a > 0.001) shown[face] = color;
    }
    return shown;
  }

  bool _sameTints(Map<int, Color> a, Map<int, Color> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }

  /// Points the model's face tints at what the groups call for now. [instant]
  /// shows that at once, as when the craft is first opened.
  void _aimFaceTints({bool instant = false}) {
    final next = _faceTints;
    if (instant) {
      _tintFrom = Map.of(next);
      _tintTo = Map.of(next);
      _tintT = 1;
      return;
    }
    if (_sameTints(_tintTo, next)) return;
    _tintFrom = _shownFaceTints;
    _tintTo = Map.of(next);
    _tintT = 0;
  }

  /// Group that owns each face.
  Map<int, CraftGroup> get _owners => {
    for (final group in _bench.groups)
      for (final face in group.faces) face: group,
  };

  BenchPaper? _paper(String id) {
    for (final paper in _papers) {
      if (paper.id == id) return paper;
    }
    return null;
  }

  void _replacePaper(BenchPaper paper) {
    _papers = [
      for (final p in _papers)
        if (p.id == paper.id) paper else p,
    ];
  }

  String _nextPaperId() => 'paper-${_bench.nextPaper++}';

  /// Drops crafted faces out of the selection not saved yet. A saved group
  /// keeps them, so its desk stays.
  void _releaseCraftedSelection() {
    final crafted = _craftedFaces;
    final extra = [
      for (final pick in _bench.extra)
        if (!crafted.contains(pick.face)) pick,
    ];
    if (extra.length == _bench.extra.length) return;
    _bench.extra = extra;
    _bench.extraNet = gridNet(_model, _bench.adjacency, extra);
    _syncSelection();
  }

  /// Selects [faces] on the model. A face of a group brings its whole group;
  /// faces of other groups are let go, so no face is in two; faces in no
  /// group become the selection to save or to add. The desk switches to the
  /// group that is showing. Returns whether anything changed.
  bool _selectFaces(Set<int> faces, {int? prefer}) {
    final bench = _bench;
    final resolved = resolveSelection(faces, bench.groups, prefer: prefer);
    final extra = hologramPicks(
      resolved.free,
      bench.adjacency,
      prefer: resolved.free.contains(prefer) ? prefer : null,
    );
    final sameExtra =
        extra.length == bench.extra.length &&
        {
          for (final p in extra) p.face,
        }.containsAll({for (final p in bench.extra) p.face});
    if (resolved.open == bench.open && sameExtra) return false;
    bench.open = resolved.open;
    bench.extra = extra;
    bench.extraNet = gridNet(_model, bench.adjacency, extra);
    if (_tool == _Tool.arrange && (_hasPending || bench.open == null)) {
      _tool = _Tool.select;
    }
    _syncSelection();
    return true;
  }

  /// Shows the open group's faces and the extra faces as selected, and the
  /// desk's net to match.
  void _syncSelection() {
    _selection.replace([...?_groupOf(_bench.open)?.picks, ..._bench.extra]);
    _selectedIds.removeWhere((id) => _paper(id) == null);
    _rebuildNet();
  }

  /// Makes the extra faces a group before something is done on their desk:
  /// a new group when none is open, else added to the open one. Returns
  /// false when a new group is needed and A to E are all taken.
  bool _claim() {
    if (!_hasPending) return true;
    final bench = _bench;
    final open = _groupOf(bench.open);
    if (open == null && nextLetter(bench.groups) == null) {
      _showNote('Groups A to E are all used. Merge or delete one first.');
      return false;
    }
    _pushUndo();
    if (open != null) {
      _setGroup(mergeGroups(open, _pending));
    } else {
      final letter = nextLetter(bench.groups)!;
      bench.groups.add(
        CraftGroup(letter: letter, picks: bench.extra, net: bench.extraNet),
      );
      bench.open = letter;
    }
    bench.extra = const [];
    bench.extraNet = AsmrNet.empty;
    _syncSelection();
    HapticFeedback.mediumImpact();
    return true;
  }

  void _showNote(String text) {
    _note = text;
    _noteShown = 1;
  }

  void _rebuildNet() {
    _holoEdges
      ..clear()
      ..addEntries([
        for (final edge in _net.edges) MapEntry(edge.key, _HoloEdge(edge)),
      ]);
  }

  List<AsmrPiece> get _onModel => [
    ..._bench.bound,
    for (final flight in _flights) flight.piece,
  ];

  void _refreshCoverage() {
    _coverage = faceCoverage(_model, _bench.bound);
    final done =
        _coverage.length == _model.faces.length &&
        _coverage.values.every((c) => c >= kAsmrFilled);
    if (done && !_complete) {
      HapticFeedback.heavyImpact();
      _complete = true;
      _finishCraft();
    } else {
      _complete = done;
    }
    _releaseCraftedSelection();
    final entered = _entered;
    if (entered != null) {
      if (done) {
        _finished.add(entered);
      } else {
        _finished.remove(entered);
      }
    }
  }

  // -------------------------------------------------------------------------
  // History
  // -------------------------------------------------------------------------

  _Step _capture() => _Step(
    groups: List.of(_bench.groups),
    none: _bench.none,
    open: _bench.open,
    extra: _bench.extra,
    bound: _onModel,
    slots: List.of(_bench.slots),
    nextPaper: _bench.nextPaper,
  );

  void _pushUndo() {
    final bench = _bench;
    bench.undo.add(_capture());
    if (bench.undo.length > _kHistoryDepth) bench.undo.removeAt(0);
    bench.redo.clear();
  }

  void _commitGesture() {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before == null) return;
    final now = _capture();
    if (_sameStep(before, now)) return;
    _bench.undo.add(before);
    if (_bench.undo.length > _kHistoryDepth) _bench.undo.removeAt(0);
    _bench.redo.clear();
  }

  bool _sameStep(_Step a, _Step b) {
    if (a.open != b.open || a.nextPaper != b.nextPaper) return false;
    if (!identical(a.none, b.none) || !identical(a.extra, b.extra)) {
      return false;
    }
    if (a.groups.length != b.groups.length) return false;
    for (var i = 0; i < a.groups.length; i++) {
      if (!identical(a.groups[i], b.groups[i])) return false;
    }
    if (a.bound.length != b.bound.length) return false;
    for (var i = 0; i < a.slots.length; i++) {
      if (!identical(a.slots[i], b.slots[i])) return false;
    }
    return true;
  }

  void _restore(_Step step) {
    final bench = _bench;
    bench.groups = List.of(step.groups);
    bench.none = step.none;
    bench.open = step.open;
    bench.extra = step.extra;
    bench.extraNet = gridNet(_model, bench.adjacency, step.extra);
    bench.bound = List.of(step.bound);
    bench.slots = List.of(step.slots);
    bench.nextPaper = step.nextPaper;
    _flights.clear();
    _stowFlights.clear();
    _syncSelection();
    _flash.clear();
    _cancelGesture(quiet: true);
    _refreshCoverage();
  }

  void _undo() {
    final bench = _bench;
    if (bench.undo.isEmpty) return;
    setState(() {
      bench.redo.add(_capture());
      _restore(bench.undo.removeLast());
    });
  }

  void _redo() {
    final bench = _bench;
    if (bench.redo.isEmpty) return;
    setState(() {
      bench.undo.add(_capture());
      _restore(bench.redo.removeLast());
    });
  }

  // -------------------------------------------------------------------------
  // Animation
  // -------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _clock += dt;
    var changed = false;

    double step(double value, double target, Duration over) {
      if (value == target) return value;
      final delta = dt * 1e6 / over.inMicroseconds;
      changed = true;
      return value < target
          ? math.min(target, value + delta)
          : math.max(target, value - delta);
    }

    final fly = kCraftFlyDuration.inMicroseconds / 1e6;
    switch (_phase) {
      case _Phase.room:
        break;
      case _Phase.flyingIn:
        changed = true;
        _flyT = math.min(1, _flyT + dt / fly);
        _camera.setFly(Curves.easeInOutCubic.transform(_flyT));
        if (_flyT >= 1) _arrive();
      case _Phase.loading:
        break;
      case _Phase.rising:
        changed = true;
        _upT = math.min(
          1,
          _upT + dt / (kDeskFadeDuration.inMicroseconds / 1e6),
        );
        if (_upT >= 1) _phase = _Phase.bench;
      case _Phase.bench:
        break;
      case _Phase.leaving:
        changed = true;
        _downT = math.min(
          1,
          _downT + dt / (kDeskFadeDuration.inMicroseconds / 1e6),
        );
        if (_spinAfter) {
          if (_downT >= 1) _beginSpin();
        } else if (_benchShown <= kBenchDropAt) {
          _dropBench();
        }
      case _Phase.spinning:
        changed = true;
        _spinT = math.min(
          1,
          _spinT + dt / (kCraftSpinDuration.inMicroseconds / 1e6),
        );
        _camera.setFly(Curves.easeInOutCubic.transform(_spinT));
        if (_spinT >= 1) _dropBench();
      case _Phase.flyingOut:
        changed = true;
        _downT = math.min(
          1,
          _downT + dt / (kDeskFadeDuration.inMicroseconds / 1e6),
        );
        _flyT = math.min(1, _flyT + dt / fly);
        _camera.setFly(Curves.easeInOutCubic.transform(_flyT));
        if (_flyT >= 1 && _downT >= 1) {
          _phase = _Phase.room;
          _entered = null;
          _craftTransform = null;
          _refreshHover();
        }
    }
    for (final view in Workview.values) {
      _activeShown[view] = step(
        _activeShown[view]!,
        view == _active ? 1 : 0,
        _looks.switchDuration,
      );
    }

    if (_deskShown) {
      final model = _model;
      final owners = _owners;
      final extra = {for (final pick in _bench.extra) pick.face};
      for (var f = 0; f < model.faces.length; f++) {
        final target = extra.contains(f)
            ? 1.0
            : f == _hoverFace && !owners.containsKey(f)
            ? _kHoverFill
            : 0.0;
        _faceFill[f] = step(_faceFill[f] ?? 0, target, _kPreselectFade);
      }
      _aimFaceTints();
      _tintT = step(_tintT, 1, _kThemeFade);
      _noteShown = step(_noteShown, 0, _kNoteFade);
      _selectedOutline = step(
        _selectedOutline,
        _selectedIds.isEmpty ? 0 : 1,
        _kOutlineFade,
      );
      for (final id in _flash.keys.toList()) {
        final value = step(_flash[id]!, 0, _kFlashFade);
        if (value <= 0) {
          _flash.remove(id);
        } else {
          _flash[id] = value;
        }
      }
      _completeShown = step(
        _completeShown,
        _complete ? 1 : 0,
        const Duration(milliseconds: 800),
      );
      _edgeShown = step(_edgeShown, _edgeOn ? 1 : 0, _kStraightEdgeFly);

      if (_drag == _Drag.fold &&
          !_folding &&
          !_dragMoved &&
          _foldGuide != null &&
          _clock - _holdSince >= _kFoldHold.inMicroseconds / 1e6) {
        _enterFolding();
        changed = true;
      }
      final settle = _settle;
      if (settle != null) {
        changed = true;
        settle.t = math.min(
          1,
          settle.t + dt / (_kFoldSettle.inMicroseconds / 1e6),
        );
        if (settle.t >= 1) {
          _settle = null;
          if (settle.preview) _previewJoint = null;
          _foldPaper = null;
        }
      }

      if (_flights.isNotEmpty) {
        changed = true;
        var landed = false;
        _flights.removeWhere((flight) {
          if (!flight.advance(dt)) return false;
          _bench.bound.add(flight.piece);
          landed = true;
          return true;
        });
        if (landed) {
          HapticFeedback.lightImpact();
          _refreshCoverage();
        }
      }
      if (_stowFlights.isNotEmpty) {
        changed = true;
        _stowFlights.removeWhere((flight) {
          if (!flight.advance(dt)) return false;
          _bench.slots[flight.slot] = flight.paper;
          return true;
        });
      }
    }
    if (changed || _complete) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Desk
  // -------------------------------------------------------------------------

  Offset _toDesk(Offset screen) => (screen - _deskOrigin) / _deskScale;

  Offset _toScreen(Offset desk) => _deskOrigin + desk * _deskScale;

  void _zoomDesk(double factor, Offset focal) {
    final desk = _toDesk(focal);
    _deskScale = (_deskScale * factor).clamp(2.0, 120.0);
    _deskOrigin = focal - desk * _deskScale;
  }

  SnapContext get _snapContext => SnapContext(
    gridSpacing: kBenchGrid,
    paperRings: [for (final paper in _papers) ...paper.drawnRings],
    blueprintRings: [for (final face in _net.faces) face.ring],
    reach: math.max(0.2, 12 / _deskScale),
  );

  Offset _snapTo(SnapUser user, Offset desk) =>
      snapPoint(_rules, user, desk, _snapContext);

  BenchPaper? _paperAt(Offset desk) {
    for (final paper in _papers.reversed) {
      if (paper.contains(desk)) return paper;
    }
    return null;
  }

  BenchPaper? get _selected {
    if (_selectedIds.length != 1) return null;
    return _paper(_selectedIds.single);
  }

  Offset? _handleFor(BenchPaper paper) {
    final rings = paper.drawnRings;
    if (rings.isEmpty) return null;
    var top = double.infinity;
    var left = double.infinity;
    var right = -double.infinity;
    for (final ring in rings) {
      for (final p in ring) {
        final s = _toScreen(p);
        top = math.min(top, s.dy);
        left = math.min(left, s.dx);
        right = math.max(right, s.dx);
      }
    }
    return Offset((left + right) / 2, top - _kHandleLift);
  }

  /// A fresh white sheet in the middle of the desk, its corners on the grid.
  void _layPaper() {
    setState(() {
      _cancelGesture(quiet: true);
      if (!_claim()) return;
      _pushUndo();
      final middle = _toDesk(_deskCenter);
      final corner = snapToCraftGrid(
        middle - Offset(kBenchSheetSize.width / 2, kBenchSheetSize.height / 2),
        kBenchGrid,
      );
      final paper = BenchPaper.fresh(_nextPaperId(), corner);
      _papers = [..._papers, paper];
      _tool = _Tool.select;
      _selectedIds
        ..clear()
        ..add(paper.id);
      _flash[paper.id] = 0.6;
    });
  }

  /// A piece the cut freed that is not inside the blueprint is darkened a
  /// little. Each one draws its own amount, and keeps it.
  BenchPaper _shadeScrap(
    BenchPaper paper,
    Set<String> freed,
    AsmrNet net,
    math.Random random,
  ) {
    if (paper.shade > 0 || !freed.contains(paper.id) || net.isEmpty) {
      return paper;
    }
    if (insideBlueprint(paper, net)) return paper;
    return paper.copyWith(shade: 0.08 + random.nextDouble() * 0.1);
  }

  /// Takes the outcome of a cut. Paper the cut freed that is exactly a net
  /// island of the open selection leaves the desk and folds onto the model.
  void _applyCut(BenchCut cut) {
    _pushUndo();
    final open = _groupOf(_bench.open);
    final already = open != null && _groupCrafted(open);
    final net = _net;
    final sent = <String>{};
    if (!net.isEmpty) {
      for (final paper in cut.papers) {
        if (!cut.freed.contains(paper.id)) continue;
        if (matchedIsland(paper, net) == null) continue;
        final piece = boundPiece(paper, net);
        if (slicesOf(piece).isEmpty) continue;
        _flights.add(
          AsmrFlight(
            piece: piece,
            from: deskPaperToScreen(piece, _deskOrigin, _deskScale),
          ),
        );
        sent.add(paper.id);
      }
    }
    final random = math.Random();
    _papers = [
      for (final paper in cut.papers)
        if (!sent.contains(paper.id))
          _shadeScrap(paper, cut.freed, net, random),
    ];
    for (final id in cut.freed) {
      if (!sent.contains(id)) _flash[id] = 1;
    }
    _selectedIds.removeWhere((id) => _paper(id) == null);
    if (sent.isNotEmpty) {
      HapticFeedback.heavyImpact();
    } else if (cut.split) {
      HapticFeedback.mediumImpact();
    }
    if (!already && open != null && _groupCrafted(open)) _bankLeftovers();
  }

  /// Whether every face of [group] has paper on it in 3D, including a piece
  /// still flying on.
  bool _groupCrafted(CraftGroup group) {
    final faces = group.faces;
    if (faces.isEmpty) return false;
    final crafted = _craftedFaces;
    return faces.every(crafted.contains);
  }

  /// The open group's faces are all crafted. Leftover paper, largest first,
  /// flies into the empty scrap slots, and the desk returns to the null
  /// group at the same moment the icons appear.
  void _bankLeftovers() {
    final free = [
      for (var i = 0; i < kScrapSlots; i++)
        if (_bench.slots[i] == null &&
            _stowFlights.every((flight) => flight.slot != i))
          i,
    ];
    final leftovers = [..._papers]..sort((a, b) => b.area.compareTo(a.area));
    final taking = leftovers.take(free.length).toList();
    final from = {for (final paper in taking) paper.id: _paperScreen(paper)};
    if (taking.isNotEmpty) {
      final ids = {for (final paper in taking) paper.id};
      _papers = [
        for (final paper in _papers)
          if (!ids.contains(paper.id)) paper,
      ];
      for (var i = 0; i < taking.length; i++) {
        final paper = taking[i];
        _stowFlights.add(
          _StowFlight(
            paper: paper,
            slot: free[i],
            from: from[paper.id]!,
            to: _slotCenter(free[i]),
          ),
        );
      }
    }
    _bench.open = null;
    _bench.extra = const [];
    _bench.extraNet = AsmrNet.empty;
    _selectedIds.clear();
    if (_tool == _Tool.arrange) _tool = _Tool.select;
    _syncSelection();
  }

  Offset _paperScreen(BenchPaper paper) =>
      _deskOrigin + paper.deskCenter * _deskScale;

  /// Whether the empty scrap slots are showing, as drop targets.
  bool get _slotsOpen =>
      _stowFlights.isNotEmpty || _selectedIds.any((id) => _paper(id) != null);

  /// The scrap slots' column on the right: the lower half of the screen,
  /// above the trash. Group chips take the upper half.
  double get _slotsTop => _size.height / 2;

  double get _slotsBottom => math.max(_slotsTop, _size.height - _kTrashClear);

  /// Center of scrap slot [index] on the right of the desk, matching the
  /// column. A full slot keeps its place when the empty ones are hidden.
  Offset _slotCenter(int index) {
    const slot = 52.0;
    const gap = 8.0;
    final stack = kScrapSlots * slot + (kScrapSlots - 1) * gap;
    final height = math.max(stack, _slotsBottom - _slotsTop);
    final top = _slotsTop + (height - stack) / 2;
    return Offset(
      _size.width - 8 - slot / 2,
      top + index * (slot + gap) + slot / 2,
    );
  }

  void _cutAlong(List<Offset> deskStroke) {
    final cut = cutBench(_papers, deskStroke, nextId: _nextPaperId);
    if (cut != null) _applyCut(cut);
  }

  // -------------------------------------------------------------------------
  // Exacto
  // -------------------------------------------------------------------------

  Offset _knifeAt(Offset pointer) =>
      _aimsWithCursor ? pointer : pointer + _kKnifeLift;

  Offset _bladeAt(Offset pointer) {
    final tip = _knifeAt(pointer);
    final edge = _liveEdge;
    final side = _knifeSide;
    if (edge == null || side == null) return tip;
    return edge.hold(tip, side, snap: kStraightEdgeSnap);
  }

  List<Offset> _smoothed(List<Offset> raw) {
    final smooth = smoothToolCurve(raw, _settings.curveSmoothing);
    final edge = _liveEdge;
    final side = _knifeSide;
    if (edge == null || side == null) return smooth;
    return [for (final p in smooth) _toDesk(edge.hold(_toScreen(p), side))];
  }

  void _beginCut(Offset pointer) {
    _knifeSide = _liveEdge?.sideOf(_knifeAt(pointer));
    final tip = _snapTo(SnapUser.exacto, _toDesk(_bladeAt(pointer)));
    _tipDesk = tip;
    _finger = pointer;
    _rawStroke = [tip];
    _stroke = [tip];
  }

  void _extendCut(Offset pointer) {
    final raw = _rawStroke;
    if (raw == null) return;
    final tip = _snapTo(SnapUser.exacto, _toDesk(_bladeAt(pointer)));
    _tipDesk = tip;
    _finger = pointer;
    addStrokePoint(raw, tip, spacing: _kStrokeSpacing);
    _stroke = _smoothed(raw);
  }

  void _endCut() {
    final raw = _rawStroke;
    var stroke = raw == null ? null : _smoothed(raw);
    _dropStroke();
    if (stroke == null || stroke.length < 2) return;
    if (stroke.length > 10 &&
        (stroke.last - stroke.first).distance < 0.4 &&
        (stroke.last - stroke.first).distance > 1e-6) {
      stroke = [...stroke, stroke.first];
    }
    _cutAlong(stroke);
  }

  void _dropStroke() {
    _rawStroke = null;
    _stroke = null;
    _finger = null;
    _knifeSide = null;
    if (!_aimsWithCursor) _tipDesk = null;
  }

  // -------------------------------------------------------------------------
  // Straight cut and scissors
  // -------------------------------------------------------------------------

  /// Line parameters, 0 at [a] and 1 at [b], that the straight edge keeps a
  /// straight cut inside.
  (double, double) _straightLimits(Offset a, Offset b) {
    final edge = _liveEdge;
    if (edge == null) return (double.negativeInfinity, double.infinity);
    return edge.lineLimits(_toScreen(a), _toScreen(b));
  }

  List<(Offset, Offset)> get _cutPreview {
    final start = _segmentStart;
    final end = _segmentEnd;
    if (start == null || end == null) return const [];
    if (_drag == _Drag.scissors) {
      final snip = scissorCut(start, end - start);
      return snip == null ? const [] : [snip];
    }
    if ((end - start).distance < 1e-6) return const [];
    final (lo, hi) = _straightLimits(start, end);
    return straightThroughPreview(_papers, start, end, lo: lo, hi: hi);
  }

  void _endSegment() {
    final start = _segmentStart;
    final end = _segmentEnd;
    final straight = _drag == _Drag.straight;
    final cuts = _cutPreview;
    _segmentStart = null;
    _segmentEnd = null;
    _snapShown = null;
    if (!_dragMoved || start == null || end == null) return;
    if (straight) {
      final (lo, hi) = _straightLimits(start, end);
      final cut = cutStraight(
        _papers,
        start,
        end,
        lo: lo,
        hi: hi,
        nextId: _nextPaperId,
      );
      if (cut != null) _applyCut(cut);
      return;
    }
    if (cuts.isEmpty) return;
    final (a, b) = cuts.single;
    if ((b - a).distance < 1e-6) return;
    _cutAlong([a, b]);
  }

  // -------------------------------------------------------------------------
  // Folder
  // -------------------------------------------------------------------------

  void _aimFolder(Offset desk) {
    final aim = _snapTo(SnapUser.folder, desk);
    _snapShown = aim;
    _foldPaper = null;
    _foldGuide = null;
    _foldLine = null;
    _foldFlap = null;
    _unfoldLine = null;
    for (final paper in _papers.reversed) {
      final cue = benchUnfoldCue(paper, desk);
      if (cue != null) {
        _unfoldLine = cue;
        _foldPaper = paper.id;
        return;
      }
      final found = benchFolderGuide(paper, aim);
      if (found == null) continue;
      _foldPaper = paper.id;
      _foldGuide = found.guide;
      _foldLine = (found.a, found.b);
      _foldFlap = found.flap;
      return;
    }
  }

  /// Held long enough: the crease is set, and dragging across it bends the
  /// paper over.
  void _enterFolding() {
    final guide = _foldGuide;
    final paper = _foldPaper == null ? null : _paper(_foldPaper!);
    if (guide == null || paper == null) return;
    final normal = creaseLeftNormal(guide.line.$1, guide.line.$2);
    if (normal == null) return;
    final c = math.cos(paper.angle);
    final s = math.sin(paper.angle);
    _foldAxis = Offset(
      c * normal.dx - s * normal.dy,
      s * normal.dx + c * normal.dy,
    );
    _folding = true;
    _foldSigned = 0;
    _foldAnchor = _pointers.values.isEmpty
        ? _dragStart
        : _pointers.values.first;
    _unfoldLine = null;
    _previewJoint = FoldJoint(
      a: guide.line.$1,
      b: guide.line.$2,
      side: 1,
      facing: FoldFacing.toward,
      pieceIds: {guide.pieceId},
    );
    HapticFeedback.mediumImpact();
  }

  Offset? _flapFor(FolderGuide guide, double signed) {
    final normal = creaseLeftNormal(guide.line.$1, guide.line.$2);
    if (normal == null || signed.abs() < 1e-4) return null;
    return flapForPerpendicularDrag(
      drag: normal * signed.sign,
      creaseA: guide.line.$1,
      creaseB: guide.line.$2,
      origin: Offset.lerp(guide.line.$1, guide.line.$2, 0.5)!,
    );
  }

  void _bendFolder(Offset pointer) {
    final guide = _foldGuide;
    final axis = _foldAxis;
    final joint = _previewJoint;
    if (guide == null || axis == null || joint == null) return;
    final delta = pointer - _foldAnchor;
    _foldSigned = foldBarSigned(
      delta.dx * axis.dx + delta.dy * axis.dy,
      _kFoldBarHalf,
    );
    final flap = _flapFor(guide, _foldSigned);
    if (flap == null) return;
    final side = sideOfLine(flap, guide.line.$1, guide.line.$2);
    _previewJoint = FoldJoint(
      a: joint.a,
      b: joint.b,
      side: side,
      facing: joint.facing,
      pieceIds: joint.pieceIds,
    );
  }

  void _releaseFolder({required bool tap}) {
    final id = _foldPaper;
    final paper = id == null ? null : _paper(id);
    if (!_folding) {
      if (tap && paper != null && _unfoldLine != null) {
        final opened = unfoldBench(paper, _toDesk(_dragStart));
        if (opened != null) {
          _pushUndo();
          _replacePaper(opened);
          HapticFeedback.selectionClick();
        }
      }
      _clearFolder();
      return;
    }
    _folding = false;
    final guide = _foldGuide;
    final signed = _foldSigned;
    final from = foldPreviewBend(signed);
    if (guide == null || paper == null) {
      _clearFolder();
      return;
    }
    final flap = foldPreviewCommits(signed) ? _flapFor(guide, signed) : null;
    final folded = flap == null
        ? null
        : foldBench(
            paper,
            FolderGuide(
              line: guide.line,
              flap: flap,
              separation: guide.separation,
              pieceId: guide.pieceId,
            ),
          );
    if (folded == null) {
      _settle = _Settle(paper.id, from, 0, preview: true);
      _foldGuide = null;
      _foldLine = null;
      _foldFlap = null;
      return;
    }
    _pushUndo();
    _replacePaper(folded);
    _previewJoint = null;
    _settle = _Settle(paper.id, from, 1, preview: false);
    _foldGuide = null;
    _foldLine = null;
    _foldFlap = null;
    HapticFeedback.mediumImpact();
  }

  void _clearFolder() {
    _folding = false;
    _foldGuide = null;
    _foldLine = null;
    _foldFlap = null;
    _unfoldLine = null;
    _snapShown = null;
    if (_settle == null) {
      _foldPaper = null;
      _previewJoint = null;
    }
  }

  /// Papers as drawn, with the fold being previewed on its paper.
  List<BenchPaper> get _shownPapers {
    final joint = _previewJoint;
    final id = _foldPaper;
    if (joint == null || id == null) return _papers;
    return [
      for (final paper in _papers)
        if (paper.id == id)
          paper.copyWith(
            sheet: paper.sheet.copyWith(folds: [...paper.sheet.folds, joint]),
          )
        else
          paper,
    ];
  }

  BenchBend? get _bend {
    final settle = _settle;
    if (settle != null) {
      final paper = _paper(settle.paper);
      if (paper == null) return null;
      final count = paper.sheet.folds.length;
      final t = Curves.easeOut.transform(settle.t);
      return (
        paper: settle.paper,
        joint: settle.preview ? count : count - 1,
        t: settle.from + (settle.to - settle.from) * t,
      );
    }
    final id = _foldPaper;
    if (!_folding || id == null || _previewJoint == null) return null;
    final paper = _paper(id);
    if (paper == null) return null;
    return (
      paper: id,
      joint: paper.sheet.folds.length,
      t: foldPreviewBend(_foldSigned),
    );
  }

  // -------------------------------------------------------------------------
  // Straight edge
  // -------------------------------------------------------------------------

  AsmrStraightEdge? get _edge {
    final anchor = _edgeAnchor;
    if (anchor == null) return null;
    return AsmrStraightEdge(
      anchor: _toScreen(anchor),
      angle: _edgeAngle,
      thickness: kStraightEdgeSquares * kBenchGrid * _deskScale,
    );
  }

  AsmrStraightEdge? get _liveEdge => _edgeOn && _edgeShown >= 1 ? _edge : null;

  double get _edgeFly {
    final t = _edgeOn
        ? Curves.easeOutCubic.transform(_edgeShown)
        : Curves.easeInCubic.transform(_edgeShown);
    return (1 - t) *
        (_size.longestSide + kStraightEdgeSquares * _deskScale * 2) *
        _edgeFlySide;
  }

  Offset? get _edgeHandle => _edge?.rotateHandle(_deskCenter);

  /// [anchor] and [angle] as the snap rules hold the straight edge: turned
  /// to its step, and slid so an edge lies on a grid line.
  (Offset, double) _snappedEdge(Offset anchor, double angle) {
    final turned = snapAngle(_rules, SnapUser.straightEdge, angle);
    if (!_rules[SnapUser.straightEdge].allows(SnapTarget.craftGrid)) {
      return (anchor, turned);
    }
    final eighths = turned / (math.pi / 4);
    if ((eighths - eighths.roundToDouble()).abs() > 1e-6) {
      return (anchor, turned);
    }
    final diagonal = eighths.round().isOdd;
    final spacing = kBenchGrid * (diagonal ? 1 / math.sqrt2 : 1);
    final normal = Offset(-math.sin(turned), math.cos(turned));
    final half = kStraightEdgeSquares * kBenchGrid / 2;
    final top = anchor.dx * normal.dx + anchor.dy * normal.dy - half;
    final snapped = (top / spacing).roundToDouble() * spacing;
    return (anchor + normal * (snapped - top), turned);
  }

  void _placeEdge() {
    final (anchor, angle) = _snappedEdge(_edgeDragAnchor, _edgeDragAngle);
    _edgeAnchor = anchor;
    _edgeAngle = angle;
  }

  void _toggleEdge() {
    setState(() {
      if (_edgeOn) {
        _edgeOn = false;
        final edge = _edge;
        if (edge != null) {
          _edgeFlySide = edge.across(_deskCenter) <= 0 ? 1 : -1;
        }
        if (_drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn) {
          _drag = _Drag.none;
        }
      } else {
        _edgeOn = true;
        if (_edgeAnchor == null) {
          final (anchor, angle) = _snappedEdge(_toDesk(_deskCenter), 0);
          _edgeAnchor = anchor;
          _edgeAngle = angle;
        }
      }
    });
  }

  bool _grabEdge(Offset pointer) {
    final edge = _liveEdge;
    final anchor = _edgeAnchor;
    if (edge == null || anchor == null) return false;
    final handle = _edgeHandle;
    final onHandle =
        handle != null && (pointer - handle).distance <= _kHandleRadius;
    if (!onHandle && !edge.contains(pointer)) return false;
    _edgeHome = anchor;
    _edgeHomeAngle = _edgeAngle;
    _edgeDragAnchor = anchor;
    _edgeDragAngle = _edgeAngle;
    if (onHandle) {
      _drag = _Drag.edgeTurn;
      _edgePivot = edge.nearestOnMiddle(_deskCenter);
      _edgeTurnFrom = math.atan2(
        pointer.dy - _edgePivot.dy,
        pointer.dx - _edgePivot.dx,
      );
      _edgeTurnBase = _edgeAngle;
      return true;
    }
    _drag = _Drag.edgeSlide;
    return true;
  }

  // -------------------------------------------------------------------------
  // Model pane
  // -------------------------------------------------------------------------

  /// Faces with paper on them in 3D, including a piece still flying on.
  /// These are not selectable.
  Set<int> get _craftedFaces {
    final faces = <int>{
      for (final entry in _coverage.entries)
        if (entry.value >= kAsmrFilled) entry.key,
    };
    if (_flights.isEmpty) return faces;
    final flying = faceCoverage(_model, [
      for (final flight in _flights) flight.piece,
    ]);
    for (final entry in flying.entries) {
      if (entry.value >= kAsmrFilled) faces.add(entry.key);
    }
    return faces;
  }

  bool _crafted(int face) => _craftedFaces.contains(face);

  /// The selectable face under [screen]. [blocked] is true when the nearest
  /// face has paper on it, so a tap there changes nothing.
  ({int? face, bool blocked}) _aimFace(Offset screen) {
    if (_viewport.height < 2) return (face: null, blocked: false);
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return (face: null, blocked: false);
    final hit = pickFace(_model, ray.origin, ray.direction);
    if (hit == null) return (face: null, blocked: false);
    if (_crafted(hit.face)) return (face: null, blocked: true);
    return (face: hit.face, blocked: false);
  }

  int? _faceAt(Offset screen) => _aimFace(screen).face;

  List<Offset>? _screenRing(int face) {
    final ring = <Offset>[];
    for (final point in _model.faces[face].worldRing()) {
      final screen = _camera.camera.projectToScreen(point, _viewport);
      if (screen == null) return null;
      ring.add(screen);
    }
    return ring;
  }

  void _applyMarquee() {
    final start = _marqueeStart;
    final end = _marqueeEnd;
    if (start == null || end == null || (end - start).distance < _kTapSlop) {
      return;
    }
    final rect = Rect.fromPoints(start, end);
    final hits = marqueeFaces(
      [for (var i = 0; i < _model.faces.length; i++) _screenRing(i)],
      rect,
      marqueePick(start, end),
    )..removeWhere(_crafted);
    int? prefer;
    var best = double.infinity;
    for (final face in hits) {
      final ring = _screenRing(face);
      if (ring == null || ring.isEmpty) continue;
      var center = Offset.zero;
      for (final point in ring) {
        center += point;
      }
      center = center / ring.length.toDouble();
      final distance = (center - rect.center).distance;
      if (distance < best) {
        best = distance;
        prefer = face;
      }
    }
    _selectFaces(hits, prefer: prefer);
  }

  void _panView(Offset delta) {
    _camera.panInView(
      delta,
      _viewport,
      anchor: _model.center,
      limit: _model.radius * 3,
    );
    _refreshHover();
  }

  /// Where the Save or Add button sits: beside the selected faces on screen,
  /// while some of them are in no group.
  Offset? get _saveAt {
    if (!_inBench || !_hasPending) return null;
    var box = Rect.zero;
    var any = false;
    for (final face in _selection.faces) {
      final ring = _screenRing(face);
      if (ring == null) continue;
      for (final p in ring) {
        final point = Rect.fromLTWH(p.dx, p.dy, 0, 0);
        box = any ? box.expandToInclude(point) : point;
        any = true;
      }
    }
    if (!any) return null;
    final x = (box.right + 12).clamp(8.0, math.max(8.0, _size.width - 64));
    final y = box.top.clamp(8.0, math.max(8.0, _size.height - _kToolsClear));
    return Offset(x.toDouble(), y.toDouble());
  }

  // -------------------------------------------------------------------------
  // Groups
  // -------------------------------------------------------------------------

  /// Saves the extra faces as a new group, or adds them to the open one.
  void _saveGroup() {
    setState(() {
      _cancelGesture(quiet: true);
      _claim();
    });
  }

  void _openGroup(int letter) {
    final group = _groupOf(letter);
    if (group == null) return;
    setState(() {
      _cancelGesture(quiet: true);
      _selectFaces(group.faces);
    });
  }

  /// Every face in no group and not in [letter]'s, as a new selection.
  void _invertGroup(int letter) {
    final group = _groupOf(letter);
    if (group == null) return;
    setState(() {
      _cancelGesture(quiet: true);
      final owned = _owners.keys.toSet();
      _selectFaces({
        for (final pick in invertedPicks(_model, _bench.adjacency, group.faces))
          if (!owned.contains(pick.face) && !_crafted(pick.face)) pick.face,
      });
    });
  }

  /// Throws group [letter] away, with its desk. Its faces are free again.
  void _deleteGroup(int? letter) {
    if (letter == null || _groupOf(letter) == null) return;
    setState(() {
      _cancelGesture(quiet: true);
      _pushUndo();
      _bench.groups.removeWhere((g) => g.letter == letter);
      if (_bench.open == letter) {
        _bench.open = null;
        _bench.extra = const [];
        _bench.extraNet = AsmrNet.empty;
      }
      if (_tool == _Tool.arrange) _tool = _Tool.select;
      _syncSelection();
      HapticFeedback.mediumImpact();
    });
  }

  void _mergeGroups(int target, int dropped) {
    final into = _groupOf(target);
    final from = _groupOf(dropped);
    if (into == null || from == null || target == dropped) return;
    setState(() {
      _cancelGesture(quiet: true);
      _pushUndo();
      _setGroup(mergeGroups(into, from));
      _bench.groups.removeWhere((g) => g.letter == dropped);
      _bench.open = target;
      _bench.extra = const [];
      _bench.extraNet = AsmrNet.empty;
      _syncSelection();
      HapticFeedback.mediumImpact();
    });
  }

  // -------------------------------------------------------------------------
  // Scrap slots
  // -------------------------------------------------------------------------

  bool _inside(GlobalKey key, Offset local) {
    final stack = _stackKey.currentContext?.findRenderObject() as RenderBox?;
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (stack == null || box == null || !box.attached || !box.hasSize) {
      return false;
    }
    final global = stack.localToGlobal(local);
    final origin = box.localToGlobal(Offset.zero);
    return (origin & box.size).contains(global);
  }

  /// -1 for the trash, a slot index, or null.
  int? _binAt(Offset local) {
    if (_inside(_trashKey, local)) return -1;
    for (var i = 0; i < kScrapSlots; i++) {
      if (_inside(_slotKeys[i], local)) return i;
    }
    return null;
  }

  void _dropInBin(int bin) {
    final held = [
      for (final paper in _papers)
        if (_moveFrom.containsKey(paper.id)) paper,
    ];
    if (held.isEmpty) return;
    if (bin >= 0) {
      final slots = _bench.slots;
      final free = [
        for (var i = 0; i < slots.length; i++)
          if (slots[i] == null) i,
      ];
      if (free.isEmpty) {
        _putBack();
        return;
      }
      final order = [bin, ...free.where((i) => i != bin)];
      if (slots[bin] != null) order.remove(bin);
      var k = 0;
      final stowed = <String>{};
      for (final paper in held) {
        if (k >= order.length) break;
        slots[order[k++]] = _moveFrom[paper.id] ?? paper;
        stowed.add(paper.id);
      }
      _papers = [
        for (final paper in _papers)
          if (!stowed.contains(paper.id)) paper,
      ];
    } else {
      _papers = [
        for (final paper in _papers)
          if (!_moveFrom.containsKey(paper.id)) paper,
      ];
    }
    _selectedIds.removeWhere((id) => _paper(id) == null);
  }

  void _unstow(int slot) {
    final paper = _bench.slots[slot];
    if (paper == null) return;
    setState(() {
      _cancelGesture(quiet: true);
      if (!_claim()) return;
      _pushUndo();
      _bench.slots[slot] = null;
      final middle = _toDesk(_deskCenter);
      var back = paper.copyWith(
        position: paper.position + (middle - paper.deskCenter),
      );
      final shift = snapShift(_rules, SnapUser.paperMove, [
        for (final ring in back.drawnRings) ...ring,
      ], _snapContext);
      back = back.copyWith(position: back.position + shift);
      _papers = [..._papers, back];
      _tool = _Tool.select;
      _selectedIds
        ..clear()
        ..add(back.id);
    });
  }

  void _putBack() {
    _papers = [for (final paper in _papers) _moveFrom[paper.id] ?? paper];
  }

  // -------------------------------------------------------------------------
  // Pointers
  // -------------------------------------------------------------------------

  double _span() {
    final points = _pointers.values.toList();
    return points.length < 2 ? 0 : (points[0] - points[1]).distance;
  }

  Offset _focal() {
    var sum = Offset.zero;
    for (final p in _pointers.values) {
      sum += p;
    }
    return _pointers.isEmpty ? Offset.zero : sum / _pointers.length.toDouble();
  }

  bool _scrubbed(Duration time) {
    var hit = false;
    for (final entry in _pointers.entries) {
      final scrub = _scrubs.putIfAbsent(entry.key, AsmrScrub.new);
      if (scrub.add(time, entry.value)) hit = true;
    }
    if (_pointers.length >= 2 && _focalScrub.add(time, _focal())) hit = true;
    return hit;
  }

  /// Drops the gesture under way. Paper in hand goes back where it was
  /// picked up; a fold being bent eases flat.
  void _cancelGesture({bool quiet = false}) {
    final drag = _drag;
    if (drag == _Drag.cut) _dropStroke();
    if (drag == _Drag.straight || drag == _Drag.scissors) {
      _segmentStart = null;
      _segmentEnd = null;
      _snapShown = null;
    }
    final home = _marqueeHome;
    if (home != null) {
      _bench.open = home.open;
      _bench.extra = home.extra;
      _bench.extraNet = gridNet(_model, _bench.adjacency, home.extra);
      _syncSelection();
    }
    _marqueeStart = null;
    _marqueeEnd = null;
    _marqueeHome = null;
    if (_moveFrom.isNotEmpty) _putBack();
    _moveFrom = {};
    _movePrimary = null;
    final from = _islandFrom;
    if (from != null) _setGroup(_group.copyWith(net: from));
    _islandFrom = null;
    _island = null;
    final edgeHome = _edgeHome;
    if (edgeHome != null) {
      _edgeAnchor = edgeHome;
      _edgeAngle = _edgeHomeAngle;
      _edgeHome = null;
    }
    if (_folding) {
      _folding = false;
      final id = _foldPaper;
      if (id != null) {
        _settle = _Settle(id, foldPreviewBend(_foldSigned), 0, preview: true);
      }
    }
    if (_settle == null) _clearFolder();
    _foldGuide = null;
    _foldLine = null;
    _foldFlap = null;
    _unfoldLine = null;
    _bin = null;
    _drag = _Drag.none;
    _dragMoved = true;
    _gestureBefore = null;
    for (final scrub in _scrubs.values) {
      scrub.reset();
    }
    _focalScrub.reset();
    if (!quiet) HapticFeedback.mediumImpact();
  }

  void _onPointerDown(PointerDownEvent event) {
    _lastKind = event.kind;
    final first = _pointers.isEmpty;
    _pointers[event.pointer] = event.localPosition;
    if (first) _scrubs.clear();
    _focalScrub.reset();
    if (_aimsWithCursor) _hover = event.localPosition;
    if (first) _manyFingers = false;
    if (_pointers.length >= 2) {
      _manyFingers = true;
      _doubleTap.reset();
      _beginTwoFinger();
      return;
    }
    _dragStart = event.localPosition;
    _dragStartTime = event.timeStamp;
    _dragMoved = false;
    final secondary =
        event.kind == PointerDeviceKind.mouse &&
        (event.buttons & (kSecondaryMouseButton | kMiddleMouseButton)) != 0;
    setState(() {
      if (_phase == _Phase.room) {
        _drag = _Drag.room;
        _roomGrab = _camera.planePoint(event.localPosition, _viewport);
        return;
      }
      if (!_inBench) {
        _drag = _Drag.none;
        return;
      }
      if (_deskActive) _refreshHover();
      if (_modelActive) {
        if (secondary) {
          _drag = _Drag.pan;
        } else if (_modelTool == _ModelTool.select) {
          _drag = _Drag.marquee;
          _marqueeHome = (open: _bench.open, extra: _bench.extra);
          _marqueeStart = event.localPosition;
          _marqueeEnd = event.localPosition;
        } else {
          _drag = _Drag.orbit;
        }
        return;
      }
      if (secondary) {
        _drag = _Drag.deskPan;
        return;
      }
      if (_grabEdge(event.localPosition)) return;
      _startDeskDrag(event.localPosition);
    });
  }

  void _startDeskDrag(Offset pointer) {
    final desk = _toDesk(pointer);
    _deskStart = desk;
    final acts = switch (_tool) {
      _Tool.exacto || _Tool.straight || _Tool.scissors || _Tool.folder => true,
      _Tool.arrange => false,
      _Tool.select => _paperAt(desk) != null || _onHandle(pointer),
    };
    if (acts && !_claim()) {
      _drag = _Drag.none;
      return;
    }
    switch (_tool) {
      case _Tool.exacto:
        _drag = _Drag.cut;
        _beginCut(pointer);
        return;
      case _Tool.straight:
        _drag = _Drag.straight;
        _segmentStart = _snapTo(SnapUser.straightCut, desk);
        _segmentEnd = _segmentStart;
        _snapShown = _segmentStart;
        return;
      case _Tool.scissors:
        _drag = _Drag.scissors;
        _segmentStart = _snapTo(SnapUser.scissors, desk);
        _segmentEnd = _segmentStart;
        _snapShown = _segmentStart;
        return;
      case _Tool.folder:
        if (_settle != null) {
          _drag = _Drag.none;
          return;
        }
        _drag = _Drag.fold;
        _holdSince = _clock;
        _aimFolder(desk);
        return;
      case _Tool.arrange:
        final island = islandAt(_net, desk);
        if (island == null) {
          _drag = _Drag.deskPan;
          return;
        }
        _drag = _Drag.island;
        _island = island;
        _islandFrom = _net;
        _gestureBefore = _capture();
        return;
      case _Tool.select:
        break;
    }
    final selected = _selected;
    if (selected != null && _onHandle(pointer)) {
      _drag = _Drag.rotate;
      _moveFrom = {selected.id: selected};
      _movePrimary = selected.id;
      _rotatePivot = selected.deskCenter;
      final center = _toScreen(_rotatePivot);
      _rotateFrom = math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
      _gestureBefore = _capture();
      return;
    }
    final hit = _paperAt(desk);
    if (hit != null) {
      _drag = _Drag.move;
      if (!_selectedIds.contains(hit.id)) {
        _selectedIds
          ..clear()
          ..add(hit.id);
      }
      _moveFrom = {
        for (final paper in _papers)
          if (_selectedIds.contains(paper.id)) paper.id: paper,
      };
      _movePrimary = hit.id;
      _papers = [
        for (final paper in _papers)
          if (!_moveFrom.containsKey(paper.id)) paper,
        for (final paper in _papers)
          if (_moveFrom.containsKey(paper.id) && paper.id != hit.id) paper,
        hit,
      ];
      _gestureBefore = _capture();
      return;
    }
    _drag = _Drag.deskPan;
  }

  bool _onHandle(Offset pointer) {
    final selected = _selected;
    final handle = selected == null ? null : _handleFor(selected);
    return handle != null && (pointer - handle).distance <= _kHandleRadius;
  }

  void _beginTwoFinger() {
    setState(() {
      if (_drag != _Drag.none &&
          _drag != _Drag.pan &&
          _drag != _Drag.deskPan &&
          _drag != _Drag.room &&
          _drag != _Drag.orbit) {
        _cancelGesture(quiet: true);
      }
      _drag = _Drag.pan;
      _dragMoved = true;
      _marqueeStart = null;
      _marqueeEnd = null;
      _lastSpan = _span();
      _lastFocal = _focal();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.localPosition;
    if (_aimsWithCursor) _hover = event.localPosition;
    if (_inBench && _scrubbed(event.timeStamp)) {
      setState(_cancelGesture);
      return;
    }
    final delta = event.localPosition - previous;
    final slop = _drag == _Drag.fold ? _kFoldHoldSlop : _kTapSlop;
    if ((event.localPosition - _dragStart).distance > slop) _dragMoved = true;
    setState(() {
      if (_inBench && _deskActive) _refreshHover();
      if (_pointers.length >= 2) {
        _twoFingerMove();
        return;
      }
      final local = event.localPosition;
      switch (_drag) {
        case _Drag.room:
          if ((local - _dragStart).distance < _kRoomSlop) return;
          _panRoom(local);
          _refreshHover();
        case _Drag.orbit:
          if (!_dragMoved) return;
          _turntable(-delta.dx * _kOrbitPerPixel, delta.dy * _kOrbitPerPixel);
          _refreshHover();
        case _Drag.pan:
          _panView(delta);
        case _Drag.marquee:
          _marqueeEnd = local;
          if (_dragMoved) _applyMarquee();
        case _Drag.cut:
          _extendCut(local);
        case _Drag.straight:
          _segmentEnd = _snapTo(SnapUser.straightCut, _toDesk(local));
          _snapShown = _segmentEnd;
        case _Drag.scissors:
          _segmentEnd = _toDesk(local);
        case _Drag.fold:
          if (_folding) {
            _bendFolder(local);
          } else if (_dragMoved) {
            _aimFolder(_toDesk(local));
          }
        case _Drag.move:
          _moveHeld(_toDesk(local) - _deskStart);
          _bin = _binAt(local);
        case _Drag.rotate:
          _turnHeld(local);
        case _Drag.island:
          _moveIsland(_toDesk(local) - _deskStart);
        case _Drag.deskPan:
          _deskOrigin += delta;
        case _Drag.edgeSlide:
          final edge = _edge;
          if (edge == null) return;
          final push = delta.dx * edge.normal.dx + delta.dy * edge.normal.dy;
          _edgeDragAnchor += edge.normal * (push / _deskScale);
          _placeEdge();
        case _Drag.edgeTurn:
          final now = math.atan2(
            local.dy - _edgePivot.dy,
            local.dx - _edgePivot.dx,
          );
          _edgeDragAngle = _edgeTurnBase + now - _edgeTurnFrom;
          _edgeDragAnchor = _toDesk(_edgePivot);
          _placeEdge();
        case _Drag.none:
          break;
      }
    });
  }

  /// Slides the papers in hand by [by], then nudges them so a corner of the
  /// one under the finger lands where moving paper snaps.
  void _moveHeld(Offset by) {
    final primary = _moveFrom[_movePrimary];
    if (primary == null) return;
    final moved = primary.copyWith(position: primary.position + by);
    final shift = snapShift(_rules, SnapUser.paperMove, [
      for (final ring in moved.drawnRings) ...ring,
    ], _snapContext);
    _papers = [
      for (final paper in _papers)
        if (_moveFrom[paper.id] case final from?)
          from.copyWith(position: from.position + by + shift)
        else
          paper,
    ];
  }

  void _turnHeld(Offset pointer) {
    final from = _moveFrom[_movePrimary];
    if (from == null) return;
    final center = _toScreen(_rotatePivot);
    final now = math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
    final target = snapAngle(
      _rules,
      SnapUser.paperMove,
      from.angle + now - _rotateFrom,
    );
    var turned = from.turnedAbout(target - from.angle, _rotatePivot);
    final shift = snapShift(_rules, SnapUser.paperMove, [
      for (final ring in turned.drawnRings) ...ring,
    ], _snapContext);
    turned = turned.copyWith(position: turned.position + shift);
    _replacePaper(turned);
  }

  void _moveIsland(Offset by) {
    final island = _island;
    final from = _islandFrom;
    if (island == null || from == null) return;
    final corners = [
      for (final face in islandFaces(from, island))
        for (final p in face.ring) p + by,
    ];
    final shift =
        by + snapShift(_rules, SnapUser.islandMove, corners, _snapContext);
    _setGroup(
      _group.copyWith(
        net: from.transformedIslands({island: islandMove(shift: shift)}),
      ),
    );
    _rebuildNet();
  }

  /// Turns the island under a tap by the islands' turn step, about its
  /// middle, and puts a corner back on the grid.
  void _turnIsland(int island) {
    final net = _net;
    final step = _rules[SnapUser.islandMove].rotationStep ?? math.pi / 2;
    final pivot = snapToCraftGrid(islandBounds(net, island).center, kBenchGrid);
    final turn = islandMove(angle: step, pivot: pivot);
    final turned = net.transformedIslands({island: turn});
    final corners = [
      for (final face in islandFaces(turned, island)) ...face.ring,
    ];
    final shift = snapShift(_rules, SnapUser.islandMove, corners, _snapContext);
    _pushUndo();
    _setGroup(
      _group.copyWith(
        net: turned.transformedIslands({island: islandMove(shift: shift)}),
      ),
    );
    _rebuildNet();
  }

  void _twoFingerMove() {
    final focal = _focal();
    final span = _span();
    final scale = _lastSpan > 1 && span > 1 ? span / _lastSpan : 1.0;
    final delta = focal - _lastFocal;
    _lastFocal = focal;
    _lastSpan = span;
    if (!_inBench) {
      if (_phase == _Phase.room && (scale - 1).abs() > 1e-4) {
        _camera.zoomByScale(scale);
        _refreshHover();
      }
      return;
    }
    if (_modelActive) {
      _panView(delta);
      if ((scale - 1).abs() > 1e-4) _camera.zoomByScale(scale);
    } else {
      _deskOrigin += delta;
      if ((scale - 1).abs() > 1e-4) _zoomDesk(scale, focal);
    }
  }

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    _scrubs.remove(event.pointer);
    _focalScrub.reset();
    if (_pointers.isNotEmpty) {
      _lastFocal = _focal();
      _lastSpan = _span();
      return;
    }
    final moved = _dragMoved;
    final tap = !moved && event.timeStamp - _dragStartTime < _kTapTime;
    final switchTap =
        _inBench &&
        tap &&
        !_manyFingers &&
        event is PointerUpEvent &&
        (event.localPosition - _dragStart).distance < _kTapSlop &&
        _emptyAt(event.localPosition);
    setState(() {
      switch (_drag) {
        case _Drag.room:
          _roomGrab = null;
          if (!moved &&
              (event.localPosition - _dragStart).distance < _kRoomSlop) {
            final aim = _aimsWithCursor ? event.localPosition : _modelCenter;
            final index = _craftAt(aim);
            if (index != null) _enterCraft(index);
          }
        case _Drag.marquee:
          if (tap) {
            final aim = _aimFace(event.localPosition);
            if (!aim.blocked) {
              _selectFaces(
                aim.face == null ? const {} : {aim.face!},
                prefer: aim.face,
              );
            }
          }
          _marqueeStart = null;
          _marqueeEnd = null;
        case _Drag.cut:
          _endCut();
        case _Drag.straight:
        case _Drag.scissors:
          _endSegment();
        case _Drag.fold:
          _releaseFolder(tap: !moved);
          _snapShown = null;
        case _Drag.move:
          final bin = moved ? _binAt(event.localPosition) : null;
          if (bin != null) _dropInBin(bin);
          if (!moved) _papers = List.of(_papers);
        case _Drag.island:
          final island = _island;
          if (!moved && island != null) {
            final from = _islandFrom;
            if (from != null) _setGroup(_group.copyWith(net: from));
            _gestureBefore = null;
            _turnIsland(island);
          }
          _island = null;
          _islandFrom = null;
        case _Drag.deskPan:
          if (tap && _tool == _Tool.select) _selectedIds.clear();
        case _Drag.edgeSlide:
        case _Drag.edgeTurn:
          _edgeHome = null;
        case _Drag.orbit:
        case _Drag.pan:
        case _Drag.rotate:
        case _Drag.none:
          break;
      }
      _drag = _Drag.none;
      _moveFrom = {};
      _movePrimary = null;
      _marqueeHome = null;
      _bin = null;
      _commitGesture();
      if (!switchTap) {
        if (tap) _doubleTap.reset();
      } else if (_doubleTap.tap(event.localPosition, _clock)) {
        _setActive(_modelActive ? Workview.desk : Workview.model);
      }
      if (_inBench && _deskActive) _refreshHover();
    });
  }

  void _onPointerHover(PointerHoverEvent event) {
    _lastKind = event.kind;
    setState(() {
      _hover = event.localPosition;
      _refreshHover();
      if (_inBench && _tool == _Tool.exacto) {
        _tipDesk = _deskActive ? _toDesk(event.localPosition) : null;
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final factor = math.exp(-event.scrollDelta.dy * 0.002);
    setState(() {
      if (_phase == _Phase.room) {
        _camera.zoomByScale(factor);
        _refreshHover();
      } else if (_inBench) {
        if (_modelActive) {
          _camera.zoomByScale(factor);
          _refreshHover();
        } else {
          _zoomDesk(factor, event.localPosition);
        }
      }
    });
  }

  double _panZoomScale = 1;
  bool _panZoomModel = false;

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _lastKind = event.kind;
    _panZoomScale = 1;
    _panZoomModel = _modelActive;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final factor = _panZoomScale > 0 ? event.scale / _panZoomScale : 1.0;
    _panZoomScale = event.scale;
    setState(() {
      if (_phase == _Phase.room) {
        if ((factor - 1).abs() > 1e-4) _camera.zoomByScale(factor);
        return;
      }
      if (!_inBench) return;
      if (_panZoomModel) {
        _panView(event.localPanDelta);
        if ((factor - 1).abs() > 1e-4) _camera.zoomByScale(factor);
      } else {
        _deskOrigin += event.localPanDelta;
        if ((factor - 1).abs() > 1e-4) _zoomDesk(factor, event.localPosition);
      }
    });
  }

  void _setTool(_Tool tool) {
    _cancelGesture(quiet: true);
    _tool = tool;
    if (tool != _Tool.select) _selectedIds.clear();
    if (tool != _Tool.exacto) _tipDesk = null;
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  bool get _showKnife => _inBench && _deskActive && _tool == _Tool.exacto;

  Offset? get _knifeScreen {
    if (!_showKnife || _tipDesk == null) return null;
    return _finger != null ? _bladeAt(_finger!) : _toScreen(_tipDesk!);
  }

  List<HologramEdgeView> get _edgeViews => [
    for (final held in _holoEdges.values)
      HologramEdgeView(
        a: held.edge.a,
        b: held.edge.b,
        fold: held.edge.fold,
        opacity: 1,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAsmrDeskColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _onLayout(constraints.biggest);
          return Stack(
            key: _stackKey,
            children: [
              Positioned.fill(child: _input()),
              if (_knifeScreen case final tip?)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AsmrKnifePainter(tip: tip, finger: _finger),
                    ),
                  ),
                ),
              if (_modelActive && _marqueeStart != null && _marqueeEnd != null)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AsmrMarqueePainter(
                        start: _marqueeStart!,
                        end: _marqueeEnd!,
                      ),
                    ),
                  ),
                ),
              if (_phase == _Phase.room || _inBench)
                if (_aim case final aim?)
                  Positioned(
                    key: const ValueKey('craft-room-crosshair'),
                    left: aim.dx - _kReticleBox / 2,
                    top: aim.dy - _kReticleBox / 2,
                    width: _kReticleBox,
                    height: _kReticleBox,
                    child: const IgnorePointer(child: ViewCrosshair()),
                  ),
              ..._chrome(context),
              if (_flights.isNotEmpty)
                Positioned.fill(
                  key: const ValueKey('craft-room-flight'),
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AsmrFlightPainter(
                        flights: List.of(_flights),
                        camera: _camera,
                        model: _model,
                        modelSize: _viewport,
                        tiles: _tiles,
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// The crosshair stands in for the cursor over the room and the 3D
  /// workview, and the knife over the desk with the exacto.
  bool get _hideCursor => _showKnife || !_inBench || _modelActive;

  Widget _input() {
    final order = [
      for (final view in Workview.values)
        if (view != _active) view,
      _active,
    ];
    return MouseRegion(
      cursor: _hideCursor ? SystemMouseCursors.none : MouseCursor.defer,
      onExit: (_) => setState(() {
        _hover = null;
        _refreshHover();
        if (_aimsWithCursor && _stroke == null) _tipDesk = null;
      }),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerUp,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: Stack(
          children: [
            Positioned.fill(child: _backdrop()),
            for (final view in order)
              if (view == Workview.model || _deskShown)
                Positioned.fill(child: _workview(view)),
          ],
        ),
      ),
    );
  }

  /// Under every workview: the sky, and the desk's color over it as far as
  /// the desk is active.
  Widget _backdrop() {
    final desk = _deskShown
        ? Curves.easeInOut.transform(_activeShown[Workview.desk]!) * _benchShown
        : 0.0;
    return IgnorePointer(
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [kAsmrSkyColor, kAsmrDeskColor],
                ),
              ),
            ),
          ),
          if (desk > 0)
            Positioned.fill(
              child: ColoredBox(color: _theme.desk.withValues(alpha: desk)),
            ),
        ],
      ),
    );
  }

  /// [view] at its look: full strength while active, the DevTools look while
  /// not, easing between them. The desk also fades with [_benchShown].
  Widget _workview(Workview view) {
    final t = Curves.easeInOut.transform(_activeShown[view]!);
    var look = WorkviewLook.lerp(_looks.inactive, WorkviewLook.identity, t);
    if (view == Workview.desk) {
      look = look.withOpacity(look.opacity * _benchShown);
    }
    final child = switch (view) {
      Workview.model => _inRoomView ? _roomLayer() : _modelLayer(),
      Workview.desk => _deskLayer(),
    };
    return IgnorePointer(
      child: look.wrap(
        child,
        key: ValueKey('craft-room-workview-${view.name}'),
      ),
    );
  }

  Widget _deskLayer() {
    final selected = _tool == _Tool.select ? _selected : null;
    final papers = _shownPapers;
    final guide = splitCraftGuide(_edgeViews, papers);
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(
            key: const Key('craft-room-desk'),
            painter: CraftBenchPainter(
              background: false,
              papers: papers,
              theme: _theme,
              paperGridOpacity: _snap.paperGridOpacity,
              origin: _deskOrigin,
              scale: _deskScale,
              selectedIds: _tool == _Tool.select
                  ? Set.of(_selectedIds)
                  : const {},
              selectedOutline: _selectedOutline,
              flash: Map.of(_flash),
              bend: _bend,
              stroke: _stroke == null ? null : List.of(_stroke!),
              cuts: _cutPreview,
              crease: _foldLine,
              flap: _folding ? null : _foldFlap,
              unfold: _unfoldLine,
              snap: _snapShown,
              island: _tool == _Tool.arrange && _island != null
                  ? [for (final face in islandFaces(_net, _island!)) face.ring]
                  : const [],
              islandColor: _group.color,
              pencil: guide.pencil,
              rotateHandle: selected == null ? null : _handleFor(selected),
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned.fill(
          child: CustomPaint(
            painter: HologramPainter(
              edges: guide.bare,
              faces: [for (final face in _net.faces) face.ring],
              origin: _deskOrigin,
              scale: _deskScale,
              contrast: 1,
              line: _theme.line,
              glow: _theme.glow,
            ),
          ),
        ),
        Positioned.fill(child: _straightEdgeLayer()),
      ],
    );
  }

  Widget _roomLayer() {
    final collection = _collection;
    if (collection == null) return const SizedBox.expand();
    final shown = _roomShown;
    return CustomPaint(
      key: const Key('craft-room-room'),
      painter: CraftCollectionPainter(
        camera: _camera,
        surfaces: collection.surfaces,
        opacity: shown,
        crafts: [
          for (var i = 0; i < _crafts.length; i++)
            CollectionCraft(
              model: _crafts[i].placed,
              finished: _finished.contains(i),
              hover: i == _hoverCraft ? 1 : 0,
              opacity: i == _entered ? 1 : shown,
            ),
        ],
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _modelLayer() {
    final model = _model;
    final glow = _complete
        ? {
            for (var f = 0; f < model.faces.length; f++)
              f: _completeShown * (0.6 + 0.4 * math.sin(_clock * 3)),
          }
        : const <int, double>{};
    return CustomPaint(
      key: const Key('craft-room-model'),
      painter: ModelPainter(
        camera: _camera,
        model: model,
        covered: {
          for (final entry in _coverage.entries)
            if (entry.value >= kAsmrFilled) entry.key: 1.0,
        },
        glow: glow,
        sheets: (canvas, size, add) => addBoundPaper(
          canvas: canvas,
          size: size,
          camera: _camera,
          model: model,
          pieces: List.of(_bench.bound),
          tiles: _tiles,
          add: add,
          highlight: Map.of(_faceFill),
          tint: _shownFaceTints,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  Widget _straightEdgeLayer() {
    final edge = _edge;
    if (edge == null || _edgeShown <= 0) return const SizedBox.shrink();
    return CustomPaint(
      key: const Key('craft-room-straight-edge'),
      painter: AsmrStraightEdgePainter(
        edge: edge,
        fly: _edgeFly,
        handle: _edgeHandle,
        pressed: _drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn,
      ),
      child: const SizedBox.expand(),
    );
  }

  int get _filledCount =>
      _coverage.values.where((c) => c >= kAsmrFilled).length;

  String get _title {
    if (_phase == _Phase.loading ||
        _phase == _Phase.rising ||
        _inBench ||
        _phase == _Phase.leaving ||
        _phase == _Phase.spinning) {
      return 'Faces filled  $_filledCount / ${_model.faces.length}';
    }
    final hover = _hoverCraft;
    if (_phase == _Phase.room && hover != null) {
      return _crafts[hover].craft.name;
    }
    return _collection?.name ?? 'Craft Room';
  }

  String get _hint => _modelActive
      ? switch (_modelTool) {
          _ModelTool.orbit =>
            'Drag to turn the craft. Double-tap empty space for the desk.',
          _ModelTool.select =>
            'Drag a box or tap a face to select. Double-tap empty space for the desk.',
        }
      : _deskHint;

  String get _deskHint => switch (_tool) {
    _Tool.select =>
      'Drag paper to move it, or into a scrap slot. Turn it by its handle.',
    _Tool.exacto =>
      'Cut freely. Cut a net island out exactly and it folds onto the craft.',
    _Tool.straight =>
      'Drag to set a line. The paper it crosses is cut right through along it.',
    _Tool.scissors =>
      'Press on a grid point and drag: each snip cuts 3 squares.',
    _Tool.folder =>
      'Hold on paper, then drag across the crease to fold. Tap a crease to open it.',
    _Tool.arrange => 'Drag a net island to move it. Tap it to turn it.',
  };

  void _back(BuildContext context) {
    if (_phase == _Phase.loading || _phase == _Phase.rising || _inBench) {
      setState(_leave);
      return;
    }
    if (_phase != _Phase.room) return;
    if (context.canPop()) {
      context.pop();
    } else {
      context.goNamed('dev_routes');
    }
  }

  List<Widget> _chrome(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return [
      Positioned(
        top: padding.top + 8,
        left: 8,
        child: AsmrRoundButton(
          key: const Key('craft-room-back'),
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onTap: () => _back(context),
        ),
      ),
      Positioned(
        top: padding.top + 14,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Text(
              _title,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
      if (_inBench) ..._benchChrome(padding),
      Positioned(
        top: padding.top + 8,
        right: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            DevToolsButton(
              active: _devToolsOpen,
              onPressed: () => setState(() => _devToolsOpen = !_devToolsOpen),
            ),
            if (_devToolsOpen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AsmrDevPanel(
                  settings: _settings,
                  pages: [
                    AsmrDevPage(
                      label: 'Snap',
                      tabKey: const Key('craft-room-dev-tab-snap'),
                      builder: (context) => SnapRulesPage(settings: _snap),
                    ),
                    AsmrDevPage(
                      label: 'Workviews',
                      tabKey: const Key('craft-room-dev-tab-workviews'),
                      builder: (context) => WorkviewPage(settings: _looks),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _modelCarousel() => HudToolCarousel<_ModelTool>(
    items: [
      HudCarouselItem(
        value: _ModelTool.orbit,
        icon: Icons.threed_rotation,
        label: 'Orbit',
        fill: CraftPalette.cerulean.fill,
      ),
      HudCarouselItem(
        value: _ModelTool.select,
        icon: Icons.highlight_alt,
        label: 'Select faces',
        fill: CraftPalette.kentuckyBlue.fill,
      ),
    ],
    selected: _modelTool,
    onSelect: (tool) => setState(() {
      _modelTool = tool;
      _marqueeStart = null;
      _marqueeEnd = null;
    }),
  );

  Widget _deskCarousel(CraftGroup group) => HudToolCarousel<_Tool>(
    items: [
      HudCarouselItem(
        value: _Tool.select,
        icon: Icons.open_with,
        label: 'Select',
        fill: CraftPalette.kentuckyBlue.fill,
      ),
      HudCarouselItem(
        value: _Tool.exacto,
        icon: Icons.colorize,
        label: 'Exacto',
        fill: CraftPalette.scarlet.fill,
      ),
      HudCarouselItem(
        value: _Tool.straight,
        icon: Icons.horizontal_rule,
        label: 'Straight cut',
        fill: CraftPalette.ginger.fill,
      ),
      HudCarouselItem(
        value: _Tool.scissors,
        icon: Icons.content_cut,
        label: 'Scissors',
        fill: CraftPalette.scarlet.fill,
      ),
      HudCarouselItem(
        value: _Tool.folder,
        icon: Icons.flip,
        label: 'Folder',
        fill: CraftPalette.cerulean.fill,
      ),
      if (group.saved && !_hasPending)
        HudCarouselItem(
          value: _Tool.arrange,
          icon: Icons.dashboard_customize_outlined,
          label: 'Arrange',
          fill: CraftPalette.granite.fill,
        ),
    ],
    selected: _tool == _Tool.arrange && (!group.saved || _hasPending)
        ? _Tool.select
        : _tool,
    onSelect: (tool) => setState(() => _setTool(tool)),
    trailing: [
      SizedBox(
        width: 56,
        child: HudToolButton(
          icon: Icons.straighten,
          label: 'Straight edge',
          fill: CraftPalette.granite.fill,
          selected: _edgeOn,
          onTap: _toggleEdge,
        ),
      ),
    ],
  );

  List<Widget> _benchChrome(EdgeInsets padding) {
    final save = _saveAt;
    final group = _group;
    final desk = _deskActive;
    return [
      if (save != null) _saveButton(save),
      Positioned(
        right: 8,
        top: padding.top + 48,
        height: math.max(0, _slotsTop - padding.top - 56),
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final group in _bench.groups) _groupChip(group),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      Positioned(
        right: 8,
        bottom: padding.bottom + 12,
        child: DragTarget<int>(
          onAcceptWithDetails: (details) => _deleteGroup(details.data),
          builder: (context, candidate, rejected) => KeyedSubtree(
            key: const Key('craft-room-trash'),
            child: AsmrTrashButton(
              key: _trashKey,
              hot: _bin == -1 || candidate.isNotEmpty,
            ),
          ),
        ),
      ),
      if (_noteShown > 0)
        Positioned(
          left: 24,
          right: 24,
          top: padding.top + 64,
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: math.min(1, _noteShown * 4),
                child: Container(
                  key: const Key('craft-room-note'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    _note,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
              ),
            ),
          ),
        ),
      if (desk)
        Positioned(
          top: padding.top + 56,
          left: 8,
          child: _PillButton(
            buttonKey: const Key('craft-room-paper'),
            icon: Icons.note_add_outlined,
            label: 'Paper',
            onTap: _layPaper,
          ),
        ),
      if (desk &&
          (_stowFlights.isNotEmpty ||
              _selectedIds.any((id) => _paper(id) != null) ||
              _bench.slots.any((paper) => paper != null)))
        Positioned(
          right: 8,
          top: _slotsTop,
          height: _slotsBottom - _slotsTop,
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      for (var i = 0; i < kScrapSlots; i++)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: i == kScrapSlots - 1 ? 0 : 8,
                          ),
                          child: _slotsOpen || _bench.slots[i] != null
                              ? _ScrapSlot(
                                  key: _slotKeys[i],
                                  slotKey: Key('craft-room-slot-$i'),
                                  paper: _bench.slots[i],
                                  hot: _bin == i,
                                  onTap: () => _unstow(i),
                                )
                              : const SizedBox(width: 52, height: 52),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      for (final flight in _stowFlights)
        Positioned(
          key: ValueKey('craft-room-stow-${flight.paper.id}'),
          left: flight.at.dx - 26,
          top: flight.at.dy - 26,
          width: 52,
          height: 52,
          child: IgnorePointer(
            child: Transform.scale(
              scale: 1.35 - 0.35 * flight.eased,
              child: CustomPaint(painter: _ScrapPainter(flight.paper)),
            ),
          ),
        ),
      if (desk && group.saved)
        Positioned(
          top: padding.top + 36,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: Text(
              'Group ${group.name}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: group.color.withValues(alpha: 0.9),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      Positioned(
        left: 0,
        right: 0,
        bottom: padding.bottom + 84,
        child: IgnorePointer(
          child: Center(
            child: Text(
              _hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 64,
        right: 72,
        bottom: padding.bottom + 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AsmrHistoryButton(
              buttonKey: const Key('craft-room-undo'),
              icon: Icons.undo,
              tooltip: 'Undo',
              enabled: _bench.undo.isNotEmpty,
              gap: const EdgeInsets.only(right: _kHistoryPad),
              onTap: _undo,
            ),
            Flexible(
              child: KeyedSubtree(
                key: ValueKey('craft-room-tools-${_active.name}'),
                child: desk ? _deskCarousel(group) : _modelCarousel(),
              ),
            ),
            AsmrHistoryButton(
              buttonKey: const Key('craft-room-redo'),
              icon: Icons.redo,
              tooltip: 'Redo',
              enabled: _bench.redo.isNotEmpty,
              gap: const EdgeInsets.only(left: _kHistoryPad),
              onTap: _redo,
            ),
          ],
        ),
      ),
      if (_completeShown > 0)
        Positioned(
          key: const ValueKey('craft-room-complete'),
          left: 0,
          right: 0,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Center(
              child: Opacity(
                opacity: _completeShown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.6),
                    ),
                  ),
                  child: const Text(
                    'Craft complete',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ];
  }

  /// Save while no group is open, Add (+) while one is. Grey when a new
  /// group is needed and A to E are all taken.
  Widget _saveButton(Offset at) {
    final open = _groupOf(_bench.open);
    final letter = open?.letter ?? nextLetter(_bench.groups);
    final full = letter == null;
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: Tooltip(
        message: full
            ? 'Groups A to E are all used'
            : open != null
            ? 'Add to group ${open.name}'
            : 'Save as a group',
        child: Material(
          key: const Key('craft-room-save'),
          color: full ? Colors.grey.shade600 : craftGroupTheme(letter).accent,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: full ? null : _saveGroup,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(
                open != null ? Icons.add : Icons.save_outlined,
                size: 22,
                color: Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _groupChip(CraftGroup group) {
    final letter = group.letter!;
    final open = _bench.open == letter;
    Widget chip({bool lifted = false, bool hot = false}) => Container(
      width: _kGroupChip,
      height: _kGroupChip,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: group.color.withValues(alpha: open || lifted ? 0.95 : 0.5),
        border: Border.all(
          color: hot || open ? Colors.white : Colors.white24,
          width: hot ? 3 : 2,
        ),
        boxShadow: lifted
            ? const [BoxShadow(color: Colors.black54, blurRadius: 10)]
            : null,
      ),
      child: Text(
        group.name,
        style: const TextStyle(
          color: Colors.black87,
          fontWeight: FontWeight.w700,
          fontSize: 16,
        ),
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (details) => details.data != letter,
        onAcceptWithDetails: (details) => _mergeGroups(letter, details.data),
        builder: (context, candidate, rejected) => Draggable<int>(
          data: letter,
          feedback: Material(
            color: Colors.transparent,
            child: chip(lifted: true),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: chip()),
          child: Tooltip(
            message: 'Group ${group.name}: tap to open, double-tap to invert',
            child: GestureDetector(
              key: ValueKey('craft-room-group-${group.name}'),
              onTap: () => _openGroup(letter),
              onDoubleTap: () => _invertGroup(letter),
              child: chip(hot: candidate.isNotEmpty),
            ),
          ),
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.buttonKey,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black.withValues(alpha: 0.4),
      shape: const StadiumBorder(side: BorderSide(color: Colors.white24)),
      child: InkWell(
        key: buttonKey,
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(color: Colors.white, fontSize: 13),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One scrap slot: empty, or holding a paper drawn small.
class _ScrapSlot extends StatelessWidget {
  const _ScrapSlot({
    super.key,
    required this.slotKey,
    required this.paper,
    required this.hot,
    required this.onTap,
  });

  final Key slotKey;
  final BenchPaper? paper;
  final bool hot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: paper == null ? 'Scrap slot' : 'Lay the scrap back down',
      child: GestureDetector(
        key: slotKey,
        behavior: HitTestBehavior.opaque,
        onTap: paper == null ? null : onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: hot ? 0.55 : 0.3),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.white.withValues(alpha: hot ? 0.8 : 0.2),
              width: hot ? 2 : 1,
            ),
          ),
          child: paper == null
              ? null
              : CustomPaint(painter: _ScrapPainter(paper!)),
        ),
      ),
    );
  }
}

/// A leftover sheet flying from the desk into a scrap slot.
class _StowFlight {
  _StowFlight({
    required this.paper,
    required this.slot,
    required this.from,
    required this.to,
  });

  final BenchPaper paper;
  final int slot;
  final Offset from;
  final Offset to;
  double t = 0;

  bool advance(double seconds) {
    t = math.min(1, t + seconds * 1e6 / _kStowFlight.inMicroseconds);
    return t >= 1;
  }

  double get eased => Curves.easeInOutCubic.transform(t);

  Offset get at => Offset.lerp(from, to, eased)!;
}

class _ScrapPainter extends CustomPainter {
  const _ScrapPainter(this.paper);

  final BenchPaper paper;

  @override
  void paint(Canvas canvas, Size size) {
    final rings = paper.drawnRings;
    if (rings.isEmpty) return;
    var box = Rect.zero;
    var any = false;
    for (final ring in rings) {
      for (final p in ring) {
        final point = Rect.fromLTWH(p.dx, p.dy, 0, 0);
        box = any ? box.expandToInclude(point) : point;
        any = true;
      }
    }
    final scale = math.min(
      (size.width - 10) / math.max(box.width, 1e-6),
      (size.height - 10) / math.max(box.height, 1e-6),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-box.center.dx, -box.center.dy);
    for (var i = 0; i < rings.length; i++) {
      final piece = paper.sheet.pieces[i];
      final path = Path()..addPolygon(rings[i], true);
      canvas.drawPath(
        path,
        Paint()..color = paperSideColor(piece, back: false),
      );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1 / scale
          ..color = Colors.black38,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _ScrapPainter old) => old.paper != paper;
}
