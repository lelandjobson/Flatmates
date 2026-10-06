import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gestures/gesture_system.dart';
import '../gridcraft/blueprint.dart';
import '../gridcraft/blueprint_board.dart';
import '../gridcraft/blueprint_board_painter.dart';
import '../gridcraft/blueprint_examination_painter.dart';
import '../gridcraft/dimension_measure.dart';
import '../gridcraft/edit.dart';
import '../gridcraft/mixed_craft.dart';
import '../gridcraft/paper_stack.dart';
import '../papercut/camera.dart';
import '../ui/craft_palette.dart';
import '../ui/dimension_chrome.dart';
import '../ui/fm_safe_area.dart';
import '../ui/game/dev_tools_button.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/object_radial_menu.dart';

const double _kBackClearance = 44;
const double _kToolbarClearance = 96;
const double _kZoomMinHalfHeight = 0.25;
const double _kZoomMaxHalfHeight = 800;
const double _kTapSlop = 18;

enum _BoardAct { none, move, scale, rotate }

class _GrabDrag {
  const _GrabDrag(this.axis, this.index);

  final DimensionAxis axis;
  final int index;
}

/// Blueprint step with dimensioning, selection, and piece transforms.
class BlueprintBoardPage extends StatefulWidget {
  const BlueprintBoardPage({
    super.key,
    required this.stepKey,
    required this.blueprint,
    required this.stepIndex,
    required this.choices,
    required this.board,
    required this.showPlacedDimensions,
    required this.onShowPlacedDimensions,
    required this.onStep,
    required this.onSendToCraft,
  });

  final String stepKey;
  final GridBlueprint blueprint;
  final int stepIndex;
  final List<BoardStepChoice> choices;
  final StepBoard board;
  final bool showPlacedDimensions;
  final ValueChanged<bool> onShowPlacedDimensions;
  final ValueChanged<String?> onStep;
  final VoidCallback onSendToCraft;

  @override
  State<BlueprintBoardPage> createState() => _BlueprintBoardPageState();
}

class _BlueprintBoardPageState extends State<BlueprintBoardPage> {
  final PapercutCamera _camera = PapercutCamera();
  final Map<int, Offset> _pointers = {};

  BoardTool _tool = BoardTool.dimension;
  _SelectMode _selectMode = _SelectMode.point;
  _BoardAct _act = _BoardAct.none;

  Size _viewport = Size.zero;
  DimensionChrome? _chrome;
  bool _framed = false;
  bool _devOpen = false;
  bool _multi = false;
  bool _moved = false;
  Offset? _down;
  double? _span;
  Offset? _pinchCentroid;
  double _trackpadScale = 1;
  _GrabDrag? _drag;

  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  List<BoardPiece>? _moveOrigin;
  Offset _moveFree = Offset.zero;

  TransformHandle? _handle;
  List<BoardPiece>? _scaleOrigin;
  Rect? _scaleBounds;
  List<BoardPiece>? _twistOrigin;
  double? _twistAngle;

  Offset? _pivot;
  List<BoardPiece>? _turnOrigin;
  double? _turnStart;

  List<String> _pickStack = const [];
  int _pickClicks = 0;
  DateTime? _pickTapAt;

  GridStep? get _step {
    final steps = widget.blueprint.steps;
    if (steps.isEmpty) return null;
    return steps[widget.stepIndex.clamp(0, steps.length - 1)];
  }

  Set<String> get _ids => widget.board.selected;

  @override
  void initState() {
    super.initState();
    _camera.addListener(_onCamera);
  }

  @override
  void didUpdateWidget(BlueprintBoardPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _tool = boardToolWithPieces(_tool, widget.board.pieces.length);
    if (oldWidget.stepKey != widget.stepKey) {
      _framed = false;
      _clearAct();
    }
  }

  @override
  void dispose() {
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    if (!mounted) return;
    if (_drag == null && _tool == BoardTool.dimension) _follow();
    setState(() {});
  }

  void _clearAct() {
    _act = _BoardAct.none;
    _moveOrigin = null;
    _moveFree = Offset.zero;
    _handle = null;
    _scaleOrigin = null;
    _scaleBounds = null;
    _twistOrigin = null;
    _twistAngle = null;
    _pivot = null;
    _turnOrigin = null;
    _turnStart = null;
    _marqueeStart = null;
    _marqueeCurrent = null;
  }

  void _setTool(BoardTool tool) {
    setState(() {
      _tool = boardToolWithPieces(tool, widget.board.pieces.length);
      _clearAct();
      if (_tool == BoardTool.dimension) _follow();
    });
  }

  void _setPieces(List<BoardPiece> pieces) {
    widget.board.pieces
      ..clear()
      ..addAll(pieces);
  }

  double _chromeSize(Size size) {
    final short = math.min(size.width, size.height);
    return (short * 0.11).clamp(44.0, 72.0);
  }

  double _snapRadius() {
    final shorter = math.min(_viewport.width, _viewport.height);
    return snapWorldRadius(
      pixels: kBoardSnapPixels,
      halfHeight: _camera.framedHalfHeightMm,
      shorterSide: shorter,
    );
  }

  double _handleRadius() {
    final shorter = math.min(_viewport.width, _viewport.height);
    return snapWorldRadius(
      pixels: 16,
      halfHeight: _camera.framedHalfHeightMm,
      shorterSide: shorter,
    );
  }

  void _zoom(double scale) {
    if (scale <= 0 || (scale - 1).abs() < 1e-6) return;
    final next = (_camera.framedHalfHeightMm / scale).clamp(
      _kZoomMinHalfHeight,
      _kZoomMaxHalfHeight,
    );
    if ((next - _camera.framedHalfHeightMm).abs() < 1e-4) return;
    _camera.moveLook(lookAt: _camera.lookAt, halfHeight: next);
  }

  void _pan(Offset delta) {
    _camera.panByScreen(delta, _viewport);
  }

  Offset? _world(Offset screen) => _camera.planePoint(screen, _viewport);

  Offset? _aim() {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.planePoint(
      Offset(_viewport.width / 2, _viewport.height / 2),
      _viewport,
    );
  }

  Offset? _project(Offset world) {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.camera.projectToScreen(
      Vector3(world.dx, world.dy, 0),
      _viewport,
    );
  }

  void _frame() {
    final step = _step;
    final chrome = _chrome;
    if (step == null || chrome == null || _viewport.height < 2) return;
    _camera.setRoll(0);
    final bounds = vertexBounds(step.vertices);
    if (bounds == null) return;
    final half =
        dimensionFrameHalfHeight(
          spanX: bounds.width,
          spanY: bounds.height,
          barX: chrome.horizontal.length,
          barY: chrome.vertical.length,
          viewportHeight: _viewport.height,
        ) ??
        dimensionFrameHalfHeight(
          spanX: step.gridSpacing,
          spanY: 0,
          barX: chrome.horizontal.length,
          barY: chrome.vertical.length,
          viewportHeight: _viewport.height,
        );
    if (half == null) return;
    _camera.moveLook(
      lookAt: bounds.center,
      halfHeight: half.clamp(_kZoomMinHalfHeight, _kZoomMaxHalfHeight),
    );
    if (widget.board.rulersPlaced) {
      if (_tool == BoardTool.dimension) _follow();
      return;
    }
    widget.board.horizontal.stickTo(
      low: bounds.left,
      high: bounds.right,
      track: chrome.horizontal,
      screenAlongOf: (world) => _screenAlong(DimensionAxis.horizontal, world),
    );
    widget.board.vertical.stickTo(
      low: bounds.top,
      high: bounds.bottom,
      track: chrome.vertical,
      screenAlongOf: (world) => _screenAlong(DimensionAxis.vertical, world),
    );
    widget.board.rulersPlaced = true;
  }

  List<ProjectedVertex> _vertices() {
    final step = _step;
    if (step == null) return const [];
    final out = <ProjectedVertex>[];
    for (final world in step.vertices) {
      final screen = _project(world);
      if (screen == null) continue;
      out.add(ProjectedVertex(world: world, screen: screen));
    }
    return out;
  }

  double? _screenAlong(DimensionAxis axis, double world) {
    final cross = axis == DimensionAxis.horizontal
        ? _camera.lookAt.dy
        : _camera.lookAt.dx;
    final point = axis == DimensionAxis.horizontal
        ? Offset(world, cross)
        : Offset(cross, world);
    final screen = _project(point);
    if (screen == null) return null;
    return axis == DimensionAxis.horizontal ? screen.dx : screen.dy;
  }

  void _follow() {
    final chrome = _chrome;
    if (chrome == null || _viewport.width < 2) return;
    final vertices = _vertices();
    final view = Offset.zero & _viewport;
    widget.board.horizontal.followCamera(
      vertices: vertices,
      viewport: view,
      track: chrome.horizontal,
      screenAlongOf: (world) => _screenAlong(DimensionAxis.horizontal, world),
    );
    widget.board.vertical.followCamera(
      vertices: vertices,
      viewport: view,
      track: chrome.vertical,
      screenAlongOf: (world) => _screenAlong(DimensionAxis.vertical, world),
    );
  }

  List<SnapGuide> _guides() {
    final out = <SnapGuide>[];
    void add(DimensionRuler ruler) {
      for (final grab in ruler.grabs) {
        final world = grab.world;
        if (world == null) continue;
        final duplicate = out.any(
          (guide) =>
              guide.axis == ruler.axis &&
              (guide.world - world).abs() <= kDimensionColinearEpsilon,
        );
        if (duplicate) continue;
        out.add(SnapGuide(axis: ruler.axis, world: world));
      }
    }

    add(widget.board.horizontal);
    add(widget.board.vertical);
    return out;
  }

  String _label(DimensionRuler ruler) {
    return dimensionReadout(ruler, _step?.gridSpacing ?? 1);
  }

  void _onSignal(PointerSignalEvent event) {
    if (event is PointerScaleEvent) {
      _zoom(event.scale);
      return;
    }
    if (event is PointerScrollEvent && event.scrollDelta.dy != 0) {
      _zoom(math.exp(-event.scrollDelta.dy * 0.002));
    }
  }

  void _onTrackpadStart(PointerPanZoomStartEvent event) {
    _trackpadScale = 1;
  }

  void _onTrackpadUpdate(PointerPanZoomUpdateEvent event) {
    if (_act == _BoardAct.scale && _ids.isNotEmpty) {
      _beginTwist();
      _twist(event.rotation);
      setState(() {});
      return;
    }
    final scale = event.scale;
    if (scale > 0 && (scale / _trackpadScale - 1).abs() > 1e-6) {
      _zoom(scale / _trackpadScale);
      _trackpadScale = scale;
    }
    if (event.localPanDelta != Offset.zero) _pan(event.localPanDelta);
  }

  void _onTrackpadEnd(PointerPanZoomEndEvent event) {
    _trackpadScale = 1;
    _endTwist();
    if (_tool == BoardTool.dimension) _follow();
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _multi = true;
      _moved = true;
      _drag = null;
      _span = null;
      _pinchCentroid = null;
      _marqueeStart = null;
      _marqueeCurrent = null;
      _handle = null;
      if (_act == _BoardAct.scale) _beginTwist();
      setState(() {});
      return;
    }
    _moved = false;
    _down = event.localPosition;
    if (_tool == BoardTool.dimension) {
      _dimensionDown(event.localPosition);
      return;
    }
    _selectDown(event.localPosition);
  }

  void _dimensionDown(Offset screen) {
    final chrome = _chrome;
    if (chrome != null && dimensionWidgetsShown(_tool)) {
      final horizontal = hitGrab(
        chrome.horizontal,
        widget.board.horizontal,
        screen,
      );
      if (horizontal != null) {
        _drag = _GrabDrag(DimensionAxis.horizontal, horizontal);
        setState(() {});
        return;
      }
      final vertical = hitGrab(chrome.vertical, widget.board.vertical, screen);
      if (vertical != null) {
        _drag = _GrabDrag(DimensionAxis.vertical, vertical);
        setState(() {});
        return;
      }
    }
    setState(() {});
  }

  void _selectDown(Offset screen) {
    if (_selectMode == _SelectMode.marquee && _act == _BoardAct.none) {
      _marqueeStart = screen;
      _marqueeCurrent = screen;
    } else if (_act == _BoardAct.move) {
      _moveOrigin = [for (final piece in widget.board.pieces) piece.clone()];
      _moveFree = Offset.zero;
    } else if (_act == _BoardAct.scale) {
      final world = _world(screen);
      final bounds = selectionBounds(widget.board.pieces, _ids);
      if (world != null && bounds != null) {
        final handle = hitTransformHandle(world, bounds, _handleRadius());
        if (handle != null) {
          _handle = handle;
          _scaleOrigin = [
            for (final piece in widget.board.pieces) piece.clone(),
          ];
          _scaleBounds = bounds;
        }
      }
    } else if (_act == _BoardAct.rotate && _pivot != null) {
      final world = _world(screen);
      _turnOrigin = [for (final piece in widget.board.pieces) piece.clone()];
      if (world != null) {
        final arm = world - _pivot!;
        _turnStart = math.atan2(arm.dy, arm.dx);
      }
    }
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent event) {
    final previous = _pointers[event.pointer] ?? event.localPosition;
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _twoFinger();
      setState(() {});
      return;
    }
    if (_multi) return;
    final down = _down;
    if (down != null && (event.localPosition - down).distance > _kTapSlop) {
      _moved = true;
    }
    if (_tool == BoardTool.dimension) {
      final drag = _drag;
      if (drag != null) {
        _moveGrab(drag, event.localPosition);
        setState(() {});
        return;
      }
      if (!_moved || down == null) return;
      _pan(event.localPosition - previous);
      setState(() {});
      return;
    }
    if (_selectMode == _SelectMode.marquee &&
        _act == _BoardAct.none &&
        _marqueeStart != null) {
      _marqueeCurrent = event.localPosition;
      setState(() {});
      return;
    }
    if (_act == _BoardAct.move && _moveOrigin != null && _moved) {
      _followMove(event.localPosition - previous);
      setState(() {});
      return;
    }
    if (_act == _BoardAct.scale && _handle != null && _moved) {
      _dragHandle(event.localPosition);
      setState(() {});
      return;
    }
    if (_act == _BoardAct.rotate &&
        _pivot != null &&
        _turnOrigin != null &&
        _moved) {
      _dragTurn(event.localPosition);
      setState(() {});
      return;
    }
    if (!_moved) return;
    _pan(event.localPosition - previous);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) {
      if (_pointers.length < 2) _endTwist();
      _span = null;
      _pinchCentroid = null;
      setState(() {});
      return;
    }
    final multi = _multi;
    final moved = _moved;
    final down = _down;
    final drag = _drag;
    _multi = false;
    _moved = false;
    _span = null;
    _pinchCentroid = null;
    _down = null;
    _drag = null;
    _endTwist();
    if (multi) {
      if (_tool == BoardTool.dimension) _follow();
      setState(() {});
      return;
    }
    if (_tool == BoardTool.dimension) {
      if (drag != null) {
        if (!moved && down != null) _lockArmedTap(drag, down);
        _follow();
      } else if (!moved && down != null) {
        _dimensionTap(down);
      }
      setState(() {});
      return;
    }
    if (_selectMode == _SelectMode.marquee && _act == _BoardAct.none) {
      _finishMarquee();
    } else if (_act == _BoardAct.move && moved) {
      _act = _BoardAct.none;
      _moveOrigin = null;
      _moveFree = Offset.zero;
    } else if (_act == _BoardAct.scale && _handle != null) {
      _handle = null;
      _scaleOrigin = null;
      _scaleBounds = null;
    } else if (_act == _BoardAct.rotate && _pivot != null && moved) {
      _act = _BoardAct.none;
      _pivot = null;
      _turnOrigin = null;
      _turnStart = null;
    } else if (_act == _BoardAct.rotate && _pivot == null && !moved) {
      _lockPivot();
    } else if (_act == _BoardAct.scale && !moved && _handle == null) {
      _act = _BoardAct.none;
    } else if (!moved &&
        _act == _BoardAct.none &&
        _selectMode == _SelectMode.point) {
      final aim = _aim();
      if (aim != null) _selectTap(aim);
    }
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) return;
    _drag = null;
    _multi = false;
    _moved = false;
    _span = null;
    _pinchCentroid = null;
    _down = null;
    _endTwist();
    if (_tool == BoardTool.dimension) _follow();
    setState(() {});
  }

  void _twoFinger() {
    if (_pointers.length < 2) return;
    final points = _pointers.values.toList();
    if (_act == _BoardAct.scale && _twistOrigin != null) {
      _twist(pointerPairAngle(points[0], points[1]));
      return;
    }
    final centroid = (points[0] + points[1]) / 2;
    final span = (points[0] - points[1]).distance;
    final previousCentroid = _pinchCentroid;
    final previousSpan = _span;
    _pinchCentroid = centroid;
    _span = span;
    if (previousCentroid != null) _pan(centroid - previousCentroid);
    if (previousSpan != null && previousSpan > 12 && span > 12) {
      _zoom(span / previousSpan);
    }
  }

  void _beginTwist() {
    if (_act != _BoardAct.scale || _ids.isEmpty || _twistOrigin != null) return;
    _twistOrigin = [for (final piece in widget.board.pieces) piece.clone()];
    if (_pointers.length < 2) return;
    final points = _pointers.values.toList();
    _twistAngle = pointerPairAngle(points[0], points[1]);
  }

  void _twist(double angle) {
    final origin = _twistOrigin;
    final start = _twistAngle;
    if (origin == null) return;
    if (start == null) {
      _twistAngle = angle;
      return;
    }
    final pivot = selectionCentroid(origin, _ids);
    if (pivot == null) return;
    _setPieces(rotatePieces(origin, _ids, pivot, wrapRadians(angle - start)));
  }

  void _endTwist() {
    _twistOrigin = null;
    _twistAngle = null;
  }

  void _moveGrab(_GrabDrag drag, Offset screen) {
    final chrome = _chrome;
    if (chrome == null) return;
    final horizontal = drag.axis == DimensionAxis.horizontal;
    final ruler = horizontal ? widget.board.horizontal : widget.board.vertical;
    final track = horizontal ? chrome.horizontal : chrome.vertical;
    ruler.moveGrab(
      index: drag.index,
      screenAlong: horizontal ? screen.dx : screen.dy,
      track: track,
      vertices: _vertices(),
    );
  }

  void _dimensionTap(Offset screen) {
    final chrome = _chrome;
    if (chrome == null) return;
    if (_ownsTrack(chrome.horizontal, screen)) {
      _lockTrack(chrome.horizontal, widget.board.horizontal, screen);
      return;
    }
    if (_ownsTrack(chrome.vertical, screen)) {
      _lockTrack(chrome.vertical, widget.board.vertical, screen);
      return;
    }
    final index = _hitLocked(screen);
    if (index != null) widget.board.locked.removeAt(index);
  }

  void _lockArmedTap(_GrabDrag drag, Offset screen) {
    final chrome = _chrome;
    if (chrome == null) return;
    final horizontal = drag.axis == DimensionAxis.horizontal;
    _lockTrack(
      horizontal ? chrome.horizontal : chrome.vertical,
      horizontal ? widget.board.horizontal : widget.board.vertical,
      screen,
    );
  }

  bool _ownsTrack(DimensionTrack track, Offset screen) {
    final dist = spanDistance(track.start, track.end, screen);
    return dist != null && dist <= kDimensionSpanSlop;
  }

  void _lockTrack(DimensionTrack track, DimensionRuler ruler, Offset screen) {
    final a = track.at(ruler.grabs[0].fraction);
    final b = track.at(ruler.grabs[1].fraction);
    if (!tapHitsMeasuredSpan(a, b, screen)) return;
    final cross = _crossWorld(track);
    if (cross == null) return;
    final placed = lockDimension(ruler, cross);
    if (placed != null) widget.board.locked.add(placed);
  }

  double? _crossWorld(DimensionTrack track) {
    if (_viewport.width < 2) return null;
    final world = _camera.planePoint(track.at(0.5), _viewport);
    if (world == null) return null;
    return track.axis == DimensionAxis.horizontal ? world.dy : world.dx;
  }

  int? _hitLocked(Offset tap) {
    final spans = <({Offset a, Offset b})>[];
    final indexes = <int>[];
    for (var i = 0; i < widget.board.locked.length; i++) {
      final ends = dimensionEndpoints(widget.board.locked[i]);
      final a = _project(ends.$1);
      final b = _project(ends.$2);
      if (a == null || b == null) continue;
      spans.add((a: a, b: b));
      indexes.add(i);
    }
    final hit = nearestSpan(spans, tap);
    if (hit == null) return null;
    return indexes[hit];
  }

  void _followMove(Offset screenDelta) {
    final origin = _moveOrigin;
    final step = _step;
    if (origin == null || step == null || screenDelta == Offset.zero) return;
    final before = _aim();
    _pan(screenDelta);
    final after = _aim();
    if (before != null && after != null) _moveFree += after - before;
    final shifted = shiftSelected(origin, _ids, _moveFree);
    final delta = blueprintMoveSnap(
      moving: [
        for (final piece in shifted)
          if (_ids.contains(piece.id)) ...piecePoints(piece),
      ],
      blueprintVertices: step.vertices,
      otherPaper: [
        for (final piece in shifted)
          if (!_ids.contains(piece.id)) ...piecePoints(piece),
      ],
      spacing: step.gridSpacing,
      radius: _snapRadius(),
    );
    _setPieces(
      delta == Offset.zero ? shifted : shiftSelected(shifted, _ids, delta),
    );
  }

  void _dragHandle(Offset screen) {
    final origin = _scaleOrigin;
    final bounds = _scaleBounds;
    final handle = _handle;
    final step = _step;
    final world = _world(screen);
    if (origin == null ||
        bounds == null ||
        handle == null ||
        step == null ||
        world == null) {
      return;
    }
    _setPieces(
      stretchPieces(
        origin,
        _ids,
        stretchToPointer(
          handle: handle,
          bounds: bounds,
          pointer: world,
          blueprintVertices: step.vertices,
          spacing: step.gridSpacing,
          radius: _snapRadius(),
        ),
      ),
    );
  }

  void _dragTurn(Offset screen) {
    final origin = _turnOrigin;
    final pivot = _pivot;
    final start = _turnStart;
    final world = _world(screen);
    if (origin == null || pivot == null || start == null || world == null) {
      return;
    }
    final arm = world - pivot;
    if (arm.distance < 1e-6) return;
    final free = wrapRadians(math.atan2(arm.dy, arm.dx) - start);
    final snapped = snapTurn(
      moving: [
        for (final piece in origin)
          if (_ids.contains(piece.id)) ...piece.vertices,
      ],
      pivot: pivot,
      radians: free,
      targets: [
        if (_step != null) ..._step!.vertices,
        for (final piece in origin)
          if (!_ids.contains(piece.id)) ...piecePoints(piece),
      ],
      radius: _snapRadius(),
    );
    _setPieces(rotatePieces(origin, _ids, pivot, snapped));
  }

  void _lockPivot() {
    final aim = _aim();
    if (aim == null) return;
    final step = _step;
    _pivot = nearestSnapVertex(aim, [
      if (step != null) ...step.vertices,
      for (final piece in widget.board.pieces) ...piecePoints(piece),
    ], _snapRadius());
  }

  void _selectTap(Offset aim) {
    final under = boardPiecesUnder(widget.board.pieces, aim);
    if (under.isEmpty) {
      widget.board.selected.clear();
      _pickStack = const [];
      _pickClicks = 0;
      return;
    }
    final now = DateTime.now();
    final repeat =
        _pickTapAt != null &&
        now.difference(_pickTapAt!) <= stackTapInterval &&
        _sameIds(_pickStack, under);
    _pickClicks = repeat ? _pickClicks + 1 : 1;
    _pickStack = under;
    _pickTapAt = now;
    final key = under[stackPickIndex(_pickClicks, under.length)];
    widget.board.selected
      ..clear()
      ..add(key);
  }

  void _finishMarquee() {
    final start = _marqueeStart;
    final end = _marqueeCurrent;
    _marqueeStart = null;
    _marqueeCurrent = null;
    if (start == null || end == null) return;
    if ((end - start).distance < 8) return;
    final world = _worldRect(start, end);
    if (world == null) return;
    widget.board.selected
      ..clear()
      ..addAll(
        boardMarqueeHits(widget.board.pieces, world, marqueePick(start, end)),
      );
  }

  Rect? _worldRect(Offset a, Offset b) {
    final corners = <Offset>[];
    for (final screen in [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)]) {
      final world = _world(screen);
      if (world == null) return null;
      corners.add(world);
    }
    return vertexBounds(corners);
  }

  Rect? _marqueeRect() {
    final start = _marqueeStart;
    final end = _marqueeCurrent;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
  }

  @override
  Widget build(BuildContext context) {
    _tool = boardToolWithPieces(_tool, widget.board.pieces.length);
    return LayoutBuilder(
      builder: (context, constraints) {
        _viewport = Size(constraints.maxWidth, constraints.maxHeight);
        final safe = fmSafeInsets(context, minimum: kFmScreenInset);
        final chrome = DimensionChrome.layout(
          viewport: _viewport,
          safe: safe.copyWith(
            top: safe.top + _kBackClearance,
            bottom: safe.bottom + _kToolbarClearance,
          ),
        );
        _chrome = chrome;
        if (!_framed && _viewport.width > 2 && _step != null) {
          _framed = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            _frame();
            setState(() {});
          });
        }
        final step = _step;
        final widgets = dimensionWidgetsShown(_tool);
        final placed = placedDimensionsShown(
          _tool,
          showInSelect: widget.showPlacedDimensions,
        );
        final box = _act == _BoardAct.scale
            ? selectionBounds(widget.board.pieces, _ids)
            : null;
        final menuCenter = _menuCenter();
        final chromeSize = _chromeSize(_viewport);
        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerSignal: _onSignal,
                onPointerPanZoomStart: _onTrackpadStart,
                onPointerPanZoomUpdate: _onTrackpadUpdate,
                onPointerPanZoomEnd: _onTrackpadEnd,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: AnimatedBuilder(
                  animation: _camera,
                  builder: (context, _) {
                    return CustomPaint(
                      key: const Key('dimension-board-canvas'),
                      foregroundPainter: BlueprintBoardPainter(
                        camera: _camera,
                        pieces: widget.board.pieces,
                        selected: _ids,
                        marquee: _marqueeRect(),
                        transform: box,
                        pivot: _act == _BoardAct.rotate ? _pivot : null,
                        snap: _act == _BoardAct.rotate && _pivot == null
                            ? _liveSnap()
                            : null,
                      ),
                      painter: step == null
                          ? null
                          : BlueprintExaminationPainter(
                              camera: _camera,
                              step: step,
                              locked: placed ? widget.board.locked : const [],
                              guides: widgets ? _guides() : const [],
                            ),
                      child: const SizedBox.expand(),
                    );
                  },
                ),
              ),
            ),
            if (widgets)
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: DimensionChromePainter(
                      chrome: chrome,
                      horizontal: widget.board.horizontal,
                      vertical: widget.board.vertical,
                      horizontalLabel: _label(widget.board.horizontal),
                      verticalLabel: _label(widget.board.vertical),
                    ),
                  ),
                ),
              ),
            if (_tool == BoardTool.select && _act != _BoardAct.scale)
              const IgnorePointer(child: ViewCrosshair()),
            if (menuCenter != null &&
                _tool == BoardTool.select &&
                _act == _BoardAct.none &&
                _ids.isNotEmpty &&
                _marqueeStart == null)
              Positioned.fill(
                child: ObjectRadialMenu(
                  center: menuCenter,
                  actions: [
                    RadialAction(
                      icon: Icons.open_with,
                      label: 'Move',
                      tint: const Color(0xFF90A4AE),
                      onTap: () => setState(() => _act = _BoardAct.move),
                    ),
                    RadialAction(
                      icon: Icons.aspect_ratio,
                      label: 'Scale',
                      tint: const Color(0xFF80CBC4),
                      onTap: () => setState(() => _act = _BoardAct.scale),
                    ),
                    RadialAction(
                      icon: Icons.rotate_right,
                      label: 'Rotate',
                      tint: const Color(0xFFFFD54F),
                      onTap: () => setState(() {
                        _pivot = null;
                        _act = _BoardAct.rotate;
                      }),
                    ),
                    RadialAction(
                      icon: Icons.arrow_forward,
                      label: 'Craft',
                      tint: const Color(0xFF90CAF9),
                      side: RadialActionSide.right,
                      onTap: () {
                        _clearAct();
                        widget.onSendToCraft();
                      },
                    ),
                  ],
                ),
              ),
            _stepMenu(safe.top),
            Positioned(
              left: 16,
              top: safe.top + 52,
              child: DevToolsButton(
                active: _devOpen,
                onPressed: () => setState(() => _devOpen = !_devOpen),
              ),
            ),
            if (_devOpen)
              Positioned(left: 16, top: safe.top + 78, child: _devPanel()),
            Positioned(
              left: 0,
              right: 0,
              bottom: safe.bottom + 8,
              child: _toolbar(chromeSize),
            ),
          ],
        );
      },
    );
  }

  Offset? _menuCenter() {
    final center = selectionCentroid(widget.board.pieces, _ids);
    if (center == null) return null;
    return _project(center);
  }

  Offset? _liveSnap() {
    final aim = _aim();
    if (aim == null) return null;
    final step = _step;
    return nearestSnapVertex(aim, [
      if (step != null) ...step.vertices,
      for (final piece in widget.board.pieces) ...piecePoints(piece),
    ], _snapRadius());
  }

  Widget _devPanel() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xE61A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 2, 12, 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Checkbox(
              key: const Key('board-show-dimensions'),
              value: widget.showPlacedDimensions,
              onChanged: (value) =>
                  widget.onShowPlacedDimensions(value ?? false),
            ),
            const Text(
              'Show placed dimensions',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stepMenu(double top) {
    if (widget.choices.isEmpty) return const SizedBox.shrink();
    final value = widget.choices.any((choice) => choice.key == widget.stepKey)
        ? widget.stepKey
        : widget.choices.first.key;
    return Positioned(
      top: top,
      right: 12,
      child: SizedBox(
        width: 220,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const Key('blueprint-board-steps'),
                isExpanded: true,
                isDense: true,
                dropdownColor: const Color(0xFF1A1A1A),
                value: value,
                items: [
                  for (final choice in widget.choices)
                    DropdownMenuItem(
                      value: choice.key,
                      child: Text(
                        choice.label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
                onChanged: widget.onStep,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _toolbar(double chrome) {
    final pieces = widget.board.pieces.length;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: chrome + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tool == BoardTool.select) _selectModes(chrome),
          HudToolCarousel<BoardTool>(
            items: [
              HudCarouselItem(
                value: BoardTool.dimension,
                icon: Icons.straighten,
                label: 'Dimension',
                fill: CraftPalette.cyan.fill,
              ),
              if (selectToolShown(pieces))
                HudCarouselItem(
                  value: BoardTool.select,
                  icon: Icons.near_me,
                  label: 'Select',
                  fill: CraftPalette.kentuckyBlue.fill,
                ),
            ],
            selected: _tool,
            onSelect: _setTool,
          ),
        ],
      ),
    );
  }

  Widget _selectModes(double chrome) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          HudToolButton(
            icon: Icons.adjust,
            label: 'Point',
            fill: CraftPalette.cerulean.fill,
            selected: _selectMode == _SelectMode.point,
            buttonSize: chrome * 0.8,
            onTap: () => setState(() {
              _selectMode = _SelectMode.point;
              _marqueeStart = null;
              _marqueeCurrent = null;
            }),
          ),
          HudToolButton(
            icon: Icons.crop_free,
            label: 'Marquee',
            fill: CraftPalette.seaGreen.fill,
            selected: _selectMode == _SelectMode.marquee,
            buttonSize: chrome * 0.8,
            onTap: () => setState(() {
              _selectMode = _SelectMode.marquee;
              if (_act == _BoardAct.move) _act = _BoardAct.none;
            }),
          ),
        ],
      ),
    );
  }
}

enum _SelectMode { point, marquee }

bool _sameIds(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
