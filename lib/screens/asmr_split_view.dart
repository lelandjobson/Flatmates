import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../asmr/asmr_cube.dart';
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
import '../asmr/asmr_session.dart';
import '../asmr/asmr_straight_edge.dart';
import '../asmr/hologram_painter.dart';
import '../asmr/hologram_selection.dart';
import '../gridcraft/edit.dart' show marqueePick, polygonInMarquee;
import '../gridcraft/folded_model.dart';
import '../gridcraft/model_painter.dart';
import '../gridcraft/wrap_cut.dart' show FaceNeighbor, faceAdjacency;
import '../papercut/camera.dart';
import '../ui/craft_palette.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';

/// The least share of the split height either pane keeps.
const double kAsmrSplitMin = 0.15;

/// The model pane's share of the split height, held so neither pane is
/// smaller than [kAsmrSplitMin] of it.
double asmrSplitFraction(double fraction) =>
    fraction.clamp(kAsmrSplitMin, 1 - kAsmrSplitMin);

enum _DeskTool { select, exacto, straight }

enum _ModelTool { orbit, select }

enum _Pane { model, desk }

enum _Drag {
  none,
  orbit,
  pan,
  marquee,
  cut,
  straight,
  move,
  rotate,
  pieceBox,
  deskPan,
  edgeSlide,
  edgeTurn,
}

enum _Bin { none, inventory, trash }

const double _kDividerHeight = 16;
const Size _kHandleSize = Size(44, 32);

const Duration _kPreselectFade = Duration(milliseconds: 180);
const Duration _kEdgeFade = Duration(milliseconds: 250);
const Duration _kOutlineFade = Duration(milliseconds: 250);
const Duration _kFlashFade = Duration(milliseconds: 600);
const Duration _kStraightEdgeFly = Duration(milliseconds: 450);
const Duration _kWarp = Duration(milliseconds: 360);

const double _kHoverFill = 0.55;
const double _kTapSlop = 8;
const Duration _kTapTime = Duration(milliseconds: 350);
const double _kOrbitPerPixel = 0.008;
const double _kMaxTilt = 85 * math.pi / 180;
const Offset _kKnifeLift = Offset(0, -56);
const double _kTickEvery = 4;
const int _kSplitCheckEvery = 4;
const double _kHandleLift = 30;
const double _kHandleRadius = 22;
const double _kHistoryPad = 32 * 1.5 - 8 - 16;
const int _kHistoryDepth = 40;

/// Desk units that fit across the desk pane's shorter side when it opens.
const double _kDeskSpan = 260;

final Vector3 _kModelUp = Vector3(0, 0, 1);

/// ASMR crafting on a split screen: the cube on top, the desk below. The
/// selected faces unfold on the desk as a cutting guide only. Paper sticks
/// to the cube when a piece is dragged up across the divider, and flies to
/// where it lay on the guide when the drag began.
class AsmrSplitView extends StatefulWidget {
  const AsmrSplitView({super.key, this.settings, this.sessionFile});

  /// Saved DevTools values. Null uses the file in the home directory.
  final AsmrDevSettings? settings;

  /// Where Save and Load keep the desk. Null uses
  /// `~/.flatmates/asmr_split_session.json`.
  final File? sessionFile;

  @override
  State<AsmrSplitView> createState() => _AsmrSplitViewState();
}

class _HoloEdge {
  _HoloEdge(this.edge);

  AsmrNetEdge edge;
  double opacity = 0;
  double target = 1;
}

class _Held {
  _Held(this.id, this.position, this.angle);

  final String id;
  final Offset position;
  final double angle;
}

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

class _CraftStep {
  _CraftStep({
    required this.desk,
    required this.bound,
    required this.picks,
    required this.nextSheet,
    required this.selectedIds,
    required this.stowed,
  });

  final List<AsmrPiece> desk;
  final List<AsmrPiece> bound;
  final List<HologramPick> picks;
  final int nextSheet;
  final Set<String> selectedIds;
  final List<AsmrPiece> stowed;
}

class _AsmrSplitViewState extends State<AsmrSplitView>
    with SingleTickerProviderStateMixin {
  late final FoldedModel _model = asmrCubeModel();
  late final List<List<FaceNeighbor?>> _adjacency = faceAdjacency(_model);
  final PapercutCamera _camera = PapercutCamera();
  final HologramSelection _selection = HologramSelection();
  final AsmrPaperTiles _tiles = AsmrPaperTiles();
  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Size _size = Size.zero;
  bool _posed = false;

  /// The model pane's share of the split height.
  double _split = 0.5;
  double _splitFrom = 0.5;
  double _splitDragFrom = 0;

  final Map<int, double> _faceFill = {};
  AsmrNet _net = AsmrNet.empty;
  final Map<String, _HoloEdge> _holoEdges = {};

  /// Paper on the desk. None of it is bound.
  final List<AsmrPiece> _desk = [];

  /// Paper on the model, each piece bound to the net it was sent with.
  final List<AsmrPiece> _bound = [];
  final List<AsmrFlight> _flights = [];
  final List<AsmrPiece> _stowed = [];

  Offset _deskOrigin = Offset.zero;
  double _deskScale = 2.5;
  _DeskTool _deskTool = _DeskTool.exacto;
  _ModelTool _modelTool = _ModelTool.orbit;
  int? _hoverFace;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  final Set<String> _selectedIds = {};
  Set<String>? _pieceBoxHome;
  final Set<String> _moveIds = {};
  _Bin _bin = _Bin.none;
  final GlobalKey _drawerKey = GlobalKey();
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
  _Pane _pane = _Pane.desk;
  Offset _dragStart = Offset.zero;
  Duration _dragStartTime = Duration.zero;
  bool _dragMoved = false;
  double _lastSpan = 0;
  Offset _lastFocal = Offset.zero;
  Offset _lastDesk = Offset.zero;
  double _rotateFrom = 0;
  double _rotateBase = 0;
  Offset _rotatePivot = Offset.zero;

  /// Where each piece Select is holding was picked up. A piece sent to the
  /// model goes to its spot on the guide from here.
  final List<_Held> _held = [];
  final List<_Warp> _warps = [];

  /// The move under way has crossed onto the model pane.
  bool _crossed = false;

  final List<_CraftStep> _undoStack = [];
  final List<_CraftStep> _redoStack = [];
  _CraftStep? _gestureBefore;
  List<HologramPick>? _marqueeHome;

  bool _edgeGrabbed = false;
  Offset _edgeHomeAnchor = Offset.zero;
  double _edgeHomeAngle = 0;

  final Map<int, AsmrScrub> _scrubs = {};
  final AsmrScrub _focalScrub = AsmrScrub();

  late final AsmrDevSettings _settings = widget.settings ?? AsmrDevSettings();
  AsmrDevSettings? _ownedSettings;
  bool _devToolsOpen = false;

  List<Offset>? _rawStroke;
  List<Offset>? _stroke;
  Offset? _segmentStart;
  Offset? _segmentEnd;
  List<List<Offset>> _segmentReach = const [];

  AsmrStraightEdge? _edge;
  bool _edgeOn = false;
  double _edgeShown = 0;
  int _edgeFlySide = 1;
  double _edgeTurnFrom = 0;
  double _edgeTurnBase = 0;
  Offset _edgePivot = Offset.zero;

  int? _knifeSide;
  Offset? _tipDesk;
  Offset? _finger;
  double _tickDistance = 0;
  int _sinceCheck = 0;

  @override
  void initState() {
    super.initState();
    if (widget.settings == null) _ownedSettings = _settings;
    _settings.addListener(_onDevSettings);
    _settings.load();
    _camera.setFocal(PapercutCamera.perspectiveFocalMm);
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _settings.removeListener(_onDevSettings);
    _ownedSettings?.dispose();
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

  // -------------------------------------------------------------------------
  // Layout and camera
  // -------------------------------------------------------------------------

  double get _splitHeight => math.max(0, _size.height - _kDividerHeight);

  double get _modelHeight => _splitHeight * _split;

  double get _deskTop => _modelHeight + _kDividerHeight;

  /// The model pane. Its top left is the screen's, so its points are the
  /// screen's too.
  Size get _viewport => Size(_size.width, _modelHeight);

  Rect get _deskRect =>
      Rect.fromLTRB(0, _deskTop, _size.width, math.max(_deskTop, _size.height));

  Offset get _deskCenter => _deskRect.center;

  Offset get _modelCenter => Offset(_size.width / 2, _modelHeight / 2);

  void _onLayout(Size size) {
    if (size == _size) return;
    final before = _deskCenter;
    _size = size;
    if (_posed) {
      _deskOrigin += _deskCenter - before;
      _refreshHover();
      return;
    }
    if (size.width <= 2 || _modelHeight <= 2) return;
    _posed = true;
    _deskOrigin = _deskCenter;
    _deskScale = _deskRect.shortestSide / _kDeskSpan;
    final center = _model.center;
    final half = _camera
        .frameSphere(center, _model.radius * 2.2, _viewport)
        .halfHeight;
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

  /// Moves the divider. The desk keeps the point at its pane's middle.
  void _setSplit(double fraction) {
    final before = _deskCenter;
    _split = asmrSplitFraction(fraction);
    _deskOrigin += _deskCenter - before;
    _refreshHover();
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
    if (_viewport.height < 2) return null;
    final ray = _camera.camera.unprojectRay(screen, _viewport);
    if (ray == null) return null;
    return pickFace(_model, ray.origin, ray.direction)?.face;
  }

  bool get _aimsWithCursor =>
      _lastKind == PointerDeviceKind.mouse ||
      _lastKind == PointerDeviceKind.trackpad;

  void _refreshHover() {
    final hover = _hover;
    final aim = _aimsWithCursor
        ? hover != null && hover.dy < _modelHeight
              ? hover
              : null
        : _modelCenter;
    _hoverFace = aim == null ? null : _faceAt(aim);
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
    );
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

  /// Lays out the guide for the selected faces. Paper already on the model
  /// keeps the net it was sent with.
  void _rebuildNet() {
    _net = unfoldSelection(_model, _adjacency, _selection.picks);
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

    for (var f = 0; f < _model.faces.length; f++) {
      final target = _selection.contains(f)
          ? 1.0
          : f == _hoverFace
          ? _kHoverFill
          : 0.0;
      _faceFill[f] = step(_faceFill[f] ?? 0, target, _kPreselectFade);
    }

    final gone = <String>[];
    for (final entry in _holoEdges.entries) {
      final edge = entry.value;
      edge.opacity = step(edge.opacity, edge.target, _kEdgeFade);
      if (edge.opacity == 0 && edge.target == 0) gone.add(entry.key);
    }
    gone.forEach(_holoEdges.remove);

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

    if (_warps.isNotEmpty) {
      final span = _kWarp.inMicroseconds / 1e6;
      _warps.removeWhere((warp) {
        warp.t = math.min(1, warp.t + dt / span);
        final i = _desk.indexWhere((p) => p.id == warp.id);
        if (i < 0) return true;
        final u = Curves.easeInOutCubic.transform(warp.t);
        var delta = warp.toAngle - warp.fromAngle;
        while (delta > math.pi) {
          delta -= math.pi * 2;
        }
        while (delta < -math.pi) {
          delta += math.pi * 2;
        }
        _desk[i] = _desk[i].copyWith(
          position: Offset.lerp(warp.from, warp.to, u)!,
          angle: warp.fromAngle + delta * u,
        );
        changed = true;
        return warp.t >= 1;
      });
    }

    if (_flights.isNotEmpty) {
      changed = true;
      var landed = false;
      _flights.removeWhere((flight) {
        if (!flight.advance(dt)) return false;
        _bound.add(flight.piece);
        landed = true;
        return true;
      });
      if (landed) {
        HapticFeedback.lightImpact();
        _refreshCoverage();
      }
    }
    if (changed || _complete) setState(() {});
  }

  // -------------------------------------------------------------------------
  // Desk
  // -------------------------------------------------------------------------

  Offset _toDesk(Offset screen) => (screen - _deskOrigin) / _deskScale;

  Offset _toScreen(Offset desk) => _deskOrigin + desk * _deskScale;

  AsmrPiece? get _selected {
    if (_selectedIds.length != 1) return null;
    final id = _selectedIds.single;
    for (final piece in _desk) {
      if (piece.id == id) return piece;
    }
    return null;
  }

  void _keepSelection() {
    _selectedIds.removeWhere((id) => !_desk.any((piece) => piece.id == id));
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
    for (final piece in _desk.reversed) {
      if (piece.contains(desk)) return piece;
    }
    return null;
  }

  void _zoomDesk(double factor, Offset focal) {
    final desk = _toDesk(focal);
    _deskScale = (_deskScale * factor).clamp(0.5, 24.0);
    _deskOrigin = focal - desk * _deskScale;
  }

  void _placeSheet(AsmrPaper paper, Offset desk) {
    setState(() {
      _pushUndo();
      final piece = AsmrPiece.sheet(
        id: '${paper.id}-${_nextSheet++}',
        paper: paper,
        at: desk,
      );
      _desk.add(piece);
      _selectedIds
        ..clear()
        ..add(piece.id);
      _flash[piece.id] = 0.6;
    });
  }

  void _place(AsmrPaper paper) => _placeSheet(paper, _toDesk(_deskCenter));

  void _replace(AsmrPiece piece) {
    final i = _desk.indexWhere((p) => p.id == piece.id);
    if (i >= 0) _desk[i] = piece;
  }

  void _applyCut(AsmrCut cut) {
    _pushUndo();
    _desk
      ..clear()
      ..addAll(cut.pieces);
    for (final id in cut.freed) {
      _flash[id] = 1;
    }
    _keepSelection();
    if (cut.split) HapticFeedback.mediumImpact();
  }

  void _refreshCoverage() {
    _coverage = faceCoverage(_model, _bound);
    final done =
        _coverage.length == _model.faces.length &&
        _coverage.values.every((c) => c >= kAsmrFilled);
    if (done && !_complete) HapticFeedback.heavyImpact();
    _complete = done;
  }

  /// Sends each held piece that lay on the guide when it was picked up to
  /// that spot on the model. The rest stay in hand, and go home on release.
  void _sendAcross() {
    _crossed = true;
    final net = _net;
    final sent = <String>{};
    for (final pose in _held) {
      if (net.isEmpty) break;
      final i = _desk.indexWhere((p) => p.id == pose.id);
      if (i < 0) continue;
      final piece = _desk[i];
      final bound = piece.copyWith(
        position: pose.position,
        angle: pose.angle,
        binding: net,
      );
      if (slicesOf(bound).isEmpty) continue;
      _flights.add(
        AsmrFlight(
          piece: bound,
          from: deskPaperToScreen(piece, _deskOrigin, _deskScale),
        ),
      );
      _desk.removeAt(i);
      sent.add(piece.id);
    }
    if (sent.isEmpty) {
      HapticFeedback.heavyImpact();
      return;
    }
    final before = _gestureBefore;
    if (before != null) {
      _undoStack.add(before);
      if (_undoStack.length > _kHistoryDepth) _undoStack.removeAt(0);
      _redoStack.clear();
      _gestureBefore = null;
    }
    _moveIds.removeAll(sent);
    _selectedIds.removeAll(sent);
    _held.removeWhere((pose) => sent.contains(pose.id));
    HapticFeedback.mediumImpact();
  }

  /// Eases every held piece back to where it was picked up.
  void _warpHome() {
    _warps.clear();
    for (final pose in _held) {
      final i = _desk.indexWhere((p) => p.id == pose.id);
      if (i < 0) continue;
      final piece = _desk[i];
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
  }

  // -------------------------------------------------------------------------
  // Session and history
  // -------------------------------------------------------------------------

  File get _sessionFile => widget.sessionFile ?? asmrSplitSessionFile();

  List<AsmrPiece> get _onModel => [
    ..._bound,
    for (final flight in _flights) flight.piece,
  ];

  void _saveSession() {
    final edge = _edge;
    final onModel = _onModel;
    AsmrSession(
      picks: _selection.picks,
      pieces: [..._desk, ...onModel],
      bindings: [
        for (final _ in _desk) const <HologramPick>[],
        for (final piece in onModel) picksOfNet(piece.binding ?? AsmrNet.empty),
      ],
      deskOrigin: _deskOrigin,
      deskScale: _deskScale,
      in3d: true,
      azimuth: _camera.azimuth,
      elevation: _camera.elevation,
      roll: _camera.roll,
      lookAt: _camera.lookAt,
      lookAtZ: _camera.lookAtZ,
      halfHeight: _camera.framedHalfHeightMm,
      focal: _camera.focalLengthMm,
      straightEdgeOn: _edgeOn,
      straightEdgeAnchor: edge?.anchor ?? _deskCenter,
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
      final nets = <String, AsmrNet>{};
      _desk.clear();
      _bound.clear();
      _flights.clear();
      for (var i = 0; i < session.pieces.length; i++) {
        final piece = session.pieces[i];
        final binding = session.bindings[i];
        if (binding.isEmpty) {
          _desk.add(piece.unbound());
          continue;
        }
        final key = [for (final pick in binding) '${pick.face}<${pick.from}'];
        final net = nets[key.join(',')] ??= unfoldSelection(
          _model,
          _adjacency,
          binding,
        );
        _bound.add(piece.copyWith(binding: net));
      }
      var next = 0;
      for (final piece in [..._desk, ..._bound]) {
        final tail = int.tryParse(piece.id.split('-').last);
        if (tail != null && tail >= next) next = tail + 1;
      }
      _nextSheet = next;
      _flash.clear();
      _selection.replace(session.picks);
      _rebuildNet();
      _selectedIds.clear();
      _deskOrigin = session.deskOrigin;
      _deskScale = session.deskScale;
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

  /// Clears the desk. Paper on the model stays.
  void _reset() {
    setState(() {
      _pushUndo();
      _desk.clear();
      _selectedIds.clear();
      _flash.clear();
    });
  }

  _CraftStep _capture() => _CraftStep(
    desk: List.of(_desk),
    bound: _onModel,
    picks: List.of(_selection.picks),
    nextSheet: _nextSheet,
    selectedIds: Set.of(_selectedIds),
    stowed: List.of(_stowed),
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
          p.ring.length != q.ring.length ||
          p.holes.length != q.holes.length ||
          p.scores.length != q.scores.length ||
          !identical(p.binding, q.binding)) {
        return false;
      }
    }
    return true;
  }

  bool _sameCraft(_CraftStep a, _CraftStep b) {
    if (a.nextSheet != b.nextSheet || a.picks.length != b.picks.length) {
      return false;
    }
    for (var i = 0; i < a.picks.length; i++) {
      if (a.picks[i] != b.picks[i]) return false;
    }
    return _samePieces(a.desk, b.desk) &&
        _samePieces(a.bound, b.bound) &&
        _samePieces(a.stowed, b.stowed);
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
  }

  void _restore(_CraftStep step) {
    _desk
      ..clear()
      ..addAll(step.desk);
    _bound
      ..clear()
      ..addAll(step.bound);
    _flights.clear();
    _nextSheet = step.nextSheet;
    _stowed
      ..clear()
      ..addAll(step.stowed);
    _selection.replace(step.picks);
    _rebuildNet();
    _selectedIds
      ..clear()
      ..addAll(step.selectedIds);
    _keepSelection();
    _flash.clear();
    _warps.clear();
    _held.clear();
    _moveIds.clear();
    _crossed = false;
    _bin = _Bin.none;
    _pieceBoxHome = null;
    _gestureBefore = null;
    _dropStroke();
    _cancelStraight();
    _marqueeStart = null;
    _marqueeEnd = null;
    _marqueeHome = null;
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
    final edge = _liveEdge;
    _knifeSide = edge?.sideOf(_knifeAt(pointer));
    final tip = _toDesk(_bladeAt(pointer));
    _tipDesk = tip;
    _finger = pointer;
    _rawStroke = [tip];
    _stroke = [tip];
    _tickDistance = 0;
    _sinceCheck = 0;
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
    final stroke = _stroke!;
    final added = rawStroke.length - before;
    if (added <= 0) return;
    if (_pieceAt(tip) != null) {
      _tickDistance += added * kAsmrStrokeSpacing;
      if (_tickDistance >= _kTickEvery) {
        _tickDistance = 0;
        HapticFeedback.selectionClick();
      }
    }
    _sinceCheck += added;
    if (_sinceCheck < _kSplitCheckEvery) return;
    _sinceCheck = 0;
    final cut = cutPieces(_desk, stroke, keepScores: false, finished: false);
    if (cut == null || !cut.split) return;
    _applyCut(cut);
    final end = rawStroke.last;
    _rawStroke = [end];
    _stroke = [end];
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
    final cut = cutPieces(_desk, stroke);
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
    _segmentReach = straightCutPreview(_desk, start, end, lo: lo, hi: hi);
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
    final cut = cutPiecesAlongLine(_desk, start, end, lo: lo, hi: hi);
    if (cut != null) _applyCut(cut);
  }

  // -------------------------------------------------------------------------
  // Straight edge
  // -------------------------------------------------------------------------

  AsmrStraightEdge? get _liveEdge => _edgeOn && _edgeShown >= 1 ? _edge : null;

  double get _edgeFly {
    final t = _edgeOn
        ? Curves.easeOutCubic.transform(_edgeShown)
        : Curves.easeInCubic.transform(_edgeShown);
    return (1 - t) *
        (_size.longestSide + kStraightEdgeThickness * 2) *
        _edgeFlySide;
  }

  Offset? get _edgeHandle => _edge?.rotateHandle(_deskCenter);

  void _toggleEdge() {
    setState(() {
      final edge = _edge;
      if (_edgeOn) {
        _edgeOn = false;
        if (edge != null) {
          _edgeFlySide = edge.across(_deskCenter) <= 0 ? 1 : -1;
        }
        if (_drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn) {
          _drag = _Drag.none;
        }
      } else {
        _edgeOn = true;
        _edge ??= AsmrStraightEdge(anchor: _deskCenter);
      }
    });
  }

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
      _edgePivot = edge.nearestOnMiddle(_deskCenter);
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

  void _settleEdge() {
    final edge = _edge;
    if (edge == null) return;
    _edge = edge.copyWith(anchor: edge.nearestOnMiddle(_deskCenter));
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

  void _dropStroke() {
    _rawStroke = null;
    _stroke = null;
    _finger = null;
    _tipDesk = null;
    _knifeSide = null;
  }

  /// Drops the gesture under way. Pieces in hand ease back to where they
  /// were picked up; pieces already sent to the model keep flying.
  void _cancelGesture() {
    final marquee = _marqueeHome;
    final pieceBox = _pieceBoxHome;
    final edgeGrabbed = _edgeGrabbed;
    final drag = _drag;
    if (drag == _Drag.none &&
        _held.isEmpty &&
        marquee == null &&
        pieceBox == null &&
        !edgeGrabbed) {
      return;
    }
    if (drag == _Drag.cut) _dropStroke();
    if (drag == _Drag.straight) _cancelStraight();
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
    _warpHome();
    _held.clear();
    _moveIds.clear();
    _crossed = false;
    _bin = _Bin.none;
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
    final first = _pointers.isEmpty;
    _pointers[event.pointer] = event.localPosition;
    if (first) {
      _scrubs.clear();
    }
    _focalScrub.reset();
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
      _pane = event.localPosition.dy < _modelHeight ? _Pane.model : _Pane.desk;
      if (_pane == _Pane.model) {
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
    _lastDesk = desk;
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
      _crossed = false;
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
        for (final piece in _desk)
          if (_moveIds.contains(piece.id)) piece,
      ];
      _desk.removeWhere((piece) => _moveIds.contains(piece.id));
      _desk
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
        for (final piece in _desk)
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

  _Bin _binAt(Offset local) {
    if (_inside(_trashKey, local)) return _Bin.trash;
    if (_inside(_drawerKey, local)) return _Bin.inventory;
    return _Bin.none;
  }

  void _takeHeld(List<AsmrPiece> into) {
    final taken = _desk.where((piece) => _moveIds.contains(piece.id)).toList();
    _desk.removeWhere((piece) => _moveIds.contains(piece.id));
    into.addAll(taken);
    _selectedIds.removeAll(_moveIds);
    _moveIds.clear();
    _held.clear();
    _warps.clear();
  }

  void _unstow(AsmrPiece piece) {
    setState(() {
      _pushUndo();
      _stowed.remove(piece);
      final back = piece.copyWith(position: _toDesk(_deskCenter));
      _desk.add(back);
      _setDeskTool(_DeskTool.select);
      _selectedIds
        ..clear()
        ..add(back.id);
    });
  }

  void _setDeskTool(_DeskTool tool) {
    _deskTool = tool;
    if (tool != _DeskTool.select) _selectedIds.clear();
    if (tool != _DeskTool.exacto) _tipDesk = null;
    if (tool != _DeskTool.straight || _drag == _Drag.straight) {
      _cancelStraight();
    }
    if (_drag == _Drag.straight) _drag = _Drag.none;
  }

  void _beginTwoFinger() {
    setState(() {
      if (_drag == _Drag.cut) _dropStroke();
      if (_drag == _Drag.straight) _cancelStraight();
      if (_drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn) _settleEdge();
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
        case _Drag.move:
          final desk = _toDesk(event.localPosition);
          final step = desk - _lastDesk;
          for (final id in _moveIds) {
            final i = _desk.indexWhere((piece) => piece.id == id);
            if (i < 0) continue;
            final piece = _desk[i];
            _desk[i] = piece.copyWith(position: piece.position + step);
          }
          _lastDesk = desk;
          if (!_crossed && event.localPosition.dy < _modelHeight) {
            _sendAcross();
          }
          _bin = _crossed ? _Bin.none : _binAt(event.localPosition);
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
          _deskOrigin += delta;
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
    final scale = _lastSpan > 1 && span > 1 ? span / _lastSpan : 1.0;
    final delta = focal - _lastFocal;
    _lastFocal = focal;
    _lastSpan = span;
    if (_pane == _Pane.model) {
      _panView(delta);
      if ((scale - 1).abs() > 1e-4) _camera.zoomByScale(scale);
    } else {
      _deskOrigin += delta;
      if ((scale - 1).abs() > 1e-4) _zoomDesk(scale, focal);
    }
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

  void _onPointerUp(PointerEvent event) {
    _pointers.remove(event.pointer);
    _scrubs.remove(event.pointer);
    _focalScrub.reset();
    if (_pointers.isNotEmpty) {
      _lastFocal = _focal();
      _lastSpan = _span();
      return;
    }
    final tap = !_dragMoved && event.timeStamp - _dragStartTime < _kTapTime;
    setState(() {
      switch (_drag) {
        case _Drag.orbit:
          break;
        case _Drag.marquee:
          if (tap) {
            final face = _faceAt(event.localPosition);
            final picks = face == null
                ? const <HologramPick>[]
                : [HologramPick(face)];
            if (_selection.replace(picks)) _rebuildNet();
          }
          _marqueeStart = null;
          _marqueeEnd = null;
        case _Drag.cut:
          _endCut();
        case _Drag.straight:
          _endStraight();
        case _Drag.pieceBox:
          if (tap) _selectedIds.clear();
          _marqueeStart = null;
          _marqueeEnd = null;
          _pieceBoxHome = null;
        case _Drag.move:
          if (_crossed) {
            _warpHome();
            _gestureBefore = null;
          } else {
            final bin = _dragMoved ? _binAt(event.localPosition) : _Bin.none;
            if (bin == _Bin.trash) {
              _takeHeld(<AsmrPiece>[]);
            } else if (bin == _Bin.inventory) {
              _takeHeld(_stowed);
            }
          }
          _bin = _Bin.none;
        case _Drag.rotate:
          break;
        case _Drag.deskPan:
          if (tap && _deskTool == _DeskTool.select) _selectedIds.clear();
        case _Drag.edgeSlide:
        case _Drag.edgeTurn:
          _settleEdge();
        case _Drag.pan:
        case _Drag.none:
          break;
      }
      _drag = _Drag.none;
      _crossed = false;
      _held.clear();
      _moveIds.clear();
      _marqueeHome = null;
      _pieceBoxHome = null;
      _edgeGrabbed = false;
      _commitGesture();
    });
  }

  void _onPointerHover(PointerHoverEvent event) {
    _lastKind = event.kind;
    setState(() {
      _hover = event.localPosition;
      _refreshHover();
      if (_deskTool == _DeskTool.exacto) {
        _tipDesk = event.localPosition.dy >= _deskTop
            ? _toDesk(event.localPosition)
            : null;
      }
    });
  }

  bool _inModel(Offset local) => local.dy < _modelHeight;

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    final factor = math.exp(-event.scrollDelta.dy * 0.002);
    setState(() {
      if (_inModel(event.localPosition)) {
        _camera.zoomByScale(factor);
      } else {
        _zoomDesk(factor, event.localPosition);
      }
    });
  }

  double _panZoomScale = 1;
  bool _panZoomModel = false;

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _lastKind = event.kind;
    _panZoomScale = 1;
    _panZoomModel = _inModel(event.localPosition);
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    final factor = _panZoomScale > 0 ? event.scale / _panZoomScale : 1.0;
    _panZoomScale = event.scale;
    setState(() {
      if (_panZoomModel) {
        _panView(event.localPanDelta);
        if ((factor - 1).abs() > 1e-4) _camera.zoomByScale(factor);
      } else {
        _deskOrigin += event.localPanDelta;
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
      ),
  ];

  bool get _showKnife => _deskTool == _DeskTool.exacto;

  Offset? get _knifeScreen {
    if (!_showKnife || _tipDesk == null) return null;
    return _finger != null ? _bladeAt(_finger!) : _toScreen(_tipDesk!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAsmrDeskColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _onLayout(constraints.biggest);
          final deskClip = _RectClip(_deskRect);
          return Stack(
            key: _stackKey,
            children: [
              Positioned.fill(child: _input(deskClip)),
              Positioned.fill(
                child: IgnorePointer(
                  child: ClipRect(
                    clipper: deskClip,
                    child: _straightEdgeLayer(),
                  ),
                ),
              ),
              if (_knifeScreen case final tip?)
                Positioned.fill(
                  key: const ValueKey('asmr-knife'),
                  child: IgnorePointer(
                    child: ClipRect(
                      clipper: deskClip,
                      child: CustomPaint(
                        painter: AsmrKnifePainter(tip: tip, finger: _finger),
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
                      ),
                    ),
                  ),
                ),
              if (!_aimsWithCursor && _modelTool == _ModelTool.orbit)
                Positioned(
                  key: const ValueKey('asmr-crosshair'),
                  left: 0,
                  top: 0,
                  right: 0,
                  height: _modelHeight,
                  child: ViewCrosshair(selectable: _hoverFace != null),
                ),
              ..._divider(),
              ..._chrome(context),
              if (_flights.isNotEmpty)
                Positioned.fill(
                  key: const ValueKey('asmr-flight'),
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

  /// Both panes, under one listener so a drag keeps going across the
  /// divider.
  Widget _input(_RectClip deskClip) {
    final selected = _selected;
    final showStraight = _deskTool == _DeskTool.straight;
    return DragTarget<AsmrPaper>(
      onAcceptWithDetails: (details) {
        final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(
          details.offset + kAsmrSwatchSize.center(Offset.zero),
        );
        setState(() => _setDeskTool(_DeskTool.select));
        _placeSheet(
          details.data,
          _toDesk(_deskRect.contains(local) ? local : _deskCenter),
        );
      },
      builder: (context, candidate, rejected) => MouseRegion(
        cursor: _showKnife
            ? SystemMouseCursors.none
            : showStraight
            ? SystemMouseCursors.precise
            : MouseCursor.defer,
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
              Positioned.fill(
                child: ClipRect(
                  clipper: deskClip,
                  child: CustomPaint(
                    painter: AsmrDeskPainter(
                      pieces: List.of(_desk),
                      tiles: _tiles,
                      origin: _deskOrigin,
                      scale: _deskScale,
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
                      shadowThrow: _settings.shadowThrow,
                      shadowSpread: _settings.shadowSpread,
                      shadowColor: _settings.shadowPaint,
                      darkOverlay: _settings.darkOverlay,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              Positioned.fill(
                child: ClipRect(
                  clipper: deskClip,
                  child: CustomPaint(
                    painter: HologramPainter(
                      edges: _edgeViews,
                      faces: [for (final face in _net.faces) face.ring],
                      origin: _deskOrigin,
                      scale: _deskScale,
                      contrast: 1,
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                height: _modelHeight,
                child: ClipRect(
                  key: const Key('asmr-split-model'),
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [kAsmrSkyColor, kAsmrDeskColor],
                      ),
                    ),
                    child: _modelLayer(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _straightEdgeLayer() {
    final edge = _edge;
    if (edge == null || _edgeShown <= 0) return const SizedBox.shrink();
    return CustomPaint(
      key: const Key('asmr-straight-edge'),
      painter: AsmrStraightEdgePainter(
        edge: edge,
        fly: _edgeFly,
        handle: _edgeHandle,
        pressed: _drag == _Drag.edgeSlide || _drag == _Drag.edgeTurn,
      ),
      child: const SizedBox.expand(),
    );
  }

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
          pieces: List.of(_bound),
          tiles: _tiles,
          add: add,
          highlight: Map.of(_faceFill),
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  /// The bar between the panes, and the handle at its left that moves it.
  List<Widget> _divider() => [
    Positioned(
      left: 0,
      right: 0,
      top: _modelHeight,
      height: _kDividerHeight,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            border: Border.symmetric(
              horizontal: BorderSide(
                color: Colors.white.withValues(alpha: 0.14),
              ),
            ),
          ),
        ),
      ),
    ),
    Positioned(
      left: 10,
      top: _modelHeight + _kDividerHeight / 2 - _kHandleSize.height / 2,
      child: Tooltip(
        message: 'Drag to resize',
        child: GestureDetector(
          key: const Key('asmr-split-handle'),
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onVerticalDragStart: (details) {
            _splitFrom = _split;
            _splitDragFrom = details.globalPosition.dy;
          },
          onVerticalDragUpdate: (details) {
            final height = _splitHeight;
            if (height <= 0) return;
            final moved = details.globalPosition.dy - _splitDragFrom;
            setState(() => _setSplit(_splitFrom + moved / height));
          },
          child: Container(
            width: _kHandleSize.width,
            height: _kHandleSize.height,
            decoration: BoxDecoration(
              color: const Color(0xFF2B2D4A),
              borderRadius: BorderRadius.circular(_kHandleSize.height / 2),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            child: const Icon(
              Icons.drag_handle,
              color: Colors.white70,
              size: 20,
            ),
          ),
        ),
      ),
    ),
  ];

  int get _filledCount =>
      _coverage.values.where((c) => c >= kAsmrFilled).length;

  String get _hint => switch (_deskTool) {
    _DeskTool.select =>
      'Drag a piece up onto the cube. It goes where it lay on the outline when you picked it up.',
    _DeskTool.straight =>
      'Drag to set a line. Each piece it touches is cut right through along it.',
    _DeskTool.exacto =>
      'Lay paper from the drawer and cut along the glowing outline.',
  };

  List<Widget> _chrome(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    final compact = _modelHeight < 200;
    return [
      Positioned(
        top: padding.top + 8,
        left: 8,
        child: AsmrRoundButton(
          icon: Icons.arrow_back,
          tooltip: 'Back',
          onTap: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.goNamed('dev_routes');
            }
          },
        ),
      ),
      Positioned(
        top: padding.top + 14,
        left: 0,
        right: 0,
        child: IgnorePointer(
          child: Center(
            child: Text(
              'Faces filled  $_filledCount / ${_model.faces.length}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 14,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        top: _modelHeight - (compact ? 58 : 72) - 2,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            HudToolCarousel<_ModelTool>(
              compact: compact,
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
                AsmrTextLink(
                  label: 'Save',
                  buttonKey: const Key('asmr-save'),
                  onTap: _saveSession,
                ),
                AsmrTextLink(
                  label: 'Load',
                  buttonKey: const Key('asmr-load'),
                  onTap: _loadSession,
                ),
                AsmrRoundButton(
                  icon: Icons.restart_alt,
                  tooltip: 'Clear the desk',
                  onTap: _reset,
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
                child: AsmrDevPanel(settings: _settings),
              ),
          ],
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
                  icon: Icons.content_cut,
                  label: 'Exacto',
                  fill: CraftPalette.scarlet.fill,
                ),
                HudCarouselItem(
                  value: _DeskTool.straight,
                  icon: Icons.horizontal_rule,
                  label: 'Straight cut',
                  fill: CraftPalette.ginger.fill,
                ),
              ],
              selected: _deskTool,
              onSelect: (tool) => setState(() => _setDeskTool(tool)),
            ),
            Container(
              width: 1,
              height: 32,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Colors.white24,
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
        top: _deskTop + 8,
        bottom: padding.bottom + 8,
        right: 0,
        child: Center(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AsmrPaperDrawer(
                  key: _drawerKey,
                  tiles: _tiles,
                  onTap: _place,
                  stowed: _stowed,
                  onUnstow: _unstow,
                  accepting: _bin == _Bin.inventory,
                ),
                const SizedBox(height: 18),
                AsmrTrashButton(key: _trashKey, hot: _bin == _Bin.trash),
              ],
            ),
          ),
        ),
      ),
      if (_completeShown > 0)
        Positioned(
          key: const ValueKey('asmr-complete'),
          left: 0,
          right: 0,
          top: 0,
          height: _modelHeight,
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
}

class _RectClip extends CustomClipper<Rect> {
  const _RectClip(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _RectClip old) => old.rect != rect;
}
