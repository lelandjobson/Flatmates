import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../asmr/asmr_cube.dart';
import '../asmr/asmr_dev.dart';
import '../asmr/asmr_desk_painter.dart';
import '../asmr/asmr_group.dart';
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
import '../gridcraft/edit.dart' show MarqueePick, marqueePick, polygonInMarquee;
import '../gridcraft/folded_model.dart';
import '../gridcraft/model_painter.dart';
import '../gridcraft/wrap_cut.dart' show FaceNeighbor, faceAdjacency;
import '../papercut/camera.dart';
import '../ui/craft_palette.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';

enum _DeskTool { select, exacto, straight }

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

/// Seconds for the hologram's 3D framing to settle most of the way.
const double _kHoloSettle = 0.12;

/// Fill on the face under the aim, against 1 on a selected face.
const double _kHoverFill = 0.55;

const double _kTapSlop = 8;
const Duration _kTapTime = Duration(milliseconds: 350);
const double _kOrbitPerPixel = 0.008;
const double _kMaxTilt = 85 * math.pi / 180;

/// On touch the blade cuts this far above the finger, so the finger does
/// not hide the cut.
const Offset _kKnifeLift = Offset(0, -56);

/// Desk units of cut between haptic ticks.
const double _kTickEvery = 4;

/// Stroke samples between checks whether the cut has freed a piece yet.
const int _kSplitCheckEvery = 4;

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

/// Share of the screen the hologram fills in 3D, and the most of the
/// shorter side one cube face may take.
const double _kHoloFill = 0.75;
const double _kHoloFaceMax = 0.4;

final Vector3 _kModelUp = Vector3(0, 0, 1);

/// ASMR crafting: orbit the cube in 3D, gather faces into a glowing hologram
/// of their unfolded blueprint with the select tool's marquee, then cut
/// patterned paper over it on the 2D desk behind, freehand or along a
/// dragged segment. Paper cut free over the hologram wraps those faces,
/// until every face is filled.
class AsmrView extends StatefulWidget {
  const AsmrView({super.key, this.settings, this.sessionFile});

  /// Saved DevTools values. Null uses the file in the home directory.
  final AsmrDevSettings? settings;

  /// Where Save and Load keep the desk. Null uses `~/.flatmates/asmr_session.json`.
  final File? sessionFile;

  @override
  State<AsmrView> createState() => _AsmrViewState();
}

class _HoloEdge {
  _HoloEdge(this.edge);

  AsmrNetEdge edge;
  double opacity = 0;
  double target = 1;
}

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

/// Where a dragged selection was released.
enum _Bin { none, inventory, trash }

/// Where a piece was when Select picked it up.
class _Held {
  _Held(this.id, this.position, this.angle);

  final String id;
  final Offset position;
  final double angle;
}

/// Desk paper and the hologram it was cut against, for one undo step.
class _CraftStep {
  _CraftStep({
    required this.loose,
    required this.groups,
    required this.picks,
    required this.nextSheet,
    required this.selectedIds,
    required this.stowed,
  });

  final List<AsmrPiece> loose;
  final List<AsmrGroup> groups;
  final List<HologramPick> picks;
  final int nextSheet;
  final Set<String> selectedIds;
  final List<AsmrPiece> stowed;
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
  late final FoldedModel _model = asmrCubeModel();
  late final List<List<FaceNeighbor?>> _adjacency = faceAdjacency(_model);
  final PapercutCamera _camera = PapercutCamera();
  final HologramSelection _selection = HologramSelection();
  final AsmrPaperTiles _tiles = AsmrPaperTiles();
  final GlobalKey _stackKey = GlobalKey();
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  Size _viewport = Size.zero;
  bool _posed = false;

  bool _in3d = true;
  double _modeProgress = 1;
  double get _blend => Curves.easeInOutCubic.transform(_modeProgress);

  final Map<int, double> _faceFill = {};
  AsmrNet _net = AsmrNet.empty;
  final Map<String, _HoloEdge> _holoEdges = {};
  double _holoScale = 0;

  /// Paper laid with no faces selected.
  final List<AsmrPiece> _loose = [];

  /// A desk for faces that have no group yet. Opening the desk makes one.
  final List<AsmrPiece> _ungrouped = [];
  final List<AsmrGroup> _groups = [];

  /// The group of the selected faces, whose paper the desk shows.
  AsmrGroup? _group;

  List<AsmrPiece> get _pieces =>
      _group?.pieces ?? (_selection.picks.isEmpty ? _loose : _ungrouped);

  Iterable<AsmrPiece> get _allPieces => [
    ..._loose,
    for (final group in _groups) ...group.pieces,
  ];
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
  final List<AsmrPiece> _stowed = [];
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
  Offset _dragStart = Offset.zero;
  Duration _dragStartTime = Duration.zero;
  bool _dragMoved = false;
  double _lastSpan = 0;
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

  /// The side of the straight edge the exacto cut under way keeps to.
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

  void _onLayout(Size size) {
    if (size == _viewport) return;
    _viewport = size;
    if (!_posed && size.width > 2 && size.height > 2) {
      _posed = true;
      _deskOrigin = Offset(size.width / 2, size.height / 2);
      _deskScale = size.shortestSide / _kDeskSpan;
      final center = _model.center;
      final half = _camera
          .frameSphere(center, _model.radius * 2.2, size)
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
      _holoScale = _holoTarget();
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

  /// The face under the aim, shown while it is only being looked at. The
  /// hologram itself changes only from the select tool.
  void _refreshHover() {
    if (!_in3d) {
      _hoverFace = null;
      return;
    }
    final aim = _aim;
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
      _selectedIds.clear();
      _held.clear();
      _moveIds.clear();
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
    _attachToBlueprint();
  }

  /// Gives the selected faces a group when the desk opens on them.
  void _ensureGroup() {
    if (_group != null || _selection.picks.isEmpty) return;
    final group = AsmrGroup(
      letter: nextGroupLetter(_groups),
      picks: List.of(_selection.picks),
      net: _net,
      pieces: List.of(_ungrouped),
    );
    _ungrouped.clear();
    _groups.add(group);
    _group = group;
    _attachToBlueprint();
  }

  /// Drops each group with no paper on its faces. What paper it had left
  /// goes to the drawer.
  void _pruneGroups() {
    for (final group in _groups.where((g) => !g.anchored).toList()) {
      _stowed.addAll([for (final piece in group.pieces) piece.unbound()]);
      _groups.remove(group);
      if (identical(group, _group)) {
        _group = null;
        _selectedIds.clear();
      }
    }
  }

  /// The group a tap on [face] takes: the open one if it has that face,
  /// else the latest made that does.
  AsmrGroup? _groupWith(int face) {
    final open = _group;
    if (open != null && open.faces.contains(face)) return open;
    for (final group in _groups.reversed) {
      if (group.faces.contains(face)) return group;
    }
    return null;
  }

  void _openGroup(AsmrGroup group) {
    setState(() {
      _selection.replace(group.picks);
      _rebuildNet();
    });
  }

  double _holoTarget() {
    if (_viewport.width < 2) return _holoScale;
    final bounds = _net.isEmpty
        ? const Rect.fromLTWH(0, 0, 50, 50)
        : _net.bounds;
    final faceSide = kAsmrNetScale * 5;
    return [
      _kHoloFill * _viewport.width / math.max(bounds.width, 1),
      _kHoloFill * _viewport.height / math.max(bounds.height, 1),
      _kHoloFaceMax * _viewport.shortestSide / faceSide,
    ].reduce(math.min);
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

    _modeProgress = step(_modeProgress, _in3d ? 1 : 0, _kModeDuration);

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

    final holo = _holoTarget();
    if ((holo - _holoScale).abs() > 1e-4) {
      _holoScale += (holo - _holoScale) * (1 - math.exp(-dt / _kHoloSettle));
      changed = true;
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
    _edgeShown = step(_edgeShown, _edgeOn ? 1 : 0, _kStraightEdgeFly);

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

  void _toggleMode() {
    setState(() {
      _in3d = !_in3d;
      if (_in3d) {
        _pruneGroups();
      } else {
        _ensureGroup();
      }
      _rawStroke = null;
      _stroke = null;
      _knifeSide = null;
      _segmentStart = null;
      _segmentEnd = null;
      _segmentReach = const [];
      _tipDesk = null;
      _finger = null;
      _marqueeStart = null;
      _marqueeEnd = null;
      _drag = _Drag.none;
    });
  }

  // -------------------------------------------------------------------------
  // Desk geometry
  // -------------------------------------------------------------------------

  Offset _toDesk(Offset screen) => (screen - _deskOrigin) / _deskScale;

  Offset _toScreen(Offset desk) => _deskOrigin + desk * _deskScale;

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
      _pieces.add(piece);
      _selectedIds
        ..clear()
        ..add(piece.id);
      _flash[piece.id] = 0.6;
      _attachToBlueprint();
    });
  }

  void _replace(AsmrPiece piece) {
    final i = _pieces.indexWhere((p) => p.id == piece.id);
    if (i >= 0) _pieces[i] = piece;
  }

  /// Attaches every piece of the open group that overlaps its blueprint's
  /// outer edge to the group's faces. Attached pieces stay attached when the
  /// selection moves on.
  void _attachToBlueprint() {
    final group = _group;
    if (group == null || group.net.isEmpty) return;
    final pieces = group.pieces;
    var changed = false;
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      if (identical(piece.binding, group.net)) continue;
      if (!onBlueprintEdge(piece, group.net)) continue;
      pieces[i] = piece.copyWith(binding: group.net);
      changed = true;
    }
    if (changed) _refreshCoverage();
  }

  void _applyCut(AsmrCut cut) {
    _pushUndo();
    _pieces
      ..clear()
      ..addAll(cut.pieces);
    _attachToBlueprint();
    for (final id in cut.freed) {
      _flash[id] = 1;
    }
    _keepSelection();
    if (cut.split) HapticFeedback.mediumImpact();
    _refreshCoverage();
  }

  void _refreshCoverage() {
    _coverage = faceCoverage(_model, _allPieces);
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
    for (final piece in _loose) {
      pieces.add(piece);
      pieceGroups.add(null);
    }
    for (final group in _groups) {
      for (final piece in group.pieces) {
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
      pieceGroups: pieceGroups,
      deskOrigin: _deskOrigin,
      deskScale: _deskScale,
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
      final groups = <int, AsmrGroup>{
        for (final entry in session.groups.entries)
          entry.key: AsmrGroup(
            letter: entry.key,
            picks: entry.value,
            net: unfoldSelection(_model, _adjacency, entry.value),
          ),
      };
      _loose.clear();
      _ungrouped.clear();
      for (var i = 0; i < session.pieces.length; i++) {
        final piece = session.pieces[i];
        final binding = session.bindings[i];
        var group = groups[session.pieceGroups[i]];
        if (group == null && binding.isNotEmpty) {
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
        if (group == null) {
          _loose.add(piece);
        } else {
          group.pieces.add(
            binding.isEmpty ? piece : piece.copyWith(binding: group.net),
          );
        }
      }
      _groups
        ..clear()
        ..addAll(groups.values.toList()..sort((a, b) => a.letter - b.letter));
      _group = null;
      var next = 0;
      for (final piece in _allPieces) {
        final tail = int.tryParse(piece.id.split('-').last);
        if (tail != null && tail >= next) next = tail + 1;
      }
      _nextSheet = next;
      _flash.clear();
      _in3d = session.in3d;
      if (_in3d) _pruneGroups();
      _selection.replace(session.picks);
      _rebuildNet();
      if (!_in3d) _ensureGroup();
      _selectedIds.clear();
      _deskOrigin = session.deskOrigin;
      _deskScale = session.deskScale;
      _modeProgress = session.in3d ? 1 : 0;
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

  /// Clears the paper of the open desk. Other groups keep theirs.
  void _reset() {
    setState(() {
      _pushUndo();
      _pieces.clear();
      _selectedIds.clear();
      _flash.clear();
      _refreshCoverage();
    });
  }

  _CraftStep _capture() => _CraftStep(
    loose: List.of(_loose),
    groups: [for (final group in _groups) group.copy()],
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
    if (a.groups.length != b.groups.length) return false;
    for (var i = 0; i < a.groups.length; i++) {
      if (a.groups[i].letter != b.groups[i].letter ||
          !_samePieces(a.groups[i].pieces, b.groups[i].pieces)) {
        return false;
      }
    }
    return _samePieces(a.loose, b.loose) && _samePieces(a.stowed, b.stowed);
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
    _loose
      ..clear()
      ..addAll(step.loose);
    _ungrouped.clear();
    _groups
      ..clear()
      ..addAll([for (final group in step.groups) group.copy()]);
    _group = null;
    _nextSheet = step.nextSheet;
    _stowed
      ..clear()
      ..addAll(step.stowed);
    _selection.replace(step.picks);
    _rebuildNet();
    if (!_in3d) _ensureGroup();
    _selectedIds
      ..clear()
      ..addAll(step.selectedIds);
    _keepSelection();
    _flash.clear();
    _warps.clear();
    _held.clear();
    _moveIds.clear();
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
    final cut = cutPieces(_pieces, stroke, keepScores: false, finished: false);
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

  _Bin _binAt(Offset local) {
    if (_inside(_trashKey, local)) return _Bin.trash;
    if (_inside(_drawerKey, local)) return _Bin.inventory;
    return _Bin.none;
  }

  void _takeHeld(List<AsmrPiece> into) {
    final taken = _pieces
        .where((piece) => _moveIds.contains(piece.id))
        .toList();
    _pieces.removeWhere((piece) => _moveIds.contains(piece.id));
    into.addAll([for (final piece in taken) piece.unbound()]);
    _selectedIds.removeAll(_moveIds);
    _moveIds.clear();
    _held.clear();
    _warps.clear();
    _refreshCoverage();
  }

  void _unstow(AsmrPiece piece) {
    setState(() {
      _pushUndo();
      _stowed.remove(piece);
      final back = piece.copyWith(position: _toDesk(_center));
      _pieces.add(back);
      _setDeskTool(_DeskTool.select);
      _selectedIds
        ..clear()
        ..add(back.id);
      _attachToBlueprint();
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
          final delta = desk - _lastDesk;
          for (final id in _moveIds) {
            final i = _pieces.indexWhere((piece) => piece.id == id);
            if (i < 0) continue;
            final piece = _pieces[i];
            _pieces[i] = piece.copyWith(position: piece.position + delta);
          }
          _attachToBlueprint();
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
          _attachToBlueprint();
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
    if (_in3d) {
      _panView(delta);
      if ((scale - 1).abs() > 1e-4) _camera.zoomByScale(scale);
    } else {
      _deskOrigin += delta;
      if ((scale - 1).abs() > 1e-4) _zoomDesk(scale, focal);
    }
  }

  void _panView(Offset delta) {
    if (!_in3d) {
      _deskOrigin += delta;
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
                : _groupWith(face)?.picks ?? [HologramPick(face)];
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
          final bin = _dragMoved ? _binAt(event.localPosition) : _Bin.none;
          if (bin == _Bin.trash) {
            _takeHeld(<AsmrPiece>[]);
          } else if (bin == _Bin.inventory) {
            _takeHeld(_stowed);
          } else {
            _attachToBlueprint();
            _refreshCoverage();
          }
          _bin = _Bin.none;
        case _Drag.rotate:
          final piece = _selected;
          if (piece != null) _replace(piece);
          _attachToBlueprint();
          _refreshCoverage();
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
        _zoomDesk(factor, event.localPosition);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kAsmrDeskColor,
      body: LayoutBuilder(
        builder: (context, constraints) {
          _onLayout(constraints.biggest);
          final t = _blend;
          final holoOrigin = Offset.lerp(_deskOrigin, _center, t)!;
          final holoScale = ui.lerpDouble(_deskScale, _holoScale, t)!;
          return Stack(
            key: _stackKey,
            children: [
              Positioned.fill(child: _deskLayer()),
              if (t > 0.001)
                Positioned.fill(
                  key: const ValueKey('asmr-veil'),
                  child: _veil(t),
                ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: HologramPainter(
                      edges: _edgeViews,
                      faces: [for (final face in _net.faces) face.ring],
                      origin: holoOrigin,
                      scale: holoScale,
                      contrast: 1 - t,
                    ),
                  ),
                ),
              ),
              Positioned.fill(child: _straightEdgeLayer(1 - t)),
              if (_knifeScreen case final tip?)
                Positioned.fill(
                  key: const ValueKey('asmr-knife'),
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: AsmrKnifePainter(tip: tip, finger: _finger),
                    ),
                  ),
                ),
              if (t > 0.001)
                Positioned.fill(
                  key: const ValueKey('asmr-model'),
                  child: IgnorePointer(
                    child: Opacity(opacity: t, child: _modelLayer()),
                  ),
                ),
              if (_marqueeStart != null && _marqueeEnd != null)
                Positioned.fill(
                  key: const ValueKey('asmr-marquee'),
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _MarqueePainter(
                        start: _marqueeStart!,
                        end: _marqueeEnd!,
                      ),
                    ),
                  ),
                ),
              if (t > 0.5 && !_aimsWithCursor && _modelTool == _ModelTool.orbit)
                Positioned.fill(
                  key: const ValueKey('asmr-crosshair'),
                  child: Opacity(
                    opacity: (t - 0.5) * 2,
                    child: ViewCrosshair(selectable: _hoverFace != null),
                  ),
                ),
              ..._chrome(context, t),
            ],
          );
        },
      ),
    );
  }

  bool get _showKnife => !_in3d && _deskTool == _DeskTool.exacto;

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
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }

  Widget _deskLayer() {
    final selected = _selected;
    final showKnife = _showKnife;
    final showStraight = !_in3d && _deskTool == _DeskTool.straight;
    return DragTarget<AsmrPaper>(
      onAcceptWithDetails: (details) {
        final box = _stackKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(
          details.offset + _kSwatchSize.center(Offset.zero),
        );
        setState(() => _setDeskTool(_DeskTool.select));
        _placeSheet(details.data, _toDesk(local));
      },
      builder: (context, candidate, rejected) => MouseRegion(
        cursor: showKnife
            ? SystemMouseCursors.none
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
          onPointerCancel: _onPointerUp,
          onPointerHover: _onPointerHover,
          onPointerSignal: _onPointerSignal,
          onPointerPanZoomStart: _onPanZoomStart,
          onPointerPanZoomUpdate: _onPanZoomUpdate,
          child: CustomPaint(
            painter: AsmrDeskPainter(
              pieces: List.of(_pieces),
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
              rotateHandle: _deskTool == _DeskTool.select && selected != null
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
    );
  }

  /// Blurs and fades the desk behind the 3D view. Only the hologram, drawn
  /// over this, stays sharp.
  Widget _veil(double t) {
    return IgnorePointer(
      child: ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 10 * t, sigmaY: 10 * t),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  kAsmrSkyColor.withValues(alpha: 0.92 * t),
                  kAsmrDeskColor.withValues(alpha: 0.85 * t),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// What the model draws. A piece that overlaps a blueprint edge keeps
  /// those faces, including after they are deselected.
  List<AsmrPiece> get _modelPieces => [
    for (final piece in _allPieces)
      if (piece.binding != null) piece,
  ];

  /// Each group's color, faded, on its faces. The open group is on top.
  Map<int, Color> get _groupTints {
    final tints = <int, Color>{};
    for (final group in [
      for (final group in _groups)
        if (!identical(group, _group)) group,
      ?_group,
    ]) {
      for (final face in group.faces) {
        tints[face] = group.color.withValues(alpha: 0.3);
      }
    }
    return tints;
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
          pieces: _modelPieces,
          tiles: _tiles,
          add: add,
          highlight: Map.of(_faceFill),
          tint: _groupTints,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }

  int get _filledCount =>
      _coverage.values.where((c) => c >= kAsmrFilled).length;

  List<Widget> _chrome(BuildContext context, double t) {
    final padding = MediaQuery.paddingOf(context);
    final flat = 1 - t;
    return [
      Positioned(
        top: padding.top + 8,
        left: 8,
        child: _RoundButton(
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
        top: padding.top + 8,
        right: 8,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TextLink(
                  label: 'Save',
                  buttonKey: const Key('asmr-save'),
                  onTap: _saveSession,
                ),
                _TextLink(
                  label: 'Load',
                  buttonKey: const Key('asmr-load'),
                  onTap: _loadSession,
                ),
                if (flat > 0.01)
                  Opacity(
                    opacity: flat,
                    child: IgnorePointer(
                      ignoring: flat < 0.5,
                      child: _RoundButton(
                        icon: Icons.restart_alt,
                        tooltip: 'Clear the desk',
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
                child: AsmrDevPanel(settings: _settings),
              ),
          ],
        ),
      ),
      Positioned(
        left: 16,
        bottom: padding.bottom + 16,
        child: _CubeToggle(on: _in3d, onTap: _toggleMode),
      ),
      Positioned(
        left: 88,
        right: 88,
        bottom: padding.bottom + 8,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _HistoryButton(
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
                if (flat > 0.01)
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
                            onSelect: (tool) =>
                                setState(() => _setDeskTool(tool)),
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
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            _HistoryButton(
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
        top: 0,
        bottom: 0,
        right: 12,
        child: _groups.isEmpty || t <= 0.01
            ? const SizedBox.shrink()
            : IgnorePointer(
                ignoring: t < 0.5,
                child: Opacity(
                  opacity: t,
                  child: FractionalTranslation(
                    translation: Offset((1 - t) * 1.2, 0),
                    child: Center(
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (final group in _groups)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 6,
                                ),
                                child: _GroupButton(
                                  group: group,
                                  tiles: _tiles,
                                  open: identical(group, _group),
                                  onTap: () => _openGroup(group),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
      ),
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        child: IgnorePointer(
          ignoring: flat < 0.5,
          child: FractionalTranslation(
            translation: Offset(t * 1.1, 0),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PaperDrawer(
                    key: _drawerKey,
                    tiles: _tiles,
                    onTap: _place,
                    stowed: _stowed,
                    onUnstow: _unstow,
                    accepting: _bin == _Bin.inventory,
                  ),
                  const SizedBox(height: 18),
                  _TrashButton(key: _trashKey, hot: _bin == _Bin.trash),
                ],
              ),
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
              _in3d
                  ? _modelTool == _ModelTool.select
                        ? 'Drag a box around faces. To the right takes what is inside; to the left also takes what it crosses.'
                        : 'Drag to orbit. Switch to Select and drag a box around the faces to unfold.'
                  : _deskTool == _DeskTool.select
                  ? 'Drag a box from empty space to take pieces. Drag them into the drawer, or into the trash under it.'
                  : _deskTool == _DeskTool.straight
                  ? 'Drag to set a line. Each piece it touches is cut right through along it, up to the straight edge.'
                  : 'Lay paper from the drawer and cut along the glowing outline.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.45),
                fontSize: 12,
              ),
            ),
          ),
        ),
      ),
      if (_completeShown > 0)
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, -0.7),
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

  void _place(AsmrPaper paper) => _placeSheet(paper, _toDesk(_center));
}

const Size _kSwatchSize = Size(56, 72);

/// An undo or redo icon with no disc behind it.
class _HistoryButton extends StatelessWidget {
  const _HistoryButton({
    required this.buttonKey,
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.gap,
    required this.onTap,
  });

  final Key buttonKey;
  final IconData icon;
  final String tooltip;
  final bool enabled;
  final EdgeInsets gap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      key: buttonKey,
      padding: gap,
      child: Tooltip(
        message: tooltip,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: SizedBox(
            width: 40,
            height: 40,
            child: Icon(
              icon,
              size: 24,
              color: enabled ? Colors.white : Colors.white24,
            ),
          ),
        ),
      ),
    );
  }
}

class _PaperDrawer extends StatelessWidget {
  const _PaperDrawer({
    super.key,
    required this.tiles,
    required this.onTap,
    required this.stowed,
    required this.onUnstow,
    required this.accepting,
  });

  final AsmrPaperTiles tiles;
  final ValueChanged<AsmrPaper> onTap;
  final List<AsmrPiece> stowed;
  final ValueChanged<AsmrPiece> onUnstow;
  final bool accepting;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('asmr-drawer'),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: accepting ? 0.55 : 0.35),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
        border: Border.all(
          color: Colors.white.withValues(alpha: accepting ? 0.75 : 0.12),
          width: accepting ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final paper in kAsmrPapers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Draggable<AsmrPaper>(
                data: paper,
                feedback: _Swatch(paper: paper, tiles: tiles, lifted: true),
                childWhenDragging: Opacity(
                  opacity: 0.5,
                  child: _Swatch(paper: paper, tiles: tiles),
                ),
                child: Tooltip(
                  message: paper.name,
                  child: GestureDetector(
                    onTap: () => onTap(paper),
                    child: _Swatch(paper: paper, tiles: tiles),
                  ),
                ),
              ),
            ),
          for (final piece in stowed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Tooltip(
                message: 'Lay ${piece.paper.name} back down',
                child: GestureDetector(
                  key: ValueKey('asmr-stowed-${piece.id}'),
                  onTap: () => onUnstow(piece),
                  child: _StowedSwatch(piece: piece, tiles: tiles),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A selection group in the 3D view's list: its blueprint with the paper on
/// it, its letter, and its color. A tap selects its faces.
class _GroupButton extends StatelessWidget {
  const _GroupButton({
    required this.group,
    required this.tiles,
    required this.open,
    required this.onTap,
  });

  final AsmrGroup group;
  final AsmrPaperTiles tiles;
  final bool open;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = group.color;
    return Tooltip(
      message: 'Group ${group.name}',
      child: GestureDetector(
        key: Key('asmr-group-${group.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: open ? 0.5 : 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: open ? 1 : 0.55),
              width: open ? 2.5 : 1.5,
            ),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: CustomPaint(
                    painter: _GroupThumbPainter(group: group, tiles: tiles),
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
                    color: color,
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
        ),
      ),
    );
  }
}

class _GroupThumbPainter extends CustomPainter {
  const _GroupThumbPainter({required this.group, required this.tiles});

  final AsmrGroup group;
  final AsmrPaperTiles tiles;

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
    canvas.drawPath(faces, Paint()..color = group.color.withValues(alpha: 0.3));
    canvas.save();
    canvas.clipPath(faces);
    for (final piece in group.pieces) {
      if (piece.binding == null) continue;
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
        ..color = Colors.white.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GroupThumbPainter old) => true;
}

/// The trash under the paper drawer. A plain icon; it fills in while a
/// selection is dragged onto it.
class _TrashButton extends StatelessWidget {
  const _TrashButton({super.key, required this.hot});

  final bool hot;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Trash',
      child: SizedBox(
        width: 48,
        height: 48,
        child: Icon(
          Icons.delete_outline,
          size: hot ? 32 : 26,
          color: hot ? const Color(0xFFE57373) : Colors.white,
        ),
      ),
    );
  }
}

class _StowedSwatch extends StatelessWidget {
  const _StowedSwatch({required this.piece, required this.tiles});

  final AsmrPiece piece;
  final AsmrPaperTiles tiles;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: _kSwatchSize,
      child: CustomPaint(
        painter: _StowedPainter(piece: piece, tiles: tiles),
      ),
    );
  }
}

class _StowedPainter extends CustomPainter {
  const _StowedPainter({required this.piece, required this.tiles});

  final AsmrPiece piece;
  final AsmrPaperTiles tiles;

  @override
  void paint(Canvas canvas, Size size) {
    final ring = piece.ring;
    if (ring.length < 3) return;
    var minX = ring.first.dx;
    var maxX = minX;
    var minY = ring.first.dy;
    var maxY = minY;
    for (final point in ring) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    final width = math.max(maxX - minX, 1e-6);
    final height = math.max(maxY - minY, 1e-6);
    final scale = math.min(
      (size.width - 8) / width,
      (size.height - 8) / height,
    );
    final path = Path()..addPolygon(ring, true);
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-(minX + maxX) / 2, -(minY + maxY) / 2);
    canvas.drawPath(path, tiles.paint(piece.paper));
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2 / scale
        ..color = Colors.white.withValues(alpha: 0.7),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _StowedPainter old) => old.piece != piece;
}

/// The select tool's box. Dragging right contains, in green; dragging left
/// also crosses, in blue. Same reading as the puzzle editor's marquee.
class _MarqueePainter extends CustomPainter {
  const _MarqueePainter({required this.start, required this.end});

  final Offset start;
  final Offset end;

  @override
  void paint(Canvas canvas, Size size) {
    if ((end - start).distance < 2) return;
    final box = Rect.fromPoints(start, end);
    final cross = marqueePick(start, end) == MarqueePick.cross;
    final color = cross ? const Color(0xFF42A5F5) : const Color(0xFF66BB6A);
    canvas.drawRect(
      box,
      Paint()
        ..color = color.withValues(alpha: 0.12)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRect(
      box,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
  }

  @override
  bool shouldRepaint(covariant _MarqueePainter old) =>
      old.start != start || old.end != end;
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.paper,
    required this.tiles,
    this.lifted = false,
  });

  final AsmrPaper paper;
  final AsmrPaperTiles tiles;
  final bool lifted;

  @override
  Widget build(BuildContext context) {
    return SizedBox.fromSize(
      size: _kSwatchSize,
      child: CustomPaint(
        painter: _SwatchPainter(paper: paper, tiles: tiles, lifted: lifted),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  const _SwatchPainter({
    required this.paper,
    required this.tiles,
    required this.lifted,
  });

  final AsmrPaper paper;
  final AsmrPaperTiles tiles;
  final bool lifted;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(4),
    );
    canvas.drawRRect(
      rect.shift(Offset(0, lifted ? 6 : 2)),
      Paint()
        ..color = Colors.black.withValues(alpha: lifted ? 0.45 : 0.3)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lifted ? 8 : 3),
    );
    canvas.save();
    canvas.clipRRect(rect);
    canvas.scale(1.6);
    canvas.drawRect(Offset.zero & (size / 1.6), tiles.paint(paper));
    canvas.restore();
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.white.withValues(alpha: 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _SwatchPainter old) =>
      old.paper != paper || old.lifted != lifted;
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.35),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(icon, color: Colors.white70, size: 22),
          ),
        ),
      ),
    );
  }
}

class _TextLink extends StatelessWidget {
  const _TextLink({
    required this.label,
    required this.buttonKey,
    required this.onTap,
  });

  final String label;
  final Key buttonKey;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        key: buttonKey,
        onTap: onTap,
        child: Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

/// The square button that turns the 3D view on and off.
class _CubeToggle extends StatelessWidget {
  const _CubeToggle({required this.on, required this.onTap});

  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: on ? 'Craft on the desk' : 'Look at the cube',
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: on
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.black.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: on ? 0.85 : 0.3),
              width: on ? 2 : 1,
            ),
          ),
          child: Icon(
            Icons.view_in_ar,
            color: Colors.white.withValues(alpha: on ? 1 : 0.7),
            size: 28,
          ),
        ),
      ),
    );
  }
}
