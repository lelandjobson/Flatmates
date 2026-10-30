import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../asmr/asmr_deal.dart';
import '../asmr/asmr_desk_chrome.dart';
import '../asmr/asmr_desk_painter.dart';
import '../asmr/asmr_dev.dart';
import '../asmr/asmr_flight.dart';
import '../asmr/asmr_group.dart';
import '../asmr/asmr_judge.dart';
import '../asmr/asmr_lens.dart';
import '../asmr/asmr_scissor_aim.dart';
import '../asmr/asmr_tool_camera.dart';
import '../asmr/asmr_mapping.dart';
import '../asmr/asmr_model_paper.dart';
import '../asmr/asmr_net.dart';
import '../asmr/asmr_objects.dart';
import '../asmr/asmr_paper.dart';
import '../asmr/asmr_piece.dart';
import '../asmr/asmr_scrub.dart';
import '../asmr/asmr_session.dart';
import '../asmr/asmr_slots.dart';
import '../asmr/asmr_theme.dart';
import '../asmr/asmr_straight_edge.dart';
import '../asmr/asmr_turn_dial.dart';
import '../asmr/hologram_painter.dart';
import '../asmr/hologram_selection.dart';
import '../craftroom/workview.dart';
import '../gridcraft/edit.dart' show marqueePick, polygonInMarquee;
import '../gridcraft/folded_model.dart';
import '../gridcraft/model_painter.dart';
import '../gridcraft/wrap_cut.dart' show FaceNeighbor, faceAdjacency;
import '../papercut/camera.dart';
import '../ui/craft_palette.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';

enum _DeskTool {
  select,
  exacto,
  straight,
  scissors;

  AsmrToolCamera camera(AsmrDevSettings settings) => switch (this) {
    scissors => AsmrToolCamera(
      pitch: settings.perspectiveness,
      lensMm: settings.lensMm,
    ),
    _ => AsmrToolCamera(lensMm: settings.lensMm),
  };
}

/// Tools of the 3D view. Orbit is the one it opens on.
enum _ModelTool { orbit, select }

const Duration _kModeDuration = Duration(milliseconds: 500);
const Duration _kPreselectFade = Duration(milliseconds: 180);
const Duration _kEdgeFade = Duration(milliseconds: 250);
const Duration _kOutlineFade = Duration(milliseconds: 250);
const Duration _kFlashFade = Duration(milliseconds: 600);
const Duration _kStraightEdgeFly = Duration(milliseconds: 450);

/// How long a refused pickup takes to ease back to where it was taken from.
const Duration _kWarp = Duration(milliseconds: 360);

/// How long a blueprint edge takes to change to its newly judged color.
const Duration _kJudgeFade = Duration(milliseconds: 220);

/// The view behind the active one, faded and blurred.
const WorkviewLook _kInactiveLook = WorkviewLook(opacity: 0.33, blur: 3);

/// The bin index of the trash; scrap slots are 0 and up.
const int _kTrashBin = -1;

/// Fill on the face under the aim, against 1 on a selected face.

/// Room around the 3D reticle, which is centered on the aim.
const double _kReticleBox = 24;

const double _kTapSlop = 8;
const Duration _kTapTime = Duration(milliseconds: 350);
const double _kOrbitPerPixel = 0.008;
const double _kMaxTilt = 85 * math.pi / 180;

/// On touch the blade cuts this far above the finger, so the finger does
/// not hide the cut.
const Offset _kKnifeLift = Offset(0, -56);

/// Screen pixels a finger travels for each pixel the scissors cut.
const double _kScissorRatio = 1;

/// A scissors drag shorter than this, in screen pixels, cuts nothing.
const double _kScissorMinDrag = 5;

/// How long the desk takes to bring the end of a scissors cut back to the
/// blade.
const Duration _kScissorAdvance = Duration(milliseconds: 140);

/// Screen pixels the turn dial's bar sits below where the blade cuts.
const double _kDialDrop = 52;

/// Rotation needs deliberate sideways travel; early touch wobble stays undecided.
const double _kScissorTurnSlop = 16;

/// A generous invisible handle, with extra room for fingertips on touch.
const double _kScissorTouchRadius = 44;
const double _kScissorMouseRadius = 32;

/// How long the dial's knob takes to ease back to the middle once let go.
const Duration _kKnobReturn = Duration(milliseconds: 130);

/// Seconds for a cruise to come up to speed, and to slow once let go.
const double _kCruiseTake = 0.12;
const double _kCruiseRelease = 0.35;

/// Most of the screen a blueprint may take while the paper is placed.
const double _kPlaceFill = 0.8;

/// Seconds after the paper comes up for placing before a tap puts it down,
/// so the second tap of the double-tap that opened the desk does not.
const double _kPlaceTapAfter = 0.4;

/// Desk units of cut between haptic ticks.
const double _kTickEvery = 4;

/// Screen pixels above a selected piece where its rotate handle sits.
const double _kHandleLift = 30;
const double _kHandleRadius = 22;

/// Empty space between the icons of neighboring tools: a 56px slot holds a
/// 24px icon. Undo and redo keep half again that much space from the
/// nearest tool. Their own icon is centered in a 40px box, and a tool icon
/// starts 16px into its slot, so the pad on the widget is what remains.
const double _kHistoryPad = 32 * 1.5 - 8 - 16;

const int _kHistoryDepth = 40;

/// Desk units that fit across the shorter side of the screen when the desk
/// first opens.
const double _kDeskSpan = 260;

final Vector3 _kModelUp = Vector3(0, 0, 1);

/// ASMR crafting: the object's faces are dealt into 2, 3, or 4 groups.
/// Orbit the model, open a group, and cut its blueprint out of one sheet.
/// A piece cut close enough flies onto those faces, until every face is
/// filled. The dice deals the groups again. The view behind the active one
/// stays in sight, faded and blurred.
class AsmrView extends StatefulWidget {
  const AsmrView({
    super.key,
    this.settings,
    this.sessionFile,
    this.theme,
    this.random,
    this.groupCount,
    this.objectId,
  });

  /// Saved DevTools values. Null uses the file in the home directory.
  final AsmrDevSettings? settings;

  /// Where Save and Load keep the desk. Null uses `~/.flatmates/asmr_session.json`.
  final File? sessionFile;

  /// Colors for this view. Null uses `~/.flatmates/asmr_theme.json`.
  final AsmrTheme? theme;

  /// Deals the groups. Null starts a new one. Tests pass a seeded one.
  final math.Random? random;

  /// Test override for the number of groups. Null uses 3/2/1 faces on
  /// the cube and a random count of 2, 3, or 4 on other objects.
  final int? groupCount;

  /// Which object to open on. Null is the cube.
  final String? objectId;

  @override
  State<AsmrView> createState() => _AsmrViewState();
}

class _HoloEdge {
  _HoloEdge(this.edge);

  AsmrNetEdge edge;
  double opacity = 0;
  double target = 1;

  /// The judged colors it eases from and to. Null is not cut.
  Color? _from;
  Color? _to;
  double fade = 1;

  void judge(Color? color) {
    if (color == _to) return;
    _from = this.color;
    _to = color;
    fade = 0;
  }

  /// The judged color as drawn, or null once it has eased back to uncut.
  Color? get color {
    if (fade >= 1 || _from == _to) return _to;
    const plain = Color(0xFFFFFFFF);
    return Color.lerp(
      _from ?? plain,
      _to ?? plain,
      Curves.easeOut.transform(fade),
    );
  }
}

enum _Drag {
  none,
  submit,
  orbit,
  pan,
  marquee,
  cut,
  straight,
  scissors,
  circle,
  dial,
  place,
  move,
  rotate,
  pieceBox,
  deskPan,
  edgeSlide,
  edgeTurn,
}

/// Where a piece was when Select picked it up.
class _Held {
  _Held(this.id, this.position, this.angle);

  final String id;
  final Offset position;
  final double angle;
}

/// Desk paper, the paper on the model, and the hologram it was cut against,
/// for one undo step.
class _CraftStep {
  _CraftStep({
    required this.desk,
    required this.groups,
    required this.picks,
    required this.nextSheet,
    required this.selectedIds,
    required this.slots,
    required this.objectId,
    required this.placing,
  });

  final List<AsmrPiece> desk;
  final List<AsmrGroup> groups;
  final List<HologramPick> picks;
  final int nextSheet;
  final Set<String> selectedIds;
  final List<AsmrPiece?> slots;
  final String objectId;
  final bool placing;
}

/// A piece easing from [from] back to [to], slow at both ends.
class _Warp {
  _Warp({
    required this.id,
    required this.from,
    required this.to,
    required this.fromAngle,
    required this.toAngle,
  });

  final String id;
  final Offset from;
  final Offset to;
  final double fromAngle;
  final double toAngle;
  double t = 0;
}

class _AsmrViewState extends State<AsmrView>
    with SingleTickerProviderStateMixin {
  late FoldedModel _model;
  late List<List<FaceNeighbor?>> _adjacency;
  late AsmrObject _object;
  late final math.Random _random;
  final PapercutCamera _camera = PapercutCamera();
  final HologramSelection _selection = HologramSelection();
  final AsmrPaperTiles _tiles = AsmrPaperTiles();
  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Size _viewport = Size.zero;
  double _homeCameraHalfHeight = 1;
  bool _posed = false;

  bool _in3d = true;
  double _modeProgress = 1;
  double get _blend => Curves.easeInOutCubic.transform(_modeProgress);

  final Map<int, double> _faceFill = {};
  AsmrNet _net = AsmrNet.empty;
  final Map<String, _HoloEdge> _holoEdges = {};

  /// The one desk every group cuts from. It starts as a single sheet.
  final List<AsmrPiece> _desk = [];
  final List<AsmrGroup> _groups = [];

  /// The group of the selected faces, whose blueprint the desk shows.
  AsmrGroup? _group;

  /// Group whose desk state is currently suspended or visible. Hovering the
  /// model can preview another group without discarding this workspace.
  AsmrGroup? _deskGroup;

  List<AsmrPiece> get _pieces =>
      _group?.editing == true ? _group!.draft : _desk;

  /// Paper on the model, landed or still flying there.
  Iterable<AsmrPiece> get _boundPieces => [
    for (final group in _groups) ...group.bound,
  ];

  /// Pieces flying from the desk onto the model.
  final List<AsmrFlight> _flights = [];
  final AsmrJudge _judge = AsmrJudge();
  final WorkviewDoubleTap _doubleTap = WorkviewDoubleTap();

  /// Scrap kept off the desk.
  final List<AsmrPiece?> _slots = List.filled(kAsmrSlots, null);
  final List<GlobalKey> _slotKeys = [
    for (var i = 0; i < kAsmrSlots; i++) GlobalKey(),
  ];
  Offset _deskOrigin = Offset.zero;
  double _deskScale = 2.5;

  /// The desk's turn on screen, in radians, clockwise. Only the scissors turn it.
  double _deskAngle = 0;
  _DeskTool _deskTool = _DeskTool.exacto;
  _ModelTool _modelTool = _ModelTool.orbit;
  int? _hoverFace;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  final Set<String> _selectedIds = {};
  Set<String>? _pieceBoxHome;
  final Set<String> _moveIds = {};

  /// The slot or trash the dragged pieces are over, or null.
  int? _bin;
  final GlobalKey _trashKey = GlobalKey();
  double _selectedOutline = 0;
  final Map<String, double> _flash = {};
  int _nextSheet = 0;

  Map<int, double> _coverage = {};
  bool _complete = false;
  double _completeShown = 0;
  double _clock = 0;

  final Map<int, Offset> _pointers = {};
  PointerDeviceKind _lastKind = PointerDeviceKind.touch;
  Offset? _hover;
  _Drag _drag = _Drag.none;
  Offset _dragStart = Offset.zero;
  Duration _dragStartTime = Duration.zero;
  bool _dragMoved = false;
  double _lastSpan = 0;
  double _lastFingerAngle = 0;
  bool _placingRotate = false;
  Offset _lastFocal = Offset.zero;
  Offset _lastDesk = Offset.zero;
  double _rotateFrom = 0;
  double _rotateBase = 0;

  /// Desk point the rotate handle hinges on: the center of the outline
  /// edge it sits across from, held for the whole drag.
  Offset _rotatePivot = Offset.zero;

  /// Pose of the piece Select is holding, so a scrub can put it back.
  final List<_Held> _held = [];
  final List<_Warp> _warps = [];

  final List<_CraftStep> _undoStack = [];
  final List<_CraftStep> _redoStack = [];

  /// Desk state at the start of a move or turn, committed if the piece changed.
  _CraftStep? _gestureBefore;

  /// Faces the marquee started from, restored if that drag is scrubbed away.
  List<HologramPick>? _marqueeHome;

  /// Straight-edge pose at the start of a slide or turn.
  bool _edgeGrabbed = false;
  Offset _edgeHomeAnchor = Offset.zero;
  double _edgeHomeAngle = 0;

  final Map<int, AsmrScrub> _scrubs = {};
  final AsmrScrub _focalScrub = AsmrScrub();

  late final AsmrDevSettings _settings = widget.settings ?? AsmrDevSettings();
  AsmrDevSettings? _ownedSettings;
  late final AsmrTheme _theme = widget.theme ?? AsmrTheme();
  AsmrTheme? _ownedTheme;
  bool _devToolsOpen = false;

  /// The blade's samples, before curve smoothing.
  List<Offset>? _rawStroke;
  List<Offset>? _stroke;

  /// The straight cut under way, in desk units. The segment sets the line;
  /// the cut runs along it through each piece it touches.
  Offset? _segmentStart;
  Offset? _segmentEnd;
  List<List<Offset>> _segmentReach = const [];

  /// The straight edge, held to the screen. It stays out while other tools
  /// are used, until its toolbar button is toggled off.
  AsmrStraightEdge? _edge;
  bool _edgeOn = false;
  double _edgeShown = 0;

  /// +1 or -1: the side of the straight edge it flies out to, and in from.
  int _edgeFlySide = 1;
  double _edgeTurnFrom = 0;
  double _edgeTurnBase = 0;
  Offset _edgePivot = Offset.zero;

  /// Screen pixels the finger has travelled in the scissors drag under way.
  double? _scissorDrag;

  /// Where an unfinished scissors cut stopped inside the paper, on the desk.
  /// While it is set the blade is stuck there: the desk only turns.
  Offset? _scissorEnd;

  /// An edge lined up by a tap, but not cut yet. Panning releases the aim.
  Offset? _scissorAim;
  double _advanceAngleFrom = 0;
  double _advanceAngleTarget = 0;
  bool _advanceTracksCircle = true;

  /// The desk sliding the end of the last scissors cut back to the blade.
  Offset _advanceFrom = Offset.zero;
  Offset _advanceTarget = Offset.zero;
  double _advanceT = 1;

  /// A latched pre-cut candidate keeps the orbit steady while nearest edges
  /// change on screen. New pans can choose another edge after it finishes.
  Offset _aimOrbitPivot = Offset.zero;
  double _aimOrbitFrom = 0;
  double _aimOrbitTo = 0;
  double _aimOrbitT = 1;

  /// The candidate travels around the reticle at its starting screen radius.
  /// This preserves the visible gap even through a pitched tool camera.
  double _aimOrbitGap = 0;
  double _aimOrbitScreenFrom = 0;
  double _aimOrbitScreenTurn = 0;
  Offset _aimOrbitScreenShift = Offset.zero;
  Offset _aimOrbitExpectedScreen = Offset.zero;

  /// The performed cut's endpoint on the desk. Project it through the moving
  /// camera so the circle stays on the paper throughout the advance.
  Offset? _advanceEndpoint;
  AsmrToolCamera _toolCamera = const AsmrToolCamera();
  AsmrToolCamera _cameraFrom = const AsmrToolCamera();
  AsmrToolCamera _cameraTarget = const AsmrToolCamera();
  double _cameraT = 1;

  /// The turn dial's knob, in screen pixels from the middle of its bar.
  double _knob = 0;

  /// Where the finger took hold of the knob, and where the knob was then.
  double _knobGrab = 0;
  double _knobBase = 0;

  /// The knob easing back to the middle after it is let go.
  double _knobReturnFrom = 0;
  double _knobReturnT = 1;

  /// Radians per second the paper is turning by itself, from a knob held in
  /// an end of the bar, or slowing after it is let go.
  double _spinSpeed = 0;

  /// The pip the knob last passed, for a tick as it passes the next.
  int _knobPip = 0;

  /// Once vertical intent is clear, later sideways drift cannot steal a cut.
  bool _circleCut = false;

  /// A cutting gesture may start anywhere above the lined-up reticle.
  bool _cutFromAbove = false;

  /// Rotation belongs to a grab on the circle; other above-control swipes
  /// retain their existing vertical-cut / horizontal-pan behavior.
  bool _circleCanTurn = false;

  /// Sliding the paper under a blueprint held in the middle of the screen,
  /// before cutting.
  bool _placing = false;
  double _placingSince = 0;
  double _placementGlow = 0;
  int? _placementGlowGroup;

  /// The 3D selection before the last tap, put back when that tap turns out
  /// to be the first of a double-tap.
  List<HologramPick>? _tapHome;

  /// The side of the straight edge the exacto cut under way keeps to.
  int? _knifeSide;
  Offset? _tipDesk;
  Offset? _finger;
  double _tickDistance = 0;

  @override
  void initState() {
    super.initState();
    if (widget.settings == null) _ownedSettings = _settings;
    _settings.addListener(_onDevSettings);
    _settings.load();
    if (widget.theme == null) _ownedTheme = _theme;
    _theme.addListener(_onTheme);
    _theme.load();
    _camera.setFocal(PapercutCamera.perspectiveFocalMm);
    _random = widget.random ?? math.Random();
    _useObject(
      asmrObjectById(widget.objectId ?? kAsmrCubeId) ?? asmrObjects().first,
    );
    _dealGroups();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _settings.removeListener(_onDevSettings);
    _ownedSettings?.dispose();
    _theme.removeListener(_onTheme);
    _ownedTheme?.dispose();
    _ticker.dispose();
    _camera.dispose();
    _tiles.dispose();
    super.dispose();
  }

  void _onDevSettings() {
    final raw = _rawStroke;
    if (raw != null) _stroke = _smoothed(raw);
    if (mounted) setState(() {});
  }

  AsmrPaper get _activePaper => _theme.paperMaterial;

  void _onTheme() {
    final paper = _activePaper;
    for (var i = 0; i < _desk.length; i++) {
      if (_desk[i].paper.id != paper.id) {
        _desk[i] = _desk[i].copyWith(paper: paper);
      }
    }
    for (var i = 0; i < _slots.length; i++) {
      final piece = _slots[i];
      if (piece != null && piece.paper.id != paper.id) {
        _slots[i] = piece.copyWith(paper: paper);
      }
    }
    if (mounted) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Layout and camera
  // -------------------------------------------------------------------------

  void _onLayout(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    if (!_posed && size.width > 2 && size.height > 2) {
      _posed = true;
      _deskOrigin = Offset(size.width / 2, size.height / 2);
      _deskScale = size.shortestSide / _kDeskSpan;
      _frameModel();
    }
  }

  /// Puts the camera on the opening view of [_model].
  void _frameModel() {
    if (_viewport.width < 2 || _viewport.height < 2) return;
    final center = _model.center;
    final half = _camera
        .frameSphere(center, _model.radius * 2.2, _viewport)
        .halfHeight;
    _homeCameraHalfHeight = half;
    final pose =
        CameraPose(
          lookAt: Offset(center.x, center.y),
          lookAtZ: center.z,
          halfHeight: half,
        ).withAngles(
          _camera.anglesAlong(_turntableDirection(-1.0, 0.5), up: _kModelUp),
        );
    _camera.beginFly(pose);
    _camera.setFly(1);
    _refreshHover();
  }

  void _useObject(AsmrObject object) {
    _object = object;
    _model = object.model;
    _adjacency = faceAdjacency(_model);
    _faceFill.removeWhere((face, _) => face < 0 || face >= _model.faces.length);
    final hover = _hoverFace;
    if (hover != null && (hover < 0 || hover >= _model.faces.length)) {
      _hoverFace = null;
    }
  }

  Vector3 _turntableDirection(double turn, double tilt) => Vector3(
    math.cos(tilt) * math.cos(turn),
    math.cos(tilt) * math.sin(turn),
    math.sin(tilt),
  );

  void _turntable(double dTurn, double dTilt) {
    final n = _camera.viewDirection;
    final turn = math.atan2(n.y, n.x) + dTurn;
    final tilt = (math.asin(n.z.clamp(-1.0, 1.0)) + dTilt).clamp(
      -_kMaxTilt,
      _kMaxTilt,
    );
    _camera.orbitTo(_turntableDirection(turn, tilt), up: _kModelUp);
  }

  int? _faceAt(Offset screen) {
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return null;
    return pickFace(_model, ray.origin, ray.direction)?.face;
  }

  bool get _aimsWithCursor =>
      _lastKind == PointerDeviceKind.mouse ||
      _lastKind == PointerDeviceKind.trackpad;

  Offset get _center => Offset(_viewport.width / 2, _viewport.height / 2);

  Offset? get _aim => _aimsWithCursor ? _hover : _center;

  bool get _showBlueprintReticle =>
      _settings.blueprintReticle && _hoverGroup != null;

  AsmrGroup? get _hoverGroup =>
      _hoverFace == null ? null : _groupOf(_hoverFace!);

  /// The face under the reticle, used to preview its whole group.
  void _refreshHover() {
    if (!_in3d) {
      _hoverFace = null;
      return;
    }
    final aim = _aim;
    _hoverFace = aim == null ? null : _faceAt(aim);
    final group = _hoverGroup;
    if (group != null && !identical(group, _group)) {
      _selection.replace(group.picks);
      _rebuildNet();
    }
  }

  List<Offset>? _screenRing(int face) {
    final ring = <Offset>[];
    for (final point in _model.faces[face].worldRing()) {
      final screen = _camera.camera.projectToScreen(point, _viewport);
      if (screen == null) return null;
      ring.add(screen);
    }
    return ring;
  }

  /// Replaces the hologram with the faces the marquee takes.
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
    )..removeWhere((face) => _groupOf(face) != null);
    int? prefer;
    var best = double.infinity;
    final middle = rect.center;
    for (final face in hits) {
      final ring = _screenRing(face);
      if (ring == null || ring.isEmpty) continue;
      var center = Offset.zero;
      for (final point in ring) {
        center += point;
      }
      center = center / ring.length.toDouble();
      final distance = (center - middle).distance;
      if (distance < best) {
        best = distance;
        prefer = face;
      }
    }
    if (_selection.replace(hologramPicks(hits, _adjacency, prefer: prefer))) {
      _rebuildNet();
    }
  }

  // -------------------------------------------------------------------------
  // Hologram
  // -------------------------------------------------------------------------

  /// Lays out the hologram of the selection. Faces that make up a group
  /// take that group's layout, so its paper lines up again.
  void _rebuildNet() {
    final group = groupOfFaces(_groups, _selection.faces);
    if (group != null) _selection.replace(group.picks);
    if (!identical(group, _group)) {
      _group = group;
      if (!_in3d) {
        _selectedIds.clear();
        _held.clear();
        _moveIds.clear();
      }
    }
    _net = group?.net ?? unfoldSelection(_model, _adjacency, _selection.picks);
    final keys = <String>{};
    for (final edge in _net.edges) {
      keys.add(edge.key);
      final held = _holoEdges[edge.key];
      if (held == null) {
        _holoEdges[edge.key] = _HoloEdge(edge);
      } else {
        held
          ..edge = edge
          ..target = 1;
      }
    }
    for (final entry in _holoEdges.entries) {
      if (!keys.contains(entry.key)) entry.value.target = 0;
    }
    _rejudge();
  }

  /// The group [face] belongs to, if any. A face is in one group at most.
  AsmrGroup? _groupOf(int face) {
    for (final group in _groups) {
      if (group.faces.contains(face)) return group;
    }
    return null;
  }

  /// Holds the blueprint still in the middle of the screen while the paper
  /// is slid under it. A tap puts it down and picks up the scissors.
  void _beginPlacing() {
    _aimOrbitT = 1;
    _deskGroup = _group;
    _placing = true;
    _placingSince = _clock;
    _settleAdvance();
    _scissorEnd = null;
    _scissorAim = null;
    _scissorDrag = null;
    _selectedIds.clear();
    _knob = 0;
    _knobReturnT = 1;
    _spinSpeed = 0;
    if (_viewport.width < 2 || _viewport.height < 2) return;
    final bounds = _net.isEmpty ? Rect.zero : _net.bounds;
    _deskAngle = 0;
    _deskScale = [
      _viewport.shortestSide / _kDeskSpan,
      if (bounds.width > 0) _kPlaceFill * _viewport.width / bounds.width,
      if (bounds.height > 0) _kPlaceFill * _viewport.height / bounds.height,
    ].reduce(math.min);
    _deskOrigin = _center - bounds.center * _deskScale;
  }

  void _endPlacing() {
    final group = _group;
    if (group == null || _desk.isEmpty) return;
    _pushUndo();
    for (var i = 0; i < _desk.length; i++) {
      _desk[i] = _desk[i].affixedTo(group.letter);
    }
    _placementGlow = 1;
    _placementGlowGroup = group.letter;
    _placing = false;
    _setDeskTool(_DeskTool.scissors);
    _rejudge();
    HapticFeedback.mediumImpact();
  }

  /// Rotate the paper beneath the fixed blueprint around the placement center.
  void _rotatePlacement(double radians) {
    final pivot = _toDesk(_center);
    for (var i = 0; i < _desk.length; i++) {
      final piece = _desk[i];
      _desk[i] = piece.turnedAbout(piece.angle + radians, pivot);
    }
  }

  /// Slides every piece on the desk by [delta] desk units, under the blueprint.
  void _slidePaper(Offset delta) {
    if (delta == Offset.zero) return;
    for (var i = 0; i < _desk.length; i++) {
      _desk[i] = _desk[i].copyWith(position: _desk[i].position + delta);
    }
  }

  /// Judges the blueprint edges again where the desk paper changed, and
  /// eases each changed edge to its new color.
  void _rejudge() {
    final pieces = _group?.editing == true
        ? _pieces
        : [..._desk, ...?_group?.bound];
    _refreshCoverage();
    for (final key in _judge.update(_net, pieces)) {
      _holoEdges[key]?.judge(_judge.of(key)?.color);
    }
  }

  void _tapGroup(AsmrGroup group) => setState(() => _openGroup(group));

  /// Opens [group] on the desk, or goes back to 3D when it is the group
  /// already open there.
  void _openGroup(AsmrGroup group) {
    if (!_in3d && identical(group, _group)) {
      _setMode(true);
      return;
    }
    _selection.replace(group.picks);
    _rebuildNet();
    if (_in3d) {
      _setMode(false);
    } else {
      _prepareGroupDesk();
    }
  }

  /// Submitted paper opens directly for editing, without the shared leftovers.
  void _prepareGroupDesk() {
    final group = _group;
    if (group == null) return;
    if (group.anchored || group.editing) {
      final lifting = !group.editing && group.anchored;
      if (lifting) {
        _pushUndo();
        group.draft.addAll(group.bound.map((piece) => piece.unbound()));
        group.bound.clear();
      }
      if (!group.editing || !identical(_deskGroup, group)) {
        _beginPlacing();
        _placing = false;
        group.editing = true;
        _setDeskTool(_DeskTool.select);
        _rejudge();
      }
    } else if (!identical(_deskGroup, group)) {
      _beginPlacing();
    }
  }

  /// Sending is a deliberate action between cuts. Switching away from the
  /// scissors releases their embedded endpoint before the player submits.
  bool get _canOfferPaper =>
      !_in3d &&
      !_placing &&
      _group != null &&
      (_drag == _Drag.none ||
          _drag == _Drag.submit ||
          _drag == _Drag.deskPan ||
          _drag == _Drag.pan) &&
      !_pinned &&
      _stroke == null &&
      _segmentStart == null &&
      _scissorDrag == null &&
      _advanceT >= 1 &&
      _flights.isEmpty;

  List<AsmrPiece> get _sendablePieces => [
    for (final piece in _pieces)
      if (asmrSubmissionQuality(piece.inBlueprintSpace(_group!.letter), _net) >=
          0.5)
        piece,
  ];

  bool get _showSendPaper => _canOfferPaper && _sendablePieces.isNotEmpty;

  bool get _canSendPaper =>
      _showSendPaper && (_drag == _Drag.none || _drag == _Drag.submit);

  /// Object hull centroid in desk space, projected through the tool camera.
  Offset? get _sendPaperAt {
    if (_in3d || _placing || _net.faces.isEmpty) return null;
    final host = _blueprintHost;
    final stamp = host?.blueprintFor(_group!.letter);
    return _toScreen(
      host == null || stamp == null
          ? _net.hullCentroid
          : host.toDesk(stamp.toPaper(_net.hullCentroid)),
    );
  }

  bool get _hasAffixedBlueprint =>
      !_placing &&
      _group != null &&
      _pieces.any((piece) => piece.blueprintFor(_group!.letter) != null);

  /// Keep the command on the most complete marked fragment, rather than on
  /// the empty frame that remains after cutting a piece free.
  AsmrPiece? get _blueprintHost {
    final group = _group;
    if (group == null) return null;
    AsmrPiece? best;
    var quality = -1.0;
    for (final piece in _pieces) {
      if (piece.blueprintFor(group.letter) == null) continue;
      final q = asmrSubmissionQuality(
        piece.inBlueprintSpace(group.letter),
        _net,
      );
      if (q > quality || (q == quality && piece.area > (best?.area ?? 0))) {
        best = piece;
        quality = q;
      }
    }
    return best;
  }

  bool _aimsAtSendPaper(Offset aim) {
    final button = _sendPaperAt;
    return button != null && (button - aim).distance <= 24;
  }

  void _sendPaper() {
    if (!_canSendPaper) return;
    final candidates = _sendablePieces;
    final group = _group!;
    _pushUndo();
    final deskToScreen = _deskToScreen;
    for (final piece in candidates) {
      final onModel = piece
          .inBlueprintSpace(group.letter)
          .copyWith(binding: group.net);
      _pieces.remove(piece);
      _selectedIds.remove(piece.id);
      group.bound.add(onModel);
      _flights.add(
        AsmrFlight(piece: onModel, from: deskToScreen.multiplied(piece.pose)),
      );
    }
    _doubleTap.reset();
    _rejudge();
    HapticFeedback.heavyImpact();
  }

  /// Whether landed paper covers every face of the open group.
  bool get _groupFilled {
    final group = _group;
    if (group == null) return false;
    return group.faces.every((f) => (_coverage[f] ?? 0) >= kAsmrFilled);
  }

  /// Desk units to screen pixels, pitched when the scissors' lens is.
  Matrix4 get _deskToScreen {
    final pitched = _lens.deskMatrix(
      origin: _deskOrigin,
      scale: _deskScale,
      angle: _deskAngle,
    );
    if (pitched != null) return Matrix4.fromFloat64List(pitched);
    return Matrix4.translationValues(_deskOrigin.dx, _deskOrigin.dy, 0)
      ..rotateZ(_deskAngle)
      ..scaleByVector3(Vector3(_deskScale, _deskScale, 1));
  }

  // -------------------------------------------------------------------------
  // Animation
  // -------------------------------------------------------------------------

  void _onTick(Duration elapsed) {
    final dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(0.0, 0.05);
    _lastTick = elapsed;
    _clock += dt;
    var changed = false;
    final cameraTarget = (_placing || _in3d)
        ? AsmrToolCamera(lensMm: _settings.lensMm)
        : _deskTool.camera(_settings);
    if (cameraTarget != _cameraTarget) {
      _cameraFrom = _toolCamera;
      _cameraTarget = cameraTarget;
      _cameraT = 0;
    }
    if (_cameraT < 1) {
      _cameraT = math.min(1, _cameraT + dt / AsmrToolCamera.transitionSeconds);
      _toolCamera = AsmrToolCamera.lerp(
        _cameraFrom,
        _cameraTarget,
        Curves.easeInOutCubic.transform(_cameraT),
      );
      changed = true;
    }

    double step(double value, double target, Duration over) {
      if (value == target) return value;
      final delta = dt * 1e6 / over.inMicroseconds;
      changed = true;
      return value < target
          ? math.min(target, value + delta)
          : math.max(target, value - delta);
    }

    _modeProgress = step(_modeProgress, _in3d ? 1 : 0, _kModeDuration);

    final hoveredFaces = _hoverGroup?.faces ?? const <int>{};
    for (var f = 0; f < _model.faces.length; f++) {
      final target = hoveredFaces.contains(f) ? 1.0 : 0.0;
      _faceFill[f] = step(_faceFill[f] ?? 0, target, _kPreselectFade);
    }

    final gone = <String>[];
    for (final entry in _holoEdges.entries) {
      final edge = entry.value;
      edge.opacity = step(edge.opacity, edge.target, _kEdgeFade);
      if (edge.opacity == 0 && edge.target == 0) gone.add(entry.key);
    }
    gone.forEach(_holoEdges.remove);
    for (final edge in _holoEdges.values) {
      edge.fade = step(edge.fade, 1, _kJudgeFade);
    }

    if (_flights.isNotEmpty) {
      changed = true;
      final before = _flights.length;
      _flights.removeWhere((flight) => flight.advance(dt));
      if (_flights.length < before) {
        _refreshCoverage();
        if (!_in3d && _groupFilled) {
          final group = _group!;
          if (group.editing) {
            _desk.addAll(group.draft.map((piece) => piece.unbound()));
            group.draft.clear();
            group.editing = false;
          }
          _setMode(true);
        }
      }
    }

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
    _placementGlow = step(_placementGlow, 0, const Duration(milliseconds: 300));
    _edgeShown = step(_edgeShown, _edgeOn ? 1 : 0, _kStraightEdgeFly);
    if (_advanceT < 1) {
      _advanceT = math.min(
        1,
        _advanceT + dt * 1e6 / _kScissorAdvance.inMicroseconds,
      );
      _deskAngle =
          _advanceAngleFrom +
          (_advanceAngleTarget - _advanceAngleFrom) *
              Curves.easeInOutCubic.transform(_advanceT);
      _deskOrigin = Offset.lerp(
        _advanceFrom,
        _advanceTarget,
        Curves.easeInOutCubic.transform(_advanceT),
      )!;
      changed = true;
    }

    if (_aimOrbitT < 1) {
      if (!_scissorAiming) {
        _aimOrbitT = 1;
      } else {
        // Keep deliberate panning/zoom additive, while the orbit itself
        // preserves the visible reticle-to-edge radius. Finish ahead of the
        // scissors, rather than leaving the reticle on the paper's inside.
        _aimOrbitScreenShift +=
            _toScreen(_aimOrbitPivot) - _aimOrbitExpectedScreen;
        _aimOrbitT = math.min(
          1,
          _aimOrbitT + dt / AsmrToolCamera.transitionSeconds,
        );
        final t = Curves.easeInOutCubic.transform(_aimOrbitT);
        final bearing = _aimOrbitScreenFrom + _aimOrbitScreenTurn * t;
        final anchor =
            _scissorLine.$1 +
            Offset(math.cos(bearing), math.sin(bearing)) * _aimOrbitGap +
            _aimOrbitScreenShift;
        _deskAngle = _aimOrbitFrom + (_aimOrbitTo - _aimOrbitFrom) * t;
        _deskOrigin =
            _lens.unproject(anchor) -
            _spin(_aimOrbitPivot, _deskAngle) * _deskScale;
        _aimOrbitExpectedScreen = anchor;
        changed = true;
      }
    }

    final dial = _dial;
    final held = _drag == _Drag.dial;
    final cruising =
        held && _settings.dialCruise && _scissoring && dial.inEnd(_knob);
    final targetSpeed = cruising
        ? dial.cruiseSign(_knob) * kAsmrDialCruiseSpeed
        : 0.0;
    if (_spinSpeed != 0 || targetSpeed != 0) {
      final settle = held ? _kCruiseTake : _kCruiseRelease;
      _spinSpeed += (targetSpeed - _spinSpeed) * (1 - math.exp(-dt / settle));
      if (targetSpeed == 0 && _spinSpeed.abs() < 0.01) _spinSpeed = 0;
      if (_scissoring) {
        _turnDesk(_spinSpeed * dt, _scissorLine.$1);
      } else {
        _spinSpeed = 0;
      }
      changed = true;
    }
    if (!held && _knobReturnT < 1) {
      _knobReturnT = math.min(
        1,
        _knobReturnT + dt * 1e6 / _kKnobReturn.inMicroseconds,
      );
      _knob = _knobReturnFrom * (1 - Curves.easeIn.transform(_knobReturnT));
      changed = true;
    }

    if (_warps.isNotEmpty) {
      final span = _kWarp.inMicroseconds / 1e6;
      _warps.removeWhere((warp) {
        warp.t = math.min(1, warp.t + dt / span);
        final i = _pieces.indexWhere((p) => p.id == warp.id);
        if (i < 0) return true;
        final u = Curves.easeInOutCubic.transform(warp.t);
        var delta = warp.toAngle - warp.fromAngle;
        while (delta > math.pi) {
          delta -= math.pi * 2;
        }
        while (delta < -math.pi) {
          delta += math.pi * 2;
        }
        _pieces[i] = _pieces[i].copyWith(
          position: Offset.lerp(warp.from, warp.to, u)!,
          angle: warp.fromAngle + delta * u,
        );
        changed = true;
        return warp.t >= 1;
      });
    }
    if (changed || _complete) setState(() {});
  }

  void _toggleMode() => setState(_toggleWorkspace);

  void _toggleWorkspace() {
    final saved = _deskGroup;
    if (_in3d && saved != null && _groups.contains(saved)) {
      _selection.replace(saved.picks);
      _rebuildNet();
    }
    _setMode(!_in3d);
  }

  /// Releases pointer gestures while keeping the workspace, placement state,
  /// camera, and embedded scissors endpoint when the same group is resumed.
  void _setMode(bool in3d) {
    if (in3d == _in3d || (!in3d && !_canOpenDesk)) return;
    _in3d = in3d;
    _aimOrbitT = 1;
    _rawStroke = null;
    _stroke = null;
    _knifeSide = null;
    _segmentStart = null;
    _segmentEnd = null;
    _segmentReach = const [];
    _scissorDrag = null;
    _circleCut = false;
    _releaseKnob();
    _spinSpeed = 0;
    _tipDesk = null;
    _finger = null;
    _marqueeStart = null;
    _marqueeEnd = null;
    _marqueeHome = null;
    _pieceBoxHome = null;
    _held.clear();
    _moveIds.clear();
    _edgeGrabbed = false;
    _gestureBefore = null;
    _bin = null;
    _drag = _Drag.none;
    _doubleTap.reset();
    if (!_in3d) _prepareGroupDesk();
    _refreshHover();
    HapticFeedback.selectionClick();
  }

  /// The desk opens on a dealt group.
  bool get _canOpenDesk => groupOfFaces(_groups, _selection.faces) != null;

  /// Lets go of the turn dial; its knob eases back to the middle.
  void _releaseKnob() {
    _knobReturnFrom = _knob;
    _knobReturnT = _knob == 0 ? 1 : 0;
  }

  // -------------------------------------------------------------------------
  // Desk geometry
  // -------------------------------------------------------------------------

  static Offset _spin(Offset v, double angle) {
    if (angle == 0) return v;
    final c = math.cos(angle);
    final s = math.sin(angle);
    return Offset(c * v.dx - s * v.dy, s * v.dx + c * v.dy);
  }

  Offset _flatToDesk(Offset flat) =>
      _spin((flat - _deskOrigin) / _deskScale, -_deskAngle);

  Offset _deskToFlat(Offset desk) =>
      _deskOrigin + _spin(desk, _deskAngle) * _deskScale;

  /// The scissors' camera. Overhead unless the scissors are the tool.
  AsmrCutLens get _lens {
    if (_viewport.height < 2 || _toolCamera.pitch < 1e-4) {
      return AsmrCutLens.overhead;
    }
    return AsmrCutLens(
      pivot: _scissorLine.$1,
      focal: AsmrCutLens.focalPixels(_toolCamera.lensMm, _viewport.height),
      elevation: AsmrCutLens.elevationFor(_toolCamera.pitch),
    );
  }

  Offset _toDesk(Offset screen) => _flatToDesk(_lens.unproject(screen));

  Offset _toScreen(Offset desk) => _lens.project(_deskToFlat(desk));

  AsmrPiece? get _selected {
    if (_selectedIds.length != 1) return null;
    final id = _selectedIds.single;
    for (final piece in _pieces) {
      if (piece.id == id) return piece;
    }
    return null;
  }

  void _keepSelection() {
    _selectedIds.removeWhere((id) => !_pieces.any((piece) => piece.id == id));
  }

  Offset? _handleFor(AsmrPiece piece) {
    final ring = [for (final p in piece.deskRing) _toScreen(p)];
    if (ring.isEmpty) return null;
    var top = ring.first.dy;
    var left = ring.first.dx;
    var right = ring.first.dx;
    for (final p in ring) {
      top = math.min(top, p.dy);
      left = math.min(left, p.dx);
      right = math.max(right, p.dx);
    }
    return Offset((left + right) / 2, top - _kHandleLift);
  }

  AsmrPiece? _pieceAt(Offset desk) {
    for (final piece in _pieces.reversed) {
      if (piece.contains(desk)) return piece;
    }
    return null;
  }

  void _zoomDesk(double factor, Offset focal) {
    if (_pinned) return;
    _settleAdvance();
    final desk = _toDesk(focal);
    _deskScale = (_deskScale * factor).clamp(0.5, 24.0);
    _deskOrigin = _lens.unproject(focal) - _spin(desk, _deskAngle) * _deskScale;
  }

  /// Slides the desk by a screen [delta]. [at] is where the finger is now, so
  /// the paper under the finger stays under it when the view is pitched.
  void _panDesk(Offset delta, {Offset? at}) {
    if (_pinned || delta == Offset.zero) return;
    _settleAdvance();
    _scissorAim = null;
    final focal = at;
    if (focal == null || _lens.isOverhead) {
      _deskOrigin += delta;
    } else {
      final desk = _toDesk(focal - delta);
      _deskOrigin =
          _lens.unproject(focal) - _spin(desk, _deskAngle) * _deskScale;
    }
    _orbitProspectiveCut();
  }

  /// Turns the desk by [turn] radians, clockwise, about the screen point
  /// [pivot], which stays over the same desk point.
  void _turnDesk(double turn, Offset pivot) {
    if (turn.abs() < 1e-9) return;
    _settleAdvance();
    final desk = _toDesk(pivot);
    _deskAngle += turn;
    _deskOrigin = pivot - _spin(desk, _deskAngle) * _deskScale;
  }

  /// The one sheet a craft is cut from, centered under the blueprints.
  AsmrPiece _freshSheet() => AsmrPiece.sheet(
    id: '${_activePaper.id}-${_nextSheet++}',
    paper: _activePaper,
    at: Offset.zero,
  );

  void _replace(AsmrPiece piece) {
    final i = _pieces.indexWhere((p) => p.id == piece.id);
    if (i >= 0) _pieces[i] = piece;
  }

  void _applyCut(AsmrCut cut) {
    _pushUndo();
    _pieces
      ..clear()
      ..addAll(cut.pieces);
    for (final id in cut.freed) {
      _flash[id] = 1;
    }
    _keepSelection();
    if (cut.split) HapticFeedback.mediumImpact();
    _rejudge();
  }

  /// Only paper that has landed counts toward a filled face.
  void _refreshCoverage() {
    _coverage = faceCoverage(_model, _modelPieces);
    final done =
        _coverage.length == _model.faces.length &&
        _coverage.values.every((c) => c >= kAsmrFilled);
    if (done && !_complete) HapticFeedback.heavyImpact();
    _complete = done;
  }

  File get _sessionFile => widget.sessionFile ?? asmrSessionFile();

  void _saveSession() {
    final edge = _edge;
    final pieces = <AsmrPiece>[];
    final pieceGroups = <int?>[];
    for (final piece in _desk) {
      pieces.add(piece);
      pieceGroups.add(null);
    }
    for (final group in _groups) {
      for (final piece in group.bound) {
        pieces.add(piece);
        pieceGroups.add(group.letter);
      }
    }
    AsmrSession(
      picks: _selection.picks,
      pieces: pieces,
      bindings: [
        for (final piece in pieces) picksOfNet(piece.binding ?? AsmrNet.empty),
      ],
      groups: {for (final group in _groups) group.letter: group.picks},
      groupDrafts: {
        for (final group in _groups)
          if (group.editing) group.letter: List.of(group.draft),
      },
      pieceGroups: pieceGroups,
      slots: List.of(_slots),
      objectId: _object.id,
      groupCutsUsed: {
        for (final group in _groups) group.letter: group.cutsUsed,
      },
      deskOrigin: _deskOrigin,
      deskScale: _deskScale,
      deskAngle: _deskAngle,
      in3d: _in3d,
      azimuth: _camera.azimuth,
      elevation: _camera.elevation,
      roll: _camera.roll,
      lookAt: _camera.lookAt,
      lookAtZ: _camera.lookAtZ,
      halfHeight: _camera.framedHalfHeightMm,
      focal: _camera.focalLengthMm,
      straightEdgeOn: _edgeOn,
      straightEdgeAnchor: edge?.anchor ?? _center,
      straightEdgeAngle: edge?.angle ?? 0,
    ).write(_sessionFile);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Saved ${_sessionFile.path}')));
  }

  void _loadSession() {
    final session = AsmrSession.read(_sessionFile);
    if (session == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('No saved desk')));
      return;
    }
    setState(() {
      _pushUndo();
      final id = session.objectId ?? kAsmrCubeId;
      if (id != _object.id) {
        final next = asmrObjectById(id);
        if (next != null) {
          _useObject(next);
          _frameModel();
        }
      }
      final groups = <int, AsmrGroup>{
        for (final entry in session.groups.entries)
          entry.key: AsmrGroup(
            letter: entry.key,
            cutsUsed: session.groupCutsUsed[entry.key] ?? 0,
            draft: List.of(session.groupDrafts[entry.key] ?? const []),
            editing: session.groupDrafts.containsKey(entry.key),
            picks: entry.value,
            net: unfoldSelection(_model, _adjacency, entry.value),
          ),
      };
      _desk.clear();
      _flights.clear();
      for (var i = 0; i < session.pieces.length; i++) {
        final piece = session.pieces[i];
        final binding = session.bindings[i];
        if (binding.isEmpty) {
          _desk.add(piece);
          continue;
        }
        var group = groups[session.pieceGroups[i]];
        if (group == null) {
          final faces = {for (final pick in binding) pick.face};
          group = groupOfFaces(groups.values, faces);
          if (group == null) {
            final letter = nextGroupLetter(groups.values);
            group = groups[letter] = AsmrGroup(
              letter: letter,
              picks: binding,
              net: unfoldSelection(_model, _adjacency, binding),
            );
          }
        }
        group.bound.add(piece.copyWith(binding: group.net));
      }
      for (var i = 0; i < _slots.length; i++) {
        _slots[i] = i < session.slots.length ? session.slots[i] : null;
      }
      if (session.pieces.isEmpty &&
          session.groupDrafts.values.every((draft) => draft.isEmpty) &&
          _slots.every((s) => s == null)) {
        _desk.add(_freshSheet());
      }
      _groups
        ..clear()
        ..addAll(groups.values.toList()..sort((a, b) => a.letter - b.letter));
      _group = null;
      var next = 0;
      for (final piece in [
        ..._desk,
        ..._boundPieces,
        for (final group in _groups) ...group.draft,
        ..._slots.nonNulls,
      ]) {
        final tail = int.tryParse(piece.id.split('-').last);
        if (tail != null && tail >= next) next = tail + 1;
      }
      _nextSheet = next;
      _flash.clear();
      _selection.replace(session.picks);
      _rebuildNet();
      _deskGroup = _group;
      _in3d = session.in3d || _group == null;
      _placing = false;
      _selectedIds.clear();
      _deskOrigin = session.deskOrigin;
      _deskScale = session.deskScale;
      _deskAngle = session.deskAngle;
      _advanceT = 1;
      _scissorEnd = null;
      _scissorAim = null;
      _modeProgress = _in3d ? 1 : 0;
      _camera.setFocal(session.focal);
      _camera.beginFly(
        CameraPose(
          lookAt: session.lookAt,
          lookAtZ: session.lookAtZ,
          halfHeight: session.halfHeight,
          azimuth: session.azimuth,
          elevation: session.elevation,
          roll: session.roll,
        ),
      );
      _camera.setFly(1);
      _edgeOn = session.straightEdgeOn;
      _edgeShown = session.straightEdgeOn ? 1 : 0;
      _edge = session.straightEdgeOn
          ? AsmrStraightEdge(
              anchor: session.straightEdgeAnchor,
              angle: session.straightEdgeAngle,
            )
          : null;
      _refreshCoverage();
      _refreshHover();
    });
  }

  /// Replaces the groups with a new deal of the same object, and clears the
  /// paper. Undo puts the previous deal back.
  void _rollGroups() {
    setState(() {
      _pushUndo();
      _dealGroups();
    });
  }

  /// Loads [id] and deals its faces. Undo returns to the object that was open.
  void _loadObject(String id) {
    final next = asmrObjectById(id);
    if (next == null || next.id == _object.id) return;
    setState(() {
      _pushUndo();
      _useObject(next);
      _dealGroups();
      _frameModel();
    });
  }

  /// Deals [_model]'s faces into groups and lays one fresh sheet.
  void _dealGroups() {
    final parts = _object.id == kAsmrCubeId && widget.groupCount == null
        ? cubeFaceGroups(_adjacency, random: _random)
        : randomFaceGroups(
            _adjacency,
            random: _random,
            count: widget.groupCount,
          );
    _groups
      ..clear()
      ..addAll([
        for (var i = 0; i < parts.length; i++)
          () {
            final picks = hologramPicks(parts[i], _adjacency);
            return AsmrGroup(
              letter: i,
              picks: picks,
              net: unfoldSelection(_model, _adjacency, picks),
            );
          }(),
      ]);
    _group = null;
    _deskGroup = null;
    _selection.replace(const []);
    _net = AsmrNet.empty;
    _holoEdges.clear();
    _desk
      ..clear()
      ..add(_freshSheet());
    for (var i = 0; i < _slots.length; i++) {
      _slots[i] = null;
    }
    _flights.clear();
    _selectedIds.clear();
    _flash.clear();
    _placing = false;
    _in3d = true;
    _modeProgress = 1;
    _scissorEnd = null;
    _scissorAim = null;
    _drag = _Drag.none;
    _dropStroke();
    _marqueeStart = null;
    _marqueeEnd = null;
    _held.clear();
    _moveIds.clear();
    _complete = false;
    _completeShown = 0;
    _refreshCoverage();
  }

  /// Starts the craft over from one fresh sheet, with nothing on the model.
  void _reset() {
    setState(() {
      _pushUndo();
      _desk
        ..clear()
        ..add(_freshSheet());
      _slots.fillRange(0, _slots.length, null);
      for (final group in _groups) {
        group.bound.clear();
        group.draft.clear();
        group.cutsUsed = 0;
        group.editing = false;
      }
      _flights.clear();
      _selectedIds.clear();
      _flash.clear();
      _scissorEnd = null;
      _scissorAim = null;
      _rejudge();
      _refreshCoverage();
    });
  }

  _CraftStep _capture() => _CraftStep(
    desk: List.of(_desk),
    groups: [for (final group in _groups) group.copy()],
    picks: List.of(_selection.picks),
    nextSheet: _nextSheet,
    selectedIds: Set.of(_selectedIds),
    slots: List.of(_slots),
    objectId: _object.id,
    placing: _placing,
  );

  bool _samePieces(List<AsmrPiece> a, List<AsmrPiece> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final p = a[i];
      final q = b[i];
      if (p.id != q.id ||
          p.position != q.position ||
          p.angle != q.angle ||
          p.liberated != q.liberated ||
          p.edgeTone != q.edgeTone ||
          !identical(p.cutEdges, q.cutEdges) ||
          p.ring.length != q.ring.length ||
          p.holes.length != q.holes.length ||
          p.scores.length != q.scores.length ||
          !identical(p.binding, q.binding) ||
          !identical(p.blueprints, q.blueprints) ||
          p.paper != q.paper) {
        return false;
      }
    }
    return true;
  }

  bool _sameGroups(List<AsmrGroup> a, List<AsmrGroup> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].letter != b[i].letter ||
          a[i].cutsUsed != b[i].cutsUsed ||
          a[i].editing != b[i].editing ||
          a[i].faces.length != b[i].faces.length ||
          !a[i].faces.containsAll(b[i].faces) ||
          !_samePieces(a[i].bound, b[i].bound) ||
          !_samePieces(a[i].draft, b[i].draft)) {
        return false;
      }
    }
    return true;
  }

  bool _sameCraft(_CraftStep a, _CraftStep b) {
    if (a.placing != b.placing ||
        a.objectId != b.objectId ||
        a.nextSheet != b.nextSheet ||
        a.picks.length != b.picks.length ||
        !_sameGroups(a.groups, b.groups)) {
      return false;
    }
    for (var i = 0; i < a.picks.length; i++) {
      if (a.picks[i] != b.picks[i]) return false;
    }
    for (var i = 0; i < a.slots.length; i++) {
      if (!identical(a.slots[i], b.slots[i])) return false;
    }
    return _samePieces(a.desk, b.desk);
  }

  void _pushUndo() {
    _undoStack.add(_capture());
    if (_undoStack.length > _kHistoryDepth) _undoStack.removeAt(0);
    _redoStack.clear();
  }

  void _commitGesture() {
    final before = _gestureBefore;
    _gestureBefore = null;
    if (before == null || _sameCraft(before, _capture())) return;
    _undoStack.add(before);
    if (_undoStack.length > _kHistoryDepth) _undoStack.removeAt(0);
    _redoStack.clear();
    _rejudge();
  }

  void _restore(_CraftStep step) {
    _aimOrbitT = 1;
    if (step.objectId != _object.id) {
      final next = asmrObjectById(step.objectId);
      if (next != null) {
        _useObject(next);
        _frameModel();
      }
    }
    _desk
      ..clear()
      ..addAll(step.desk);
    _groups
      ..clear()
      ..addAll([for (final group in step.groups) group.copy()]);
    _group = null;
    _nextSheet = step.nextSheet;
    _slots.setAll(0, step.slots);
    _flights.clear();
    _selection.replace(step.picks);
    _rebuildNet();
    _deskGroup = _group;
    _placing = step.placing;
    _placementGlow = 0;
    if (!_in3d && _group == null) _setMode(true);
    _selectedIds
      ..clear()
      ..addAll(step.selectedIds);
    _keepSelection();
    _flash.clear();
    _warps.clear();
    _held.clear();
    _moveIds.clear();
    _bin = null;
    _pieceBoxHome = null;
    _gestureBefore = null;
    _dropStroke();
    _cancelStraight();
    _scissorDrag = null;
    _scissorEnd = null;
    _scissorAim = null;
    _circleCut = false;
    _marqueeStart = null;
    _marqueeEnd = null;
    _marqueeHome = null;
    if (_drag == _Drag.dial || _drag == _Drag.circle) _releaseKnob();
    _spinSpeed = 0;
    _drag = _Drag.none;
    _refreshCoverage();
  }

  void _undo() {
    if (_undoStack.isEmpty) return;
    setState(() {
      _redoStack.add(_capture());
      _restore(_undoStack.removeLast());
    });
  }

  void _redo() {
    if (_redoStack.isEmpty) return;
    setState(() {
      _undoStack.add(_capture());
      _restore(_redoStack.removeLast());
    });
  }

  // -------------------------------------------------------------------------
  // Exacto
  // -------------------------------------------------------------------------

  Offset _knifeAt(Offset pointer) =>
      _aimsWithCursor ? pointer : pointer + _kKnifeLift;

  /// Where the blade is on screen: under or above the pointer, and kept on
  /// its side of the straight edge, sliding along it when close.
  Offset _bladeAt(Offset pointer) {
    final tip = _knifeAt(pointer);
    final edge = _liveEdge;
    final side = _knifeSide;
    if (edge == null || side == null) return tip;
    return edge.hold(tip, side, snap: kStraightEdgeSnap);
  }

  /// [raw] smoothed by the DevTools amount, then kept off the straight edge,
  /// which smoothing can round a corner into.
  List<Offset> _smoothed(List<Offset> raw) {
    final smooth = smoothToolCurve(raw, _settings.curveSmoothing);
    final edge = _liveEdge;
    final side = _knifeSide;
    if (edge == null || side == null) return smooth;
    return [for (final p in smooth) _toDesk(edge.hold(_toScreen(p), side))];
  }

  void _beginCut(Offset pointer) {
    final edge = _liveEdge;
    _knifeSide = edge?.sideOf(_knifeAt(pointer));
    final tip = _toDesk(_bladeAt(pointer));
    _tipDesk = tip;
    _finger = pointer;
    _rawStroke = [tip];
    _stroke = [tip];
    _tickDistance = 0;
  }

  void _extendCut(Offset pointer) {
    final rawStroke = _rawStroke;
    if (rawStroke == null) return;
    final raw = _toDesk(_bladeAt(pointer));
    final previous = _tipDesk ?? raw;
    final tip = _aimsWithCursor ? raw : Offset.lerp(previous, raw, 0.5)!;
    _tipDesk = tip;
    _finger = pointer;
    final before = rawStroke.length;
    addStrokePoint(rawStroke, tip);
    _stroke = _smoothed(rawStroke);
    final added = rawStroke.length - before;
    if (added <= 0) return;
    if (_pieceAt(tip) != null) {
      _tickDistance += added * kAsmrStrokeSpacing;
      if (_tickDistance >= _kTickEvery) {
        _tickDistance = 0;
        HapticFeedback.selectionClick();
      }
    }
    // Keep the live stroke white; split and color the resulting paper only
    // when the gesture finishes.
  }

  void _endCut() {
    final raw = _rawStroke;
    final stroke = raw == null ? null : _smoothed(raw);
    _rawStroke = null;
    _stroke = null;
    _finger = null;
    _knifeSide = null;
    if (!_aimsWithCursor) _tipDesk = null;
    if (stroke == null || stroke.length < 2) return;
    final cut = cutPieces(_pieces, stroke);
    if (cut != null) _applyCut(cut);
  }

  // -------------------------------------------------------------------------
  // Straight cut
  // -------------------------------------------------------------------------

  void _beginStraight(Offset pointer) {
    final desk = _toDesk(pointer);
    _segmentStart = desk;
    _segmentEnd = desk;
    _segmentReach = const [];
    _stroke = [desk, desk];
  }

  /// How far the straight cut's line runs from its start before the
  /// straight edge stops it, as line parameters.
  (double, double) _straightLimits(Offset start, Offset end) {
    final edge = _liveEdge;
    if (edge == null) return (double.negativeInfinity, double.infinity);
    return edge.lineLimits(_toScreen(start), _toScreen(end));
  }

  void _extendStraight(Offset pointer) {
    final start = _segmentStart;
    if (start == null) return;
    final end = _toDesk(pointer);
    _segmentEnd = end;
    _stroke = [start, end];
    final (lo, hi) = _straightLimits(start, end);
    _segmentReach = straightCutPreview(_pieces, start, end, lo: lo, hi: hi);
  }

  void _cancelStraight() {
    _segmentStart = null;
    _segmentEnd = null;
    _segmentReach = const [];
    _stroke = null;
  }

  void _endStraight() {
    final start = _segmentStart;
    final end = _segmentEnd;
    _cancelStraight();
    if (start == null || end == null || !_dragMoved) return;
    final (lo, hi) = _straightLimits(start, end);
    final cut = cutPiecesAlongLine(_pieces, start, end, lo: lo, hi: hi);
    if (cut != null) _applyCut(cut);
  }

  // -------------------------------------------------------------------------
  // Scissors
  // -------------------------------------------------------------------------

  bool get _scissoring =>
      !_in3d && !_placing && _deskTool == _DeskTool.scissors;

  /// The scissors are stuck in an unfinished cut, so the desk cannot slide.
  bool get _pinned => _scissoring && _scissorEnd != null;

  bool get _scissorAiming =>
      _scissoring &&
      !_pinned &&
      _scissorAim == null &&
      _scissorDrag == null &&
      !(_advanceTracksCircle && _advanceT < 1);

  /// Reveal the cutting controls in the final two thirds of edge alignment.
  /// The circle stays visible as the camera brings the edge underneath it.
  double get _scissorControlsOpacity {
    if (_scissorAim == null || _advanceTracksCircle || _advanceT >= 1) {
      return 1;
    }
    return Curves.easeInOut.transform(
      ((_advanceT - 0.35) / 0.65).clamp(0.0, 1.0),
    );
  }

  List<AsmrScissorAim> get _aimPoints =>
      scissorAimPoints(_pieces, _scissorLine.$1, _toScreen, _toDesk);

  /// An uncommitted start spot may face back toward the viewer. Orbit about
  /// the nearest candidate so the scissors face into that paper boundary.
  void _orbitProspectiveCut() {
    if (!_scissorAiming || _aimOrbitT < 1) return;
    final points = _aimPoints;
    if (points.isEmpty) return;
    final reticle = _scissorLine.$1;
    var nearest = points.first;
    for (final point in points.skip(1)) {
      if ((point.screen - reticle).distanceSquared <
          (nearest.screen - reticle).distanceSquared) {
        nearest = point;
      }
    }
    final target = scissorPreCutOrbitAngle(_deskAngle, nearest.inward);
    if (target == null) return;
    _aimOrbitPivot = nearest.point;
    _aimOrbitFrom = _deskAngle;
    _aimOrbitTo = target;
    final offset = nearest.screen - reticle;
    _aimOrbitGap = offset.distance;
    _aimOrbitScreenFrom = math.atan2(offset.dy, offset.dx);
    final sweep = -math.pi / 2 - _aimOrbitScreenFrom;
    _aimOrbitScreenTurn = math.atan2(math.sin(sweep), math.cos(sweep));
    _aimOrbitScreenShift = Offset.zero;
    _aimOrbitExpectedScreen = nearest.screen;
    _aimOrbitT = 0;
  }

  /// A tap chooses the closest red marker without performing a cut.
  void _lineUpScissors(Offset tap) {
    _aimOrbitT = 1;
    _settleAdvance();
    final points = _aimPoints;
    if (points.isEmpty) return;
    var nearest = points.first;
    for (final point in points.skip(1)) {
      if ((point.screen - tap).distanceSquared <
          (nearest.screen - tap).distanceSquared) {
        nearest = point;
      }
    }
    _scissorAim = nearest.point;
    _advance(
      nearest.point,
      angle: scissorAimAngle(_deskAngle, nearest.edge),
      trackCircle: false,
    );
    HapticFeedback.selectionClick();
  }

  /// The blade on screen: from the middle of the lower half of the screen,
  /// where it starts cutting, up to the middle of the screen.
  (Offset, Offset) get _scissorLine => (
    Offset(_viewport.width / 2, _viewport.height * 0.75 + _kDialDrop),
    _center,
  );

  /// Where the drag under way stops on the blade, on screen. The finger and
  /// the cut travel the same distance, and the cut never passes the tip.
  Offset? get _scissorMark {
    final drag = _scissorDrag;
    if (drag == null || drag <= 0) return null;
    final (from, to) = _scissorLine;
    final reach = (to - from).distance;
    if (reach < 1e-6) return null;
    final length = math.min(drag / _kScissorRatio, reach);
    final endpoint = _scissorEnd ?? _scissorAim;
    final origin = endpoint == null ? from : _toScreen(endpoint);
    return origin + (to - from) / reach * length;
  }

  /// The circle follows the live preview or the performed cut's endpoint
  /// until the camera has brought it back to the horizontal bar.
  Offset get _scissorCircle {
    final mark = _scissorMark;
    if (mark != null) return mark;
    final endpoint = _advanceEndpoint;
    if (_advanceTracksCircle && _advanceT < 1 && endpoint != null) {
      return _toScreen(endpoint);
    }
    return _dial.center + Offset(_knob, 0);
  }

  /// The cut the scissors drag under way would make, on the desk.
  (Offset, Offset)? get _scissorSpan {
    final mark = _scissorMark;
    if (mark == null) return null;
    return (
      _scissorEnd ?? _scissorAim ?? _toDesk(_scissorLine.$1),
      _toDesk(mark),
    );
  }

  int get _cutsRemaining =>
      math.max(0, _settings.scissorCuts - (_group?.cutsUsed ?? 0));

  void _beginScissors() {
    _scissorDrag = 0;
  }

  /// Prefer a clearly vertical drag for cutting and require a deliberate
  /// sideways pull before turning. Both remain locked once chosen. Above
  /// the control, either vertical direction advances the cut as before.
  void _followCircle(Offset pointer) {
    if (_drag == _Drag.dial) {
      _dragKnob(pointer);
      return;
    }
    final delta = pointer - _dragStart;
    final vertical = _cutFromAbove ? delta.dy.abs() : math.max(0.0, -delta.dy);
    final side = delta.dx.abs();
    if (_circleCut) {
      _scissorDrag = vertical;
      return;
    }
    if (vertical > _kScissorMinDrag && vertical > side * 1.15) {
      if (_cutsRemaining == 0) return;
      _beginScissors();
      _drag = _Drag.scissors;
      _circleCut = true;
      _scissorDrag = vertical;
      HapticFeedback.selectionClick();
      return;
    }
    if (side >= _kScissorTurnSlop && side >= vertical) {
      _scissorDrag = null;
      if (_circleCanTurn) {
        _drag = _Drag.dial;
        _dragKnob(pointer);
      } else {
        _drag = _pinned ? _Drag.none : _Drag.deskPan;
        if (!_pinned) _panDesk(delta, at: pointer);
      }
    }
  }

  /// Cuts along the blade. A cut that stops inside the paper leaves the
  /// blade stuck at its end. Either way the desk slides that end back to the
  /// blade's start, ready to go on along the same line.
  void _endScissors() {
    final span = _scissorSpan;
    final drag = _scissorDrag ?? 0;
    _scissorDrag = null;
    if (span == null || drag <= _kScissorMinDrag || _cutsRemaining == 0) return;
    final (from, to) = span;
    final cut = cutPieces(_pieces, [from, to], exact: true);
    if (cut == null) return;
    _applyCut(cut);
    _group?.cutsUsed++;
    _scissorEnd = _pieces.any((piece) => piece.contains(to)) ? to : null;
    _scissorAim = null;
    _advance(to);
  }

  /// Slides the desk until [desk] is under the blade's start.
  void _advance(Offset desk, {double? angle, bool trackCircle = true}) {
    _advanceEndpoint = desk;
    _advanceTracksCircle = trackCircle;
    _advanceAngleFrom = _deskAngle;
    _advanceAngleTarget = angle ?? _deskAngle;
    _advanceFrom = _deskOrigin;
    _advanceTarget =
        _scissorLine.$1 - _spin(desk, _advanceAngleTarget) * _deskScale;
    _advanceT = 0;
  }

  void _settleAdvance() {
    if (_advanceT >= 1) return;
    _advanceT = 1;
    _deskOrigin = _advanceTarget;
    _deskAngle = _advanceAngleTarget;
  }

  /// The turn dial: a bar two thirds of the screen wide, under the blade,
  /// turning the paper about where the blade cuts.
  AsmrTurnDial get _dial {
    final pivot = _scissorLine.$1 - const Offset(0, _kDialDrop);
    return AsmrTurnDial(
      center: pivot + const Offset(0, _kDialDrop),
      halfLength: _viewport.width / 3,
      pivot: pivot,
    );
  }

  void _grabKnob(Offset pointer) {
    _knobReturnT = 1;
    _knobGrab = pointer.dx;
    _knobBase = _knob;
    _knobPip = _pipOf(_knob);
  }

  /// Moves the knob after the finger, mapping the full bar to ±90 degrees. With cruise on, the ends of the bar turn
  /// nothing directly: a knob held there keeps the paper turning, from the
  /// tick.
  void _dragKnob(Offset pointer) {
    final dial = _dial;
    final before = _knob;
    _knob = dial.knobFor(
      _knobBase + pointer.dx - _knobGrab,
      cruise: _settings.dialCruise,
    );
    final reach = _settings.dialCruise ? dial.freeReach : dial.halfLength;
    final turn =
        dial.angleAt(_knob.clamp(-reach, reach)) -
        dial.angleAt(before.clamp(-reach, reach));
    if (turn != 0) _turnDesk(turn, _scissorLine.$1);
    final pip = _pipOf(_knob);
    if (pip != _knobPip) {
      _knobPip = pip;
      HapticFeedback.selectionClick();
    }
  }

  /// Which pip the knob at [x] has passed, counted out from the middle.
  int _pipOf(double x) =>
      ((_dial.angleAt(x) - math.pi / 2) / (kAsmrDialPipDegrees * math.pi / 180))
          .truncate();

  // -------------------------------------------------------------------------
  // Straight edge
  // -------------------------------------------------------------------------

  /// The straight edge where it stops and guides cuts: out, settled, and
  /// on the desk.
  AsmrStraightEdge? get _liveEdge =>
      _edgeOn && _edgeShown >= 1 && !_in3d ? _edge : null;

  /// Pixels the straight edge is moved along its normal while flying.
  double get _edgeFly {
    final t = _edgeOn
        ? Curves.easeOutCubic.transform(_edgeShown)
        : Curves.easeInCubic.transform(_edgeShown);
    return (1 - t) *
        (_viewport.longestSide + kStraightEdgeThickness * 2) *
        _edgeFlySide;
  }

  Offset? get _edgeHandle {
    final edge = _edge;
    return edge?.rotateHandle(_center);
  }

  void _toggleEdge() {
    setState(() {
      final edge = _edge;
      if (_edgeOn) {
        _edgeOn = false;
        if (edge != null) {
          _edgeFlySide = edge.across(_center) <= 0 ? 1 : -1;
        }
        if (_drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn) {
          _drag = _Drag.none;
        }
      } else {
        _edgeOn = true;
        _edge ??= AsmrStraightEdge(anchor: _center);
      }
    });
  }

  /// Starts moving or turning the straight edge if [pointer] is on it.
  bool _grabEdge(Offset pointer) {
    final edge = _liveEdge;
    if (edge == null) return false;
    final handle = _edgeHandle;
    final onHandle =
        handle != null && (pointer - handle).distance <= _kHandleRadius;
    if (!onHandle && !edge.contains(pointer)) return false;
    final stored = _edge;
    if (stored != null && !_edgeGrabbed) {
      _edgeHomeAnchor = stored.anchor;
      _edgeHomeAngle = stored.angle;
      _edgeGrabbed = true;
    }
    if (onHandle) {
      _drag = _Drag.edgeTurn;
      _edgePivot = edge.nearestOnMiddle(_center);
      _edgeTurnFrom = math.atan2(
        pointer.dy - _edgePivot.dy,
        pointer.dx - _edgePivot.dx,
      );
      _edgeTurnBase = edge.angle;
      return true;
    }
    _drag = _Drag.edgeSlide;
    return true;
  }

  /// Puts the straight edge's anchor, and so its handle, back across from
  /// the middle of the screen.
  void _settleEdge() {
    final edge = _edge;
    if (edge == null) return;
    _edge = edge.copyWith(anchor: edge.nearestOnMiddle(_center));
  }

  // -------------------------------------------------------------------------
  // Pointers
  // -------------------------------------------------------------------------

  double _span() {
    final points = _pointers.values.toList();
    return points.length < 2 ? 0 : (points[0] - points[1]).distance;
  }

  double _fingerAngle() {
    final points = _pointers.values.toList();
    if (points.length < 2) return 0;
    final direction = points[1] - points[0];
    return math.atan2(direction.dy, direction.dx);
  }

  Offset _focal() {
    var sum = Offset.zero;
    for (final p in _pointers.values) {
      sum += p;
    }
    return _pointers.isEmpty ? Offset.zero : sum / _pointers.length.toDouble();
  }

  /// True when a finger, or the pair of them, just scrubbed back and forth.
  bool _scrubbed(Duration time) {
    var hit = false;
    for (final entry in _pointers.entries) {
      final scrub = _scrubs.putIfAbsent(entry.key, AsmrScrub.new);
      final adjustingCut =
          _pointers.length == 1 &&
          (_drag == _Drag.circle ||
              _drag == _Drag.scissors ||
              _drag == _Drag.dial);
      final sample = adjustingCut ? Offset(entry.value.dx, 0) : entry.value;
      if (scrub.add(time, sample)) hit = true;
    }
    if (_pointers.length >= 2 && _focalScrub.add(time, _focal())) hit = true;
    return hit;
  }

  void _dropStroke() {
    _rawStroke = null;
    _stroke = null;
    _finger = null;
    _tipDesk = null;
    _knifeSide = null;
  }

  /// Drops the gesture under way. A piece in hand eases back to the pose it
  /// had when it was picked up.
  void _cancelGesture() {
    final held = List<_Held>.of(_held);
    final marquee = _marqueeHome;
    final pieceBox = _pieceBoxHome;
    final edgeGrabbed = _edgeGrabbed;
    final drag = _drag;
    if (drag == _Drag.none &&
        held.isEmpty &&
        marquee == null &&
        pieceBox == null &&
        !edgeGrabbed) {
      return;
    }
    if (drag == _Drag.cut) _dropStroke();
    if (drag == _Drag.straight) _cancelStraight();
    if (drag == _Drag.scissors || drag == _Drag.circle) {
      _scissorDrag = null;
      _circleCut = false;
    }
    if (drag == _Drag.dial || drag == _Drag.circle) _releaseKnob();
    if (marquee != null) {
      if (_selection.replace(marquee)) _rebuildNet();
      _marqueeStart = null;
      _marqueeEnd = null;
      _marqueeHome = null;
    }
    if (pieceBox != null) {
      _selectedIds
        ..clear()
        ..addAll(pieceBox);
      _marqueeStart = null;
      _marqueeEnd = null;
      _pieceBoxHome = null;
    }
    if (edgeGrabbed) {
      final edge = _edge;
      if (edge != null) {
        _edge = edge.copyWith(anchor: _edgeHomeAnchor, angle: _edgeHomeAngle);
      }
      _edgeGrabbed = false;
    }
    _warps.clear();
    for (final pose in held) {
      final i = _pieces.indexWhere((p) => p.id == pose.id);
      if (i < 0) continue;
      final piece = _pieces[i];
      _warps.add(
        _Warp(
          id: pose.id,
          from: piece.position,
          to: pose.position,
          fromAngle: piece.angle,
          toAngle: pose.angle,
        ),
      );
    }
    _held.clear();
    _moveIds.clear();
    _bin = null;
    _drag = _Drag.none;
    _dragMoved = true;
    _gestureBefore = null;
    for (final scrub in _scrubs.values) {
      scrub.reset();
    }
    _focalScrub.reset();
    HapticFeedback.mediumImpact();
  }

  void _onPointerDown(PointerDownEvent event) {
    _lastKind = event.kind;
    _cutFromAbove = false;
    _circleCanTurn = false;
    _placingRotate =
        _placing &&
        event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kSecondaryMouseButton) != 0;
    final first = _pointers.isEmpty;
    _pointers[event.pointer] = event.localPosition;
    if (first) {
      _scrubs.clear();
      _focalScrub.reset();
    } else {
      _focalScrub.reset();
    }
    if (_aimsWithCursor) _hover = event.localPosition;
    if (_pointers.length >= 2) {
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
      if (_in3d) {
        if (secondary) {
          _drag = _Drag.pan;
        } else if (_modelTool == _ModelTool.select) {
          _drag = _Drag.marquee;
          _marqueeHome = List.of(_selection.picks);
          _marqueeStart = event.localPosition;
          _marqueeEnd = event.localPosition;
        } else {
          _drag = _Drag.orbit;
        }
        return;
      }
      if (_placing) {
        _drag = _Drag.place;
        _lastDesk = _toDesk(event.localPosition);
        _gestureBefore = _capture();
        return;
      }
      if (!_aimsWithCursor && _canSendPaper && _aimsAtSendPaper(_center)) {
        _drag = _Drag.submit;
        return;
      }
      if (secondary) {
        _drag = _Drag.deskPan;
        return;
      }
      if (_deskTool != _DeskTool.scissors && _grabEdge(event.localPosition)) {
        return;
      }
      _startDeskDrag(event.localPosition);
    });
  }

  void _startDeskDrag(Offset pointer) {
    final desk = _toDesk(
      _deskTool == _DeskTool.select && !_aimsWithCursor ? _center : pointer,
    );
    _lastDesk = _toDesk(pointer);
    if (_deskTool == _DeskTool.exacto) {
      _drag = _Drag.cut;
      _beginCut(pointer);
      return;
    }
    if (_deskTool == _DeskTool.straight) {
      _drag = _Drag.straight;
      _beginStraight(pointer);
      return;
    }
    if (_deskTool == _DeskTool.scissors) {
      if (!_pinned && _scissorAim == null) {
        _drag = _Drag.deskPan;
        return;
      }
      final circle = _scissorCircle;
      final radius = _aimsWithCursor
          ? _kScissorMouseRadius
          : _kScissorTouchRadius;
      _circleCanTurn = (pointer - circle).distance <= radius;
      if (_circleCanTurn || pointer.dy < circle.dy) {
        _drag = _Drag.circle;
        _circleCut = false;
        _cutFromAbove = pointer.dy < circle.dy;
        _grabKnob(pointer);
      } else {
        _drag = _pinned ? _Drag.none : _Drag.deskPan;
      }
      return;
    }
    final selected = _selected;
    final handle = selected == null ? null : _handleFor(selected);
    if (selected != null &&
        handle != null &&
        (pointer - handle).distance <= _kHandleRadius) {
      _drag = _Drag.rotate;
      _warps.clear();
      _held
        ..clear()
        ..add(_Held(selected.id, selected.position, selected.angle));
      _rotatePivot = selected.edgeCenterOpposite(_toDesk(handle));
      final center = _toScreen(_rotatePivot);
      _rotateFrom = math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
      _rotateBase = selected.angle;
      _gestureBefore = _capture();
      return;
    }
    final hit = _pieceAt(desk);
    if (hit != null) {
      _drag = _Drag.move;
      _warps.clear();
      if (!_selectedIds.contains(hit.id)) {
        _selectedIds
          ..clear()
          ..add(hit.id);
      }
      _moveIds
        ..clear()
        ..addAll(_selectedIds);
      final moving = [
        for (final piece in _pieces)
          if (_moveIds.contains(piece.id)) piece,
      ];
      _pieces.removeWhere((piece) => _moveIds.contains(piece.id));
      _pieces
        ..addAll(moving.where((piece) => piece.id != hit.id))
        ..add(hit);
      _held
        ..clear()
        ..addAll([
          for (final piece in moving)
            _Held(piece.id, piece.position, piece.angle),
        ]);
      _gestureBefore = _capture();
      return;
    }
    if (_deskTool == _DeskTool.select) {
      _drag = _Drag.pieceBox;
      _marqueeStart = pointer;
      _marqueeEnd = pointer;
      _pieceBoxHome = Set.of(_selectedIds);
      return;
    }
    _drag = _Drag.deskPan;
  }

  void _applyPieceMarquee() {
    final start = _marqueeStart;
    final end = _marqueeEnd;
    if (start == null || end == null || (end - start).distance < _kTapSlop) {
      return;
    }
    final rect = Rect.fromPoints(start, end);
    final pick = marqueePick(start, end);
    _selectedIds
      ..clear()
      ..addAll([
        for (final piece in _pieces)
          if (polygonInMarquee(
            [for (final point in piece.deskRing) _toScreen(point)],
            rect,
            pick,
          ))
            piece.id,
      ]);
  }

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

  /// The scrap slot or the trash under [local], or null.
  int? _binAt(Offset local) {
    if (_inside(_trashKey, local)) return _kTrashBin;
    for (var i = 0; i < _slotKeys.length; i++) {
      if (_inside(_slotKeys[i], local)) return i;
    }
    return null;
  }

  void _trashHeld() {
    _pieces.removeWhere((piece) => _moveIds.contains(piece.id));
    _selectedIds.removeAll(_moveIds);
    _moveIds.clear();
    _held.clear();
    _warps.clear();
  }

  /// Keeps the held pieces in [slot], then in the other empty slots. What
  /// does not fit goes back where it was picked up.
  void _stowHeld(int slot) {
    final free = <int>{
      for (final i in [slot, for (var i = 0; i < _slots.length; i++) i])
        if (_slots[i] == null) i,
    }.toList();
    for (final pose in _held) {
      final i = _pieces.indexWhere((p) => p.id == pose.id);
      if (i < 0) continue;
      final piece = _pieces[i];
      if (free.isEmpty) {
        _pieces[i] = piece.copyWith(position: pose.position, angle: pose.angle);
        continue;
      }
      _slots[free.removeAt(0)] = piece.unbound();
      _pieces.removeAt(i);
      _selectedIds.remove(piece.id);
    }
    _moveIds.clear();
    _held.clear();
    _warps.clear();
  }

  /// Lays the scrap in [slot] back down, in the middle of the screen.
  void _unstow(int slot) {
    final piece = _slots[slot];
    if (piece == null) return;
    setState(() {
      _pushUndo();
      _slots[slot] = null;
      final back = piece.copyWith(
        position: piece.position + _toDesk(_center) - piece.deskCentroid,
      );
      _pieces.add(back.unbound());
      _setDeskTool(_DeskTool.select);
      _selectedIds
        ..clear()
        ..add(back.id);
      _flash[back.id] = 0.6;
      _rejudge();
    });
  }

  void _setDeskTool(_DeskTool tool) {
    if (tool != _deskTool) {
      // A held Exacto pointer must not keep cutting after the camera/tool
      // changes. Already committed splits stay; its unfinished preview ends.
      _cancelGesture();
      _dropStroke();
    }
    _aimOrbitT = 1;
    _deskTool = tool;
    if (tool != _DeskTool.select) _selectedIds.clear();
    if (tool != _DeskTool.exacto) _tipDesk = null;
    if (tool != _DeskTool.straight || _drag == _Drag.straight) {
      _cancelStraight();
    }
    if (_drag == _Drag.straight) _drag = _Drag.none;
    if (tool != _DeskTool.scissors) {
      _scissorDrag = null;
      _scissorEnd = null;
      _scissorAim = null;
      _circleCut = false;
      _spinSpeed = 0;
      if (_drag == _Drag.dial || _drag == _Drag.circle) _releaseKnob();
      if (_drag == _Drag.scissors ||
          _drag == _Drag.dial ||
          _drag == _Drag.circle) {
        _drag = _Drag.none;
      }
    }
  }

  void _beginTwoFinger() {
    setState(() {
      if (_drag == _Drag.cut) _dropStroke();
      if (_drag == _Drag.straight) _cancelStraight();
      if (_drag == _Drag.scissors || _drag == _Drag.circle) {
        _scissorDrag = null;
      }
      _circleCut = false;
      if (_drag == _Drag.dial || _drag == _Drag.circle) _releaseKnob();
      if (_placing) _gestureBefore ??= _capture();
      if (_drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn) _settleEdge();
      _drag = _Drag.pan;
      _dragMoved = true;
      _doubleTap.reset();
      _marqueeStart = null;
      _marqueeEnd = null;
      _lastSpan = _span();
      _lastFingerAngle = _fingerAngle();
      _lastFocal = _focal();
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer];
    if (previous == null) return;
    _pointers[event.pointer] = event.localPosition;
    if (_aimsWithCursor) _hover = event.localPosition;
    if (_scrubbed(event.timeStamp)) {
      setState(_cancelGesture);
      return;
    }
    final delta = event.localPosition - previous;
    if ((event.localPosition - _dragStart).distance > _kTapSlop) {
      _dragMoved = true;
    }
    setState(() {
      if (_pointers.length >= 2) {
        _twoFingerMove();
        return;
      }
      switch (_drag) {
        case _Drag.submit:
          if (_dragMoved) _panDesk(delta, at: event.localPosition);
        case _Drag.orbit:
          if (!_dragMoved) return;
          _turntable(-delta.dx * _kOrbitPerPixel, delta.dy * _kOrbitPerPixel);
          _refreshHover();
        case _Drag.pan:
          _panView(delta);
        case _Drag.marquee:
          _marqueeEnd = event.localPosition;
          if (_dragMoved) _applyMarquee();
        case _Drag.pieceBox:
          _marqueeEnd = event.localPosition;
          if (_dragMoved) _applyPieceMarquee();
        case _Drag.cut:
          _extendCut(event.localPosition);
        case _Drag.straight:
          _extendStraight(event.localPosition);
        case _Drag.circle:
        case _Drag.scissors:
        case _Drag.dial:
          _followCircle(event.localPosition);
        case _Drag.place:
          if (_placingRotate) {
            _rotatePlacement(delta.dx * 0.01);
          } else {
            final desk = _toDesk(event.localPosition);
            _slidePaper(desk - _lastDesk);
            _lastDesk = desk;
          }
        case _Drag.move:
          final desk = _toDesk(event.localPosition);
          final delta = desk - _lastDesk;
          for (final id in _moveIds) {
            final i = _pieces.indexWhere((piece) => piece.id == id);
            if (i < 0) continue;
            final piece = _pieces[i];
            _pieces[i] = piece.copyWith(position: piece.position + delta);
          }
          _lastDesk = desk;
          _bin = _binAt(event.localPosition);
        case _Drag.rotate:
          final piece = _selected;
          if (piece == null) return;
          final center = _toScreen(_rotatePivot);
          final now = math.atan2(
            event.localPosition.dy - center.dy,
            event.localPosition.dx - center.dx,
          );
          _replace(
            piece.turnedAbout(_rotateBase + now - _rotateFrom, _rotatePivot),
          );
        case _Drag.deskPan:
          _panDesk(delta, at: event.localPosition);
        case _Drag.edgeSlide:
          final edge = _edge;
          if (edge == null) return;
          final n = edge.normal;
          final push = delta.dx * n.dx + delta.dy * n.dy;
          _edge = edge.copyWith(anchor: edge.anchor + n * push);
        case _Drag.edgeTurn:
          final edge = _edge;
          if (edge == null) return;
          final now = math.atan2(
            event.localPosition.dy - _edgePivot.dy,
            event.localPosition.dx - _edgePivot.dx,
          );
          _edge = edge.copyWith(
            anchor: _edgePivot,
            angle: _edgeTurnBase + now - _edgeTurnFrom,
          );
        case _Drag.none:
          break;
      }
    });
  }

  void _twoFingerMove() {
    final focal = _focal();
    final span = _span();
    final angle = _fingerAngle();
    final rawTurn = angle - _lastFingerAngle;
    final turn = _lastSpan > 1 && span > 1
        ? math.atan2(math.sin(rawTurn), math.cos(rawTurn))
        : 0.0;
    _lastFingerAngle = angle;
    final scale = _lastSpan > 1 && span > 1 ? span / _lastSpan : 1.0;
    final delta = focal - _lastFocal;
    _lastFocal = focal;
    _lastSpan = span;
    if (_in3d) {
      _panView(delta);
      if ((scale - 1).abs() > 1e-4) _camera.zoomByScale(scale);
    } else if (_placing) {
      _rotatePlacement(turn);
      _slidePaper(_spin(delta, -_deskAngle) / _deskScale);
      if ((scale - 1).abs() > 1e-4) _zoomDesk(scale, _center);
    } else {
      _panDesk(delta, at: focal);
      if ((scale - 1).abs() > 1e-4) _zoomDesk(scale, focal);
    }
  }

  void _panView(Offset delta) {
    if (!_in3d) {
      _panDesk(delta);
      return;
    }
    _camera.panInView(
      delta,
      _viewport,
      anchor: _model.center,
      limit: _model.radius * 3,
    );
    _refreshHover();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    _scrubs.remove(event.pointer);
    _focalScrub.reset();
    _doubleTap.reset();
    setState(_cancelGesture);
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
    if (_drag == _Drag.circle ||
        _drag == _Drag.scissors ||
        _drag == _Drag.dial) {
      if ((event.localPosition - _dragStart).distance > _kTapSlop) {
        _dragMoved = true;
      }
      _followCircle(event.localPosition);
    }
    if (_drag == _Drag.submit) {
      final tapped =
          !_dragMoved && event.timeStamp - _dragStartTime < _kTapTime;
      _drag = _Drag.none;
      if (tapped) setState(_sendPaper);
      return;
    }
    final tap =
        !(_placing && _placingRotate) &&
        !_dragMoved &&
        !(_drag == _Drag.scissors && _circleCut) &&
        event.timeStamp - _dragStartTime < _kTapTime;
    if (!tap || _drag == _Drag.pan) {
      _doubleTap.reset();
    } else if (_doubleTap.tap(event.localPosition, _clock)) {
      final home = _tapHome ?? _selection.picks;
      if (!_in3d || home.isNotEmpty) {
        setState(() {
          if (_in3d && _selection.replace(home)) _rebuildNet();
          _tapHome = null;
          _toggleWorkspace();
        });
        return;
      }
    }
    _tapHome = null;
    setState(() {
      switch (_drag) {
        case _Drag.submit:
          break;
        case _Drag.orbit:
          if (tap) _tapModel(event.localPosition);
        case _Drag.marquee:
          if (tap) _tapModel(event.localPosition, select: true);
          _marqueeStart = null;
          _marqueeEnd = null;
        case _Drag.cut:
          _endCut();
        case _Drag.straight:
          _endStraight();
        case _Drag.circle:
          _circleCut = false;
          _releaseKnob();
        case _Drag.scissors:
          _endScissors();
          _circleCut = false;
          _releaseKnob();
        case _Drag.dial:
          _releaseKnob();
        case _Drag.place:
          if (tap && _clock - _placingSince >= _kPlaceTapAfter) {
            _endPlacing();
          } else {
            _rejudge();
          }
        case _Drag.pieceBox:
          if (tap) _selectedIds.clear();
          _marqueeStart = null;
          _marqueeEnd = null;
          _pieceBoxHome = null;
        case _Drag.move:
          final bin = _dragMoved ? _binAt(event.localPosition) : null;
          if (bin == _kTrashBin) {
            _trashHeld();
          } else if (bin != null) {
            _stowHeld(bin);
          }
          _bin = null;
          _rejudge();
        case _Drag.rotate:
          _rejudge();
        case _Drag.deskPan:
          if (tap && _scissoring && !_pinned) {
            _lineUpScissors(event.localPosition);
          } else if (tap && _deskTool == _DeskTool.select) {
            _selectedIds.clear();
          }
        case _Drag.edgeSlide:
        case _Drag.edgeTurn:
          _settleEdge();
        case _Drag.pan:
        case _Drag.none:
          break;
      }
      _drag = _Drag.none;
      _held.clear();
      _moveIds.clear();
      _marqueeHome = null;
      _pieceBoxHome = null;
      _edgeGrabbed = false;
      _commitGesture();
    });
  }

  /// A tap on the cube. A face of a group opens that group on the desk.
  /// Otherwise, with [select], the face becomes the selection, or a tap on
  /// nothing clears it.
  void _tapModel(Offset at, {bool select = false}) {
    final face = _faceAt(at);
    final group = face == null ? null : _groupOf(face);
    if (group != null) {
      _openGroup(group);
      return;
    }
    if (!select) return;
    _tapHome = List.of(_selection.picks);
    final picks = face == null ? const <HologramPick>[] : [HologramPick(face)];
    if (_selection.replace(picks)) _rebuildNet();
  }

  void _onPointerHover(PointerHoverEvent event) {
    _lastKind = event.kind;
    setState(() {
      _hover = event.localPosition;
      if (_in3d) {
        _refreshHover();
      } else if (_deskTool == _DeskTool.exacto) {
        _tipDesk = _toDesk(event.localPosition);
      }
    });
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final factor = math.exp(-event.scrollDelta.dy * 0.002);
    setState(() {
      if (_in3d) {
        _camera.zoomByScale(factor);
      } else {
        _zoomDesk(factor, _placing ? _center : event.localPosition);
      }
    });
  }

  double _panZoomScale = 1;

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _lastKind = event.kind;
    _panZoomScale = 1;
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final factor = _panZoomScale > 0 ? event.scale / _panZoomScale : 1.0;
    _panZoomScale = event.scale;
    setState(() {
      if (_in3d) {
        _panView(event.localPanDelta);
        if ((factor - 1).abs() > 1e-4) _camera.zoomByScale(factor);
      } else if (_placing) {
        _slidePaper(_spin(event.localPanDelta, -_deskAngle) / _deskScale);
        if ((factor - 1).abs() > 1e-4) _zoomDesk(factor, _center);
      } else {
        _panDesk(event.localPanDelta, at: event.localPosition);
        if ((factor - 1).abs() > 1e-4) {
          _zoomDesk(factor, event.localPosition);
        }
      }
    });
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  List<HologramEdgeView> get _edgeViews => [
    for (final held in _holoEdges.values)
      HologramEdgeView(
        a: held.edge.a,
        b: held.edge.b,
        fold: held.edge.fold,
        opacity: held.opacity,
        color: held.color,
      ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _theme.solid(AsmrThemeSlot.desk),
      body: LayoutBuilder(
        builder: (context, constraints) {
          _onLayout(constraints.biggest);
          final t = _blend;
          return Stack(
            key: _stackKey,
            children: [
              Positioned.fill(
                child: _input(
                  Stack(
                    children: [
                      Positioned.fill(child: _backdrop(t)),
                      for (final model in _in3d ? [false, true] : [true, false])
                        Positioned.fill(
                          key: ValueKey(model),
                          child: model ? _modelView(t) : _deskView(t),
                        ),
                    ],
                  ),
                ),
              ),
              if (_flights.isNotEmpty)
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      key: const ValueKey('asmr-flights'),
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
              Positioned.fill(child: _straightEdgeLayer(1 - t)),
              if (_scissoring && t < 0.99)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: 1 - t,
                      child: CustomPaint(
                        key: const ValueKey('asmr-scissors'),
                        painter: AsmrScissorsPainter(
                          from: _scissorLine.$1,
                          to: _scissorLine.$2,
                          mark: _scissorMark,
                          circle: _scissorCircle,
                          aiming: _scissorAiming,
                          controlsOpacity: _scissorControlsOpacity,
                          aimPoints: _scissorAiming
                              ? [for (final aim in _aimPoints) aim.screen]
                              : const [],
                          stuck: _pinned,
                          dial: _dial,
                          knob: _knob,
                          dialHeld:
                              _drag == _Drag.dial || _drag == _Drag.circle,
                          cruise: _settings.dialCruise,
                          theme: _theme,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_knifeScreen case final tip?)
                Positioned.fill(
                  key: const ValueKey('asmr-knife'),
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AsmrKnifePainter(
                        tip: tip,
                        finger: _finger,
                        theme: _theme,
                      ),
                    ),
                  ),
                ),
              if (_marqueeStart != null && _marqueeEnd != null)
                Positioned.fill(
                  key: const ValueKey('asmr-marquee'),
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AsmrMarqueePainter(
                        start: _marqueeStart!,
                        end: _marqueeEnd!,
                        contain: _theme.colorOf(AsmrThemeSlot.marquee),
                        crossColor: _theme.colorOf(AsmrThemeSlot.marqueeCross),
                        containOpacity: _theme.opacityOf(AsmrThemeSlot.marquee),
                        crossOpacity: _theme.opacityOf(
                          AsmrThemeSlot.marqueeCross,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_aim case final aim? when t > 0.5)
                Positioned(
                  key: const ValueKey('asmr-crosshair'),
                  left:
                      aim.dx - (_showBlueprintReticle ? 48 : _kReticleBox) / 2,
                  top: aim.dy - (_showBlueprintReticle ? 48 : _kReticleBox) / 2,
                  width: _showBlueprintReticle ? 48 : _kReticleBox,
                  height: _showBlueprintReticle ? 48 : _kReticleBox,
                  child: Opacity(
                    opacity: (t - 0.5) * 2,
                    child: _showBlueprintReticle
                        ? IgnorePointer(
                            child: CustomPaint(
                              key: const ValueKey('asmr-reticle-blueprint'),
                              painter: _ReticleBlueprintPainter(
                                _hoverGroup!.net,
                              ),
                            ),
                          )
                        : ViewCrosshair(
                            color: _theme.ink(
                              AsmrThemeSlot.reticle,
                              const Color(0xF2FFFFFF),
                            ),
                          ),
                  ),
                ),
              if (_sendPaperAt case final at? when _showSendPaper)
                Positioned(
                  left: at.dx - 22,
                  top: at.dy - 22,
                  child: Tooltip(
                    message: 'Send paper to object',
                    child: GestureDetector(
                      key: const Key('asmr-send-paper'),
                      behavior: HitTestBehavior.opaque,
                      onTap: _canSendPaper ? () => setState(_sendPaper) : null,
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white),
                        ),
                        child: Icon(
                          Icons.arrow_upward,
                          color: const Color(0xFF14152A),
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ),
              if (_aim case final aim? when _showSelectReticle)
                Positioned(
                  key: const ValueKey('asmr-select-reticle'),
                  left: aim.dx - _kReticleBox / 2,
                  top: aim.dy - _kReticleBox / 2,
                  width: _kReticleBox,
                  height: _kReticleBox,
                  child: ViewCrosshair(
                    color: _theme.ink(
                      AsmrThemeSlot.reticle,
                      const Color(0xF2FFFFFF),
                    ),
                  ),
                ),
              ..._chrome(context, t),
            ],
          );
        },
      ),
    );
  }

  bool get _showSelectReticle =>
      !_in3d && !_placing && _deskTool == _DeskTool.select;

  String? get _selectionHoverId {
    final aim = _aim;
    return _showSelectReticle && aim != null
        ? _pieceAt(_toDesk(aim))?.id
        : null;
  }

  bool get _showKnife => !_in3d && !_placing && _deskTool == _DeskTool.exacto;

  /// Where the exacto's crosshair is drawn, on screen.
  Offset? get _knifeScreen {
    if (!_showKnife || _tipDesk == null) return null;
    return _finger != null ? _bladeAt(_finger!) : _toScreen(_tipDesk!);
  }

  Widget _straightEdgeLayer(double flat) {
    final edge = _edge;
    if (edge == null || _edgeShown <= 0 || flat <= 0.01) {
      return const SizedBox.shrink();
    }
    return IgnorePointer(
      child: Opacity(
        opacity: flat,
        child: CustomPaint(
          key: const Key('asmr-straight-edge'),
          painter: AsmrStraightEdgePainter(
            edge: edge,
            fly: _edgeFly,
            handle: _edgeHandle,
            pressed: _drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn,
            body: _theme.colorOf(AsmrThemeSlot.straightEdge),
            bodyOpacity: _theme.opacityOf(AsmrThemeSlot.straightEdge),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  /// Takes every pointer for whichever view is in front.
  Widget _input(Widget child) {
    final showStraight = !_in3d && _deskTool == _DeskTool.straight;
    return MouseRegion(
      cursor: _showKnife || _in3d || _showSelectReticle
          ? SystemMouseCursors.none
          : _placing
          ? SystemMouseCursors.move
          : showStraight
          ? SystemMouseCursors.precise
          : MouseCursor.defer,
      onExit: (_) => setState(() {
        if (_aimsWithCursor && _stroke == null) _tipDesk = null;
      }),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        onPointerHover: _onPointerHover,
        onPointerSignal: _onPointerSignal,
        onPointerPanZoomStart: _onPanZoomStart,
        onPointerPanZoomUpdate: _onPanZoomUpdate,
        child: child,
      ),
    );
  }

  /// The desk color, with the 3D view's sky coming over it as the model
  /// comes to the front.
  Widget _backdrop(double t) {
    return IgnorePointer(
      child: ColoredBox(
        color: _theme.solid(AsmrThemeSlot.desk),
        child: Opacity(
          opacity: t,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _theme.ink(AsmrThemeSlot.sky, kAsmrSkyColor),
                  _theme.ink(AsmrThemeSlot.desk, kAsmrDeskColor),
                ],
              ),
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  /// The desk and its glowing blueprint. Behind the 3D view its paper shows
  /// only as dashed outlines.
  Widget _deskView(double t) {
    final selected = _selected;
    final lens = _lens;
    return WorkviewLook.lerp(WorkviewLook.identity, _kInactiveLook, t).wrap(
      key: const ValueKey('asmr-desk'),
      IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: CustomPaint(
                painter: AsmrDeskPainter(
                  pieces: List.of(_pieces),
                  tiles: _tiles,
                  origin: _deskOrigin,
                  scale: _deskScale,
                  angle: _deskAngle,
                  projection: lens.deskMatrix(
                    origin: _deskOrigin,
                    scale: _deskScale,
                    angle: _deskAngle,
                  ),
                  hoveredId: _selectionHoverId,
                  selectedIds: _deskTool == _DeskTool.select
                      ? Set.of(_selectedIds)
                      : const {},
                  selectedOutline: _selectedOutline,
                  flash: Map.of(_flash),
                  stroke: _stroke == null ? null : List.of(_stroke!),
                  reach: _segmentReach,
                  rotateHandle:
                      _deskTool == _DeskTool.select && selected != null
                      ? _handleFor(selected)
                      : null,
                  blueprint: _net,
                  affixedNets: {
                    for (final group in _groups) group.letter: group.net,
                  },
                  blueprintColors: {
                    if (_group != null)
                      _group!.letter: {
                        for (final entry in _holoEdges.entries)
                          if (entry.value.color != null)
                            entry.key: entry.value.color!,
                      },
                  },
                  placementGlow: _placementGlow,
                  placementGroup: _placementGlowGroup,
                  shadowThrow: _settings.shadowThrow,
                  shadowSpread: _settings.shadowSpread,
                  shadowColor: _settings.shadowPaint,
                  darkOverlay: _settings.darkOverlay,
                  theme: _theme,
                  ghost: t,
                  paintBackground: false,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            Positioned.fill(
              child: CustomPaint(
                painter: HologramPainter(
                  edges: _edgeViews,
                  faces: [for (final face in _net.faces) face.ring],
                  origin: _deskOrigin,
                  scale: _deskScale,
                  angle: _deskAngle,
                  lens: lens.isOverhead ? null : lens,
                  contrast: 1,
                  line: _theme.colorOf(AsmrThemeSlot.hologram),
                  glow: _theme.colorOf(AsmrThemeSlot.hologram),
                  inkOpacity: _hasAffixedBlueprint
                      ? 0
                      : _theme.opacityOf(AsmrThemeSlot.hologram),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _modelView(double t) {
    return WorkviewLook.lerp(_kInactiveLook, WorkviewLook.identity, t).wrap(
      key: const ValueKey('asmr-model'),
      IgnorePointer(child: _modelLayer()),
    );
  }

  /// Paper that has landed on the model. Pieces still flying there join
  /// when they land.
  List<AsmrPiece> get _modelPieces => [
    for (final piece in _boundPieces)
      if (!_flights.any((flight) => identical(flight.piece, piece))) piece,
  ];

  /// Subtle group colors fade to half-opacity white under the reticle.
  Map<int, Color> get _groupTints => {
    for (final group in _groups)
      for (final face in group.faces)
        face: Color.lerp(
          group.hatch.color.withValues(alpha: 0.15),
          Colors.white.withValues(alpha: 0.5),
          Curves.easeOut.transform((_faceFill[face] ?? 0).clamp(0.0, 1.0)),
        )!,
  };

  Widget _modelLayer() {
    final glow = _complete
        ? {
            for (var f = 0; f < _model.faces.length; f++)
              f: _completeShown * (0.6 + 0.4 * math.sin(_clock * 3)),
          }
        : const <int, double>{};
    return CustomPaint(
      painter: ModelPainter(
        camera: _camera,
        model: _model,
        covered: {
          for (final entry in _coverage.entries)
            if (entry.value >= kAsmrFilled) entry.key: 1.0,
        },
        glow: glow,
        sheets: (canvas, size, add) => addBoundPaper(
          canvas: canvas,
          size: size,
          camera: _camera,
          model: _model,
          pieces: _modelPieces,
          tiles: _tiles,
          add: add,
          tint: _groupTints,
        ),
        blueprintInk: _theme.colorOf(AsmrThemeSlot.blueprint),
        blueprintFade: _theme.opacityOf(AsmrThemeSlot.blueprint),
        preselectInk: _theme.colorOf(AsmrThemeSlot.preselect),
        preselectFade: _theme.opacityOf(AsmrThemeSlot.preselect),
        completeInk: _theme.colorOf(AsmrThemeSlot.complete),
        completeFade: _theme.opacityOf(AsmrThemeSlot.complete),
      ),
      child: const SizedBox.expand(),
    );
  }

  int get _filledCount =>
      _coverage.values.where((c) => c >= kAsmrFilled).length;

  String get _debugReadout {
    String number(double value) => value.toStringAsFixed(2);
    String degrees(double radians) =>
        (radians * 180 / math.pi).toStringAsFixed(1);
    final cameraZoom = _homeCameraHalfHeight / _camera.framedHalfHeightMm;
    final tool = _in3d
        ? _modelTool.name
        : _placing
        ? 'placement'
        : _deskTool.name;
    return [
      'DEBUG · ${_object.name} · ${_in3d ? '3D' : '2D'} · $tool · drag ${_drag.name}',
      'Camera zoom ${number(cameraZoom)}× · half-height ${number(_camera.framedHalfHeightMm)} · lens ${number(_camera.focalLengthMm)}mm',
      'Orbit ${degrees(_camera.azimuth)}° / ${degrees(_camera.elevation)}° · target ${number(_camera.lookAt.dx)}, ${number(_camera.lookAt.dy)}, ${number(_camera.lookAtZ)}',
      'Desk zoom ${number(_deskScale)}px/u · turn ${degrees(_deskAngle)}° · group ${_group?.name ?? '—'} · cuts $_cutsRemaining',
      'Pieces ${_pieces.length} · bound ${_boundPieces.length} · drafts ${_groups.fold<int>(0, (n, g) => n + g.draft.length)} · flights ${_flights.length} · hover ${_hoverFace ?? '—'}',
    ].join('\n');
  }

  List<Widget> _chrome(BuildContext context, double t) {
    final padding = MediaQuery.paddingOf(context);
    final flat = 1 - t;
    return [
      Positioned(
        top: padding.top + 56,
        left: 12,
        right: 112,
        child: IgnorePointer(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  Text(
                    'Faces filled  $_filledCount / ${_model.faces.length}',
                    style: TextStyle(
                      color: _theme.ink(AsmrThemeSlot.title, Colors.white70),
                      fontSize: 14,
                    ),
                  ),
                  if (!_in3d && _group != null)
                    Text(
                      'Group ${_group!.name} · Scissor cuts left: $_cutsRemaining',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                  if (_completeShown > 0)
                    Opacity(
                      opacity: _completeShown,
                      child: Text(
                        'Craft complete',
                        style: TextStyle(
                          color: _theme.ink(
                            AsmrThemeSlot.complete,
                            Colors.white,
                          ),
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              if (_settings.debugOutput) ...[
                const SizedBox(height: 8),
                Container(
                  key: const Key('asmr-debug-output'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _debugReadout,
                    maxLines: 8,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 10,
                      height: 1.35,
                      color: Colors.white70,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      Positioned(
        top: padding.top + 8,
        left: 8,
        child: AsmrRoundButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          iconColor: _theme.ink(AsmrThemeSlot.button, Colors.white70),
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed('dev_routes');
            }
          },
        ),
      ),
      if (_groups.isNotEmpty)
        Positioned(
          top: padding.top + 64,
          right: 12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final group in _groups)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: _GroupButton(
                    group: group,
                    tiles: _tiles,
                    open: identical(group, _group),
                    theme: _theme,
                    onTap: () => _tapGroup(group),
                  ),
                ),
            ],
          ),
        ),
      Positioned(
        top: padding.top + 8,
        right: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AsmrRoundButton(
                  key: const Key('asmr-deal'),
                  icon: Icons.casino,
                  tooltip: 'Randomize groups',
                  iconColor: _theme.ink(AsmrThemeSlot.button, Colors.white70),
                  onTap: _rollGroups,
                ),
                AsmrTextLink(
                  label: 'Save',
                  buttonKey: const Key('asmr-save'),
                  color: _theme.ink(
                    AsmrThemeSlot.button,
                    Colors.white.withValues(alpha: 0.7),
                  ),
                  onTap: _saveSession,
                ),
                AsmrTextLink(
                  label: 'Load',
                  buttonKey: const Key('asmr-load'),
                  color: _theme.ink(
                    AsmrThemeSlot.button,
                    Colors.white.withValues(alpha: 0.7),
                  ),
                  onTap: _loadSession,
                ),
                if (flat > 0.01)
                  Opacity(
                    opacity: flat,
                    child: IgnorePointer(
                      ignoring: flat < 0.5,
                      child: AsmrRoundButton(
                        icon: Icons.restart_alt,
                        tooltip: 'Start over',
                        iconColor: _theme.ink(
                          AsmrThemeSlot.button,
                          Colors.white70,
                        ),
                        onTap: _reset,
                      ),
                    ),
                  ),
                DevToolsButton(
                  active: _devToolsOpen,
                  onPressed: () =>
                      setState(() => _devToolsOpen = !_devToolsOpen),
                ),
              ],
            ),
            if (_devToolsOpen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: AsmrDevPanel(
                  settings: _settings,
                  pages: [
                    AsmrDevPage(
                      label: 'Object',
                      tabKey: const Key('asmr-dev-tab-object'),
                      builder: (_) => Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AsmrObjectMenu(
                            objectId: _object.id,
                            onSelected: _loadObject,
                          ),
                          Row(
                            children: [
                              const Expanded(
                                child: Text('Scissor cuts per group'),
                              ),
                              IconButton(
                                tooltip: 'Fewer scissor cuts',
                                onPressed: _settings.scissorCuts > 0
                                    ? () => _settings.scissorCuts--
                                    : null,
                                icon: const Icon(Icons.remove),
                              ),
                              Text('${_settings.scissorCuts}'),
                              IconButton(
                                tooltip: 'More scissor cuts',
                                onPressed: () => _settings.scissorCuts++,
                                icon: const Icon(Icons.add),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Expanded(child: Text('Debug output')),
                              Switch(
                                key: const Key('asmr-debug-output-toggle'),
                                value: _settings.debugOutput,
                                onChanged: (value) =>
                                    _settings.debugOutput = value,
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              const Expanded(child: Text('Blueprint reticle')),
                              Switch(
                                value: _settings.blueprintReticle,
                                onChanged: (value) =>
                                    _settings.blueprintReticle = value,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    AsmrDevPage(
                      label: 'Theme',
                      tabKey: const Key('asmr-dev-tab-theme'),
                      builder: (_) => AsmrThemeEditor(theme: _theme),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      Positioned(
        left: 16,
        bottom: padding.bottom + 16,
        child: _CubeToggle(
          on: _in3d,
          enabled: !_in3d || _canOpenDesk,
          onTap: _toggleMode,
          theme: _theme,
        ),
      ),
      Positioned(
        left: 88,
        right: 88,
        bottom: padding.bottom + 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AsmrHistoryButton(
              buttonKey: const Key('asmr-undo'),
              icon: Icons.undo,
              tooltip: 'Undo',
              enabled: _undoStack.isNotEmpty,
              gap: const EdgeInsets.only(right: _kHistoryPad),
              onTap: _undo,
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                if (t > 0.01)
                  Opacity(
                    opacity: t,
                    child: IgnorePointer(
                      ignoring: t < 0.5,
                      child: HudToolCarousel<_ModelTool>(
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
                            label: 'Select',
                            fill: CraftPalette.kentuckyBlue.fill,
                          ),
                        ],
                        selected: _modelTool,
                        onSelect: (tool) => setState(() {
                          _modelTool = tool;
                          _marqueeStart = null;
                          _marqueeEnd = null;
                        }),
                      ),
                    ),
                  ),
                if (flat > 0.01 && !_placing)
                  Opacity(
                    opacity: flat,
                    child: IgnorePointer(
                      ignoring: flat < 0.5,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          HudToolCarousel<_DeskTool>(
                            items: [
                              HudCarouselItem(
                                value: _DeskTool.select,
                                icon: Icons.open_with,
                                label: 'Select',
                                fill: CraftPalette.kentuckyBlue.fill,
                              ),
                              HudCarouselItem(
                                value: _DeskTool.exacto,
                                icon: Icons.carpenter,
                                label: 'Exacto',
                                fill: CraftPalette.scarlet.fill,
                              ),
                              HudCarouselItem(
                                value: _DeskTool.straight,
                                icon: Icons.horizontal_rule,
                                label: 'Straight cut',
                                fill: CraftPalette.ginger.fill,
                              ),
                              HudCarouselItem(
                                value: _DeskTool.scissors,
                                icon: Icons.cut,
                                label: 'Scissors',
                                fill: CraftPalette.carmel.fill,
                              ),
                            ],
                            selected: _deskTool,
                            onSelect: (tool) =>
                                setState(() => _setDeskTool(tool)),
                          ),
                          Container(
                            width: 1,
                            height: 32,
                            margin: const EdgeInsets.symmetric(horizontal: 6),
                            color: _theme.ink(
                              AsmrThemeSlot.button,
                              Colors.white24,
                            ),
                          ),
                          SizedBox(
                            width: 56,
                            height: 72,
                            child: HudToolButton(
                              icon: Icons.straighten,
                              label: 'Straight edge',
                              fill: CraftPalette.granite.fill,
                              selected: _edgeOn,
                              onTap: _toggleEdge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            AsmrHistoryButton(
              buttonKey: const Key('asmr-redo'),
              icon: Icons.redo,
              tooltip: 'Redo',
              enabled: _redoStack.isNotEmpty,
              gap: const EdgeInsets.only(left: _kHistoryPad),
              onTap: _redo,
            ),
          ],
        ),
      ),
      Positioned(
        right: 12,
        bottom: padding.bottom + 16,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flat > 0.01)
              Opacity(
                opacity: flat,
                child: IgnorePointer(
                  ignoring: flat < 0.5,
                  child: AsmrScrapSlots(
                    slots: List.of(_slots),
                    slotKeys: _slotKeys,
                    hot: (_bin ?? -1) >= 0 ? _bin : null,
                    open: _drag == _Drag.move || _selectedIds.isNotEmpty,
                    onTap: _unstow,
                  ),
                ),
              ),
            const SizedBox(height: 12),
            AsmrTrashButton(key: _trashKey, hot: _bin == _kTrashBin),
          ],
        ),
      ),
    ];
  }
}

/// A group in the list at the top right: its blueprint with the paper on
/// it, and its letter. A tap opens it on the desk, or closes it when it is
/// already open there; dragging it to the trash takes it apart.
class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.group,
    required this.tiles,
    required this.open,
    required this.theme,
    required this.onTap,
  });

  final AsmrGroup group;
  final AsmrPaperTiles tiles;
  final bool open;
  final AsmrTheme theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Group ${group.name}',
      child: GestureDetector(
        key: Key('asmr-group-${group.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: _chip(),
      ),
    );
  }

  Widget _chip() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: open ? 0.5 : 0.35),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: open ? 0.95 : 0.3),
          width: open ? 2.5 : 1.2,
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: CustomPaint(
                painter: _GroupThumbPainter(
                  group: group,
                  tiles: tiles,
                  theme: theme,
                ),
              ),
            ),
          ),
          Positioned(
            left: 4,
            top: 4,
            child: Container(
              width: 18,
              height: 18,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: group.hatch.color.withValues(alpha: open ? 0.95 : 0.7),
                shape: BoxShape.circle,
              ),
              child: Text(
                group.name,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupThumbPainter extends CustomPainter {
  const _GroupThumbPainter({
    required this.group,
    required this.tiles,
    required this.theme,
  });

  final AsmrGroup group;
  final AsmrPaperTiles tiles;
  final AsmrTheme theme;

  @override
  void paint(Canvas canvas, Size size) {
    final net = group.net;
    if (net.isEmpty) return;
    final box = net.bounds;
    final scale = math.min(
      size.width / math.max(box.width, 1e-6),
      size.height / math.max(box.height, 1e-6),
    );
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-box.center.dx, -box.center.dy);
    final faces = Path();
    for (final face in net.faces) {
      faces.addPolygon(face.ring, true);
    }
    canvas.drawPath(
      faces,
      Paint()..color = group.hatch.color.withValues(alpha: 0.15),
    );
    canvas.save();
    canvas.clipPath(faces);
    for (final piece in group.bound) {
      canvas.save();
      canvas.transform(piece.pose.storage);
      final path = Path()
        ..fillType = PathFillType.evenOdd
        ..addPolygon(piece.ring, true);
      for (final hole in piece.holes) {
        path.addPolygon(hole, true);
      }
      canvas.drawPath(path, tiles.paint(piece.paper));
      canvas.restore();
    }
    canvas.restore();
    canvas.drawPath(
      faces,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / scale
        ..color = theme.ink(
          AsmrThemeSlot.button,
          Colors.white.withValues(alpha: 0.85),
        ),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GroupThumbPainter old) => true;
}

/// The square button that turns the 3D view on and off. From 3D it is off
/// until faces are selected.
class _CubeToggle extends StatelessWidget {
  const _CubeToggle({
    required this.on,
    required this.onTap,
    required this.theme,
    this.enabled = true,
  });

  final bool on;
  final bool enabled;
  final VoidCallback onTap;
  final AsmrTheme theme;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: !enabled
          ? 'Select faces to craft'
          : on
          ? 'Craft on the desk'
          : 'Look at the cube',
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 160),
          opacity: enabled ? 1 : 0.4,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: on
                  ? theme.ink(
                      AsmrThemeSlot.button,
                      Colors.white.withValues(alpha: 0.18),
                    )
                  : Colors.black.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.ink(
                  AsmrThemeSlot.button,
                  Colors.white.withValues(alpha: on ? 0.85 : 0.3),
                ),
                width: on ? 2 : 1,
              ),
            ),
            child: Icon(
              Icons.view_in_ar,
              color: theme.ink(
                AsmrThemeSlot.button,
                Colors.white.withValues(alpha: on ? 1 : 0.7),
              ),
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
}

/// A group's unfolded blueprint replaces the circle while the reticle aims at it.
class _ReticleBlueprintPainter extends CustomPainter {
  const _ReticleBlueprintPainter(this.net);

  final AsmrNet net;

  @override
  void paint(Canvas canvas, Size size) {
    if (net.isEmpty) return;
    final box = net.bounds;
    final scale = math.min(
      (size.width - 6) / math.max(box.width, 1e-6),
      (size.height - 6) / math.max(box.height, 1e-6),
    );
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-box.center.dx, -box.center.dy);
    final ink = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 / scale
      ..strokeCap = StrokeCap.round;
    for (final edge in net.edges) {
      canvas.drawLine(edge.a, edge.b, ink);
    }
  }

  @override
  bool shouldRepaint(covariant _ReticleBlueprintPainter old) => old.net != net;
}
