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
import '../asmr/asmr_mapping.dart';
import '../asmr/asmr_model_paper.dart';
import '../asmr/asmr_net.dart';
import '../asmr/asmr_paper.dart';
import '../asmr/asmr_piece.dart';
import '../asmr/hologram_painter.dart';
import '../asmr/hologram_selection.dart';
import '../gridcraft/edit.dart' show MarqueePick, marqueePick;
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
  const AsmrView({super.key, this.settings});

  /// Saved DevTools values. Null uses the file in the home directory.
  final AsmrDevSettings? settings;

  @override
  State<AsmrView> createState() => _AsmrViewState();
}

class _HoloEdge {
  _HoloEdge(this.edge);

  AsmrNetEdge edge;
  double opacity = 0;
  double target = 1;
}

enum _Drag { none, orbit, pan, marquee, cut, straight, move, rotate, deskPan }

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

  final List<AsmrPiece> _pieces = [];
  Offset _deskOrigin = Offset.zero;
  double _deskScale = 2.5;
  _DeskTool _deskTool = _DeskTool.exacto;
  _ModelTool _modelTool = _ModelTool.orbit;
  int? _hoverFace;
  Offset? _marqueeStart;
  Offset? _marqueeEnd;
  String? _selectedId;
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

  late final AsmrDevSettings _settings = widget.settings ?? AsmrDevSettings();
  AsmrDevSettings? _ownedSettings;
  bool _devToolsOpen = false;

  /// The blade's samples, before curve smoothing.
  List<Offset>? _rawStroke;
  List<Offset>? _stroke;

  /// The straight cut under way, in desk units. The cut is this segment.
  Offset? _segmentStart;
  Offset? _segmentEnd;
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
    if (raw != null) {
      _stroke = smoothToolCurve(raw, _settings.curveSmoothing);
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
      final center = _model.center;
      final half = _camera
          .frameSphere(center, _model.radius * 2.2, size)
          .halfHeight;
      final pose = CameraPose(
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
      _selectedId == null ? 0 : 1,
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
    if (changed || _complete) setState(() {});
  }

  void _toggleMode() {
    setState(() {
      _in3d = !_in3d;
      _rawStroke = null;
      _stroke = null;
      _segmentStart = null;
      _segmentEnd = null;
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
    for (final piece in _pieces) {
      if (piece.id == _selectedId) return piece;
    }
    return null;
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
      final piece = AsmrPiece.sheet(
        id: '${paper.id}-${_nextSheet++}',
        paper: paper,
        at: desk,
      );
      _pieces.add(piece);
      _selectedId = piece.id;
      _flash[piece.id] = 0.6;
    });
  }

  void _replace(AsmrPiece piece) {
    final i = _pieces.indexWhere((p) => p.id == piece.id);
    if (i >= 0) _pieces[i] = piece;
  }

  /// Binds [piece] to the hologram if it is liberated, unbound, and over it.
  AsmrPiece _bindIfOver(AsmrPiece piece) {
    if (!piece.liberated || piece.binding != null || _net.isEmpty) {
      return piece;
    }
    return overlapsNet(piece, _net) ? piece.copyWith(binding: _net) : piece;
  }

  void _applyCut(AsmrCut cut) {
    _pieces
      ..clear()
      ..addAll([
        for (final piece in cut.pieces)
          cut.freed.contains(piece.id) ? _bindIfOver(piece) : piece,
      ]);
    for (final id in cut.freed) {
      _flash[id] = 1;
    }
    if (_selectedId != null && _selected == null) _selectedId = null;
    if (cut.split) HapticFeedback.mediumImpact();
    _refreshCoverage();
  }

  void _refreshCoverage() {
    _coverage = faceCoverage(_model, _pieces);
    final done =
        _coverage.length == _model.faces.length &&
        _coverage.values.every((c) => c >= kAsmrFilled);
    if (done && !_complete) HapticFeedback.heavyImpact();
    _complete = done;
  }

  void _reset() {
    setState(() {
      _pieces.clear();
      _selectedId = null;
      _flash.clear();
      _refreshCoverage();
    });
  }

  // -------------------------------------------------------------------------
  // Exacto
  // -------------------------------------------------------------------------

  Offset _knifeAt(Offset pointer) =>
      _aimsWithCursor ? pointer : pointer + _kKnifeLift;

  void _beginCut(Offset pointer) {
    final tip = _toDesk(_knifeAt(pointer));
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
    final raw = _toDesk(_knifeAt(pointer));
    final previous = _tipDesk ?? raw;
    final tip = _aimsWithCursor ? raw : Offset.lerp(previous, raw, 0.5)!;
    _tipDesk = tip;
    _finger = pointer;
    final before = rawStroke.length;
    addStrokePoint(rawStroke, tip);
    _stroke = smoothToolCurve(rawStroke, _settings.curveSmoothing);
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
    final stroke = raw == null
        ? null
        : smoothToolCurve(raw, _settings.curveSmoothing);
    _rawStroke = null;
    _stroke = null;
    _finger = null;
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
    _stroke = [desk, desk];
  }

  void _extendStraight(Offset pointer) {
    final start = _segmentStart;
    if (start == null) return;
    final end = _toDesk(pointer);
    _segmentEnd = end;
    _stroke = [start, end];
  }

  void _cancelStraight() {
    _segmentStart = null;
    _segmentEnd = null;
    _stroke = null;
  }

  void _endStraight() {
    final start = _segmentStart;
    final end = _segmentEnd;
    _cancelStraight();
    if (start == null || end == null || !_dragMoved) return;
    final cut = cutPieces(_pieces, [start, end], exact: true);
    if (cut != null) _applyCut(cut);
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

  void _onPointerDown(PointerDownEvent event) {
    _lastKind = event.kind;
    _pointers[event.pointer] = event.localPosition;
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
      final center = _toScreen(selected.deskCentroid);
      _rotateFrom = math.atan2(pointer.dy - center.dy, pointer.dx - center.dx);
      _rotateBase = selected.angle;
      return;
    }
    final hit = _pieceAt(desk);
    if (hit != null) {
      _drag = _Drag.move;
      _selectedId = hit.id;
      _pieces
        ..removeWhere((p) => p.id == hit.id)
        ..add(hit);
      return;
    }
    _drag = _Drag.deskPan;
  }

  void _beginTwoFinger() {
    setState(() {
      if (_drag == _Drag.cut) {
        _rawStroke = null;
        _stroke = null;
        _finger = null;
        _tipDesk = null;
      }
      if (_drag == _Drag.straight) _cancelStraight();
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
        case _Drag.cut:
          _extendCut(event.localPosition);
        case _Drag.straight:
          _extendStraight(event.localPosition);
        case _Drag.move:
          final desk = _toDesk(event.localPosition);
          final piece = _selected;
          if (piece != null) {
            _replace(piece.copyWith(position: piece.position + desk - _lastDesk));
          }
          _lastDesk = desk;
        case _Drag.rotate:
          final piece = _selected;
          if (piece == null) return;
          final center = _toScreen(piece.deskCentroid);
          final now = math.atan2(
            event.localPosition.dy - center.dy,
            event.localPosition.dx - center.dx,
          );
          _replace(piece.turnedTo(_rotateBase + now - _rotateFrom));
        case _Drag.deskPan:
          _deskOrigin += delta;
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
    if (_pointers.isNotEmpty) {
      _lastFocal = _focal();
      _lastSpan = _span();
      return;
    }
    final tap =
        !_dragMoved && event.timeStamp - _dragStartTime < _kTapTime;
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
        case _Drag.move:
        case _Drag.rotate:
          final piece = _selected;
          if (piece != null) _replace(_bindIfOver(piece));
          _refreshCoverage();
        case _Drag.deskPan:
          if (tap && _deskTool == _DeskTool.select) _selectedId = null;
        case _Drag.pan:
        case _Drag.none:
          break;
      }
      _drag = _Drag.none;
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
              if (t > 0.001) Positioned.fill(child: _veil(t)),
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
              if (t > 0.001)
                Positioned.fill(
                  child: IgnorePointer(
                    child: Opacity(opacity: t, child: _modelLayer()),
                  ),
                ),
              if (_marqueeStart != null && _marqueeEnd != null)
                Positioned.fill(
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

  Widget _deskLayer() {
    final selected = _selected;
    final showKnife = !_in3d && _deskTool == _DeskTool.exacto;
    final showStraight = !_in3d && _deskTool == _DeskTool.straight;
    final tipScreen = showKnife && _tipDesk != null
        ? (_finger != null ? _knifeAt(_finger!) : _toScreen(_tipDesk!))
        : null;
    return DragTarget<AsmrPaper>(
      onAcceptWithDetails: (details) {
        final box =
            _stackKey.currentContext?.findRenderObject() as RenderBox?;
        if (box == null) return;
        final local = box.globalToLocal(
          details.offset + _kSwatchSize.center(Offset.zero),
        );
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
              selectedId: _deskTool == _DeskTool.select ? _selectedId : null,
              selectedOutline: _selectedOutline,
              flash: Map.of(_flash),
              stroke: _stroke == null ? null : List.of(_stroke!),
              knifeTip: tipScreen,
              finger: showKnife ? _finger : null,
              rotateHandle: _deskTool == _DeskTool.select && selected != null
                  ? _handleFor(selected)
                  : null,
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
          pieces: List.of(_pieces),
          tiles: _tiles,
          add: add,
          highlight: Map.of(_faceFill),
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
                child: AsmrDevPanel(
                  curveSmoothing: _settings.curveSmoothing,
                  onCurveSmoothing: (value) =>
                      _settings.curveSmoothing = value,
                ),
              ),
          ],
        ),
      ),
      Positioned(
        left: 16,
        bottom: padding.bottom + 16,
        child: _CubeToggle(on: _in3d, onTap: _toggleMode),
      ),
      if (t > 0.01)
        Positioned(
          left: 88,
          right: 88,
          bottom: padding.bottom + 8,
          child: Opacity(
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
        ),
      if (flat > 0.01)
        Positioned(
          left: 88,
          right: 88,
          bottom: padding.bottom + 8,
          child: Opacity(
            opacity: flat,
            child: IgnorePointer(
              ignoring: flat < 0.5,
              child: HudToolCarousel<_DeskTool>(
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
                onSelect: (tool) => setState(() {
                  _deskTool = tool;
                  if (tool != _DeskTool.select) _selectedId = null;
                  if (tool != _DeskTool.exacto) _tipDesk = null;
                  if (tool != _DeskTool.straight || _drag == _Drag.straight) {
                    _cancelStraight();
                  }
                  if (_drag == _Drag.straight) _drag = _Drag.none;
                }),
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
            child: Center(child: _PaperDrawer(tiles: _tiles, onTap: _place)),
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
                  : _deskTool == _DeskTool.straight
                  ? 'Drag a straight line. Every piece it crosses is cut along that line.'
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

class _PaperDrawer extends StatelessWidget {
  const _PaperDrawer({required this.tiles, required this.onTap});

  final AsmrPaperTiles tiles;
  final ValueChanged<AsmrPaper> onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.35),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(18)),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
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
        ],
      ),
    );
  }
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
  const _Swatch({required this.paper, required this.tiles, this.lifted = false});

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
    canvas.drawRect(
      Offset.zero & (size / 1.6),
      tiles.paint(paper),
    );
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
