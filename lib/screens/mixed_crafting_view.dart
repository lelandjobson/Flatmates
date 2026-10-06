import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gridcraft/edit.dart';
import '../gridcraft/fold_glyph.dart';
import '../gridcraft/mixed_craft.dart';
import '../gridcraft/mixed_craft_painter.dart';
import '../gridcraft/paper_stack.dart';
import '../gridcraft/scissor.dart';
import '../gridcraft/scissor_glyph.dart';
import '../gridcraft/tool_animation.dart';
import '../gridcraft/tool_flight.dart';
import '../papercut/camera.dart';
import '../papercut/models.dart';
import '../ui/craft_palette.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/object_radial_menu.dart';

enum _CraftTool { select, scissors, folder }

enum _SelectMode { point, marquee }

/// Papercraft surface. The sheet is 24×24 real units and reads as 6×6 at the
/// opening grid scale. There is no blueprint.
class MixedCraftingView extends StatefulWidget {
  const MixedCraftingView({super.key});

  @override
  State<MixedCraftingView> createState() => _MixedCraftingViewState();
}

class _MixedCraftingViewState extends State<MixedCraftingView>
    with TickerProviderStateMixin {
  static const _tapSlop = 24.0;

  final PapercutCamera _camera = PapercutCamera();
  final MixedCraftHistory _history = MixedCraftHistory();
  final ScissorToolAnimation _scissors = ScissorToolAnimation();
  final ToolFlight _flight = ToolFlight();
  final ToolFlight _foldFlight = ToolFlight();
  final GridScaleCrossfade _grids = GridScaleCrossfade();
  final Map<int, Offset> _pointers = {};
  late final AnimationController _flightAnim;
  late final AnimationController _foldFlightAnim;
  late final AnimationController _gridFade;

  MixedCraftArea _area = mixedOpeningArea();
  int _scale = kMixedDefaultScale;
  _CraftTool _tool = _CraftTool.select;
  _SelectMode _selectMode = _SelectMode.point;

  Size _viewport = Size.zero;
  bool _framed = false;
  bool _dragged = false;
  bool _multiTouch = false;
  Offset? _downScreen;
  double? _span;
  Offset? _pinchCentroid;

  CutLock? _cut;
  bool _cutGlowing = false;

  String? _foldSheetId;
  Offset? _foldStart;
  Offset? _foldEnd;
  bool _foldGlowing = false;
  DateTime? _foldTapAt;
  Timer? _foldTimer;

  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  bool _moving = false;
  MixedCraftArea? _moveOrigin;
  Offset? _moveAnchor;
  Offset? _moveCenter;

  List<String> _pickStack = const [];
  int _pickClicks = 0;
  DateTime? _pickTapAt;
  bool _scissorSyncQueued = false;
  bool _foldSyncQueued = false;

  @override
  void initState() {
    super.initState();
    _flightAnim = AnimationController(vsync: this, duration: kArriveDuration)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener(_onFlightStatus);
    _foldFlightAnim =
        AnimationController(vsync: this, duration: kArriveDuration)
          ..addListener(() {
            if (mounted) setState(() {});
          })
          ..addStatusListener(_onFoldFlightStatus);
    _gridFade = AnimationController(vsync: this, duration: kGridScaleFade)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) _grids.settle();
      });
  }

  @override
  void dispose() {
    _foldTimer?.cancel();
    _gridFade.dispose();
    _foldFlightAnim.dispose();
    _flightAnim.dispose();
    _camera.dispose();
    super.dispose();
  }

  void _stepScale({required bool finer}) {
    final next = stepGridScale(_scale, finer: finer);
    if (!_grids.retarget(next, t: _gridFade.value)) return;
    setState(() => _scale = next);
    _gridFade.forward(from: 0);
  }

  void _apply(MixedCraftArea? next) {
    if (next == null) return;
    _history.push(_area);
    _area = next;
  }

  void _frame() {
    if (_viewport.width < 2 || _viewport.height < 2) return;
    final fit = _camera.halfHeightForSheet(_viewport, sheetMm: kMixedPaperSize);
    _camera.moveLook(lookAt: Offset.zero, halfHeight: fit * 1.35);
  }

  void _zoom(double scale) {
    if (scale <= 0 || (scale - 1).abs() < 1e-6) return;
    final next = (_camera.framedHalfHeightMm / scale).clamp(1.5, 800.0);
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

  Rect _visible() {
    final halfH = _camera.framedHalfHeightMm;
    final aspect = _viewport.height < 2
        ? 1.0
        : _viewport.width / _viewport.height;
    final halfW = halfH * aspect;
    return Rect.fromCenter(
      center: _camera.lookAt,
      width: halfW * 2,
      height: halfH * 2,
    );
  }

  void _clearCut() {
    _cut = null;
    _cutGlowing = false;
  }

  void _clearFold() {
    _foldTimer?.cancel();
    _foldSheetId = null;
    _foldStart = null;
    _foldEnd = null;
    _foldGlowing = false;
    _foldTapAt = null;
  }

  void _setTool(_CraftTool tool) {
    setState(() {
      _tool = tool;
      _moving = false;
      _clearCut();
      _clearFold();
      _marqueeStart = null;
      _marqueeCurrent = null;
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _multiTouch = true;
      _dragged = true;
      _span = null;
      _pinchCentroid = null;
      _marqueeStart = null;
      _marqueeCurrent = null;
      setState(() {});
      return;
    }
    _dragged = false;
    _downScreen = event.localPosition;
    if (_tool == _CraftTool.select && _selectMode == _SelectMode.marquee) {
      _marqueeStart = event.localPosition;
      _marqueeCurrent = event.localPosition;
    } else if (_moving) {
      final world = _world(event.localPosition);
      final center = selectionCenter(_area);
      if (world != null && center != null) {
        _moveOrigin = _area;
        _moveAnchor = world;
        _moveCenter = center;
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
    if (_multiTouch) return;
    final down = _downScreen;
    if (down != null && (event.localPosition - down).distance > _tapSlop) {
      _dragged = true;
    }
    if (_tool == _CraftTool.select &&
        _selectMode == _SelectMode.marquee &&
        _marqueeStart != null) {
      _marqueeCurrent = event.localPosition;
      setState(() {});
      return;
    }
    if (_moving && _moveOrigin != null && _moveAnchor != null) {
      final world = _world(event.localPosition);
      if (world != null) _dragMove(world);
      setState(() {});
      return;
    }
    // A tap must not slide the sheet out from under the reticle before the
    // finger comes up. Panning starts only after the press is a drag.
    if (!_dragged) return;
    _pan(event.localPosition - previous);
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent event) {
    final alone = _pointers.length == 1;
    _pointers.remove(event.pointer);
    if (_pointers.isNotEmpty) {
      _span = null;
      _pinchCentroid = null;
      setState(() {});
      return;
    }
    final dragged = _dragged;
    final multi = _multiTouch;
    _multiTouch = false;
    _span = null;
    _pinchCentroid = null;
    _dragged = false;
    if (!alone || multi) {
      _cancelGesture();
      setState(() {});
      return;
    }
    if (_tool == _CraftTool.select && _selectMode == _SelectMode.marquee) {
      _finishMarquee();
    } else if (_moving && dragged) {
      _finishMove();
    } else if (!dragged) {
      _onTap();
    } else if (_tool == _CraftTool.scissors && _cut != null) {
      _cutGlowing = true;
    } else if (_tool == _CraftTool.folder &&
        _foldStart != null &&
        _foldEnd == null) {
      _foldGlowing = true;
    }
    _downScreen = null;
    setState(() {});
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_pointers.isEmpty) _cancelGesture();
    setState(() {});
  }

  void _cancelGesture() {
    _marqueeStart = null;
    _marqueeCurrent = null;
    if (_moveOrigin != null) _area = _moveOrigin!;
    _moveOrigin = null;
    _moveAnchor = null;
    _moveCenter = null;
    _multiTouch = false;
    _dragged = false;
  }

  void _twoFinger() {
    if (_pointers.length < 2) return;
    final points = _pointers.values.toList();
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

  void _onTap() {
    final aim = _aim();
    if (aim == null) return;
    switch (_tool) {
      case _CraftTool.select:
        if (_selectMode == _SelectMode.point) _selectTap(aim);
      case _CraftTool.scissors:
        _cutTap(aim);
      case _CraftTool.folder:
        _foldTap(aim);
    }
  }

  void _selectTap(Offset aim) {
    final under = piecesUnderAim(_area, aim);
    if (under.isEmpty) {
      _area = _area.copy(selected: const {});
      _pickStack = const [];
      _pickClicks = 0;
      return;
    }
    final now = DateTime.now();
    final repeat =
        _pickTapAt != null &&
        now.difference(_pickTapAt!) <= stackTapInterval &&
        _sameKeys(_pickStack, under);
    _pickClicks = repeat ? _pickClicks + 1 : 1;
    _pickStack = under;
    _pickTapAt = now;
    final key = under[stackPickIndex(_pickClicks, under.length)];
    _area = _area.copy(selected: {key});
  }

  void _cutTap(Offset aim) {
    final lock = _cut;
    if (lock == null) {
      _cut = lockCut(aim, _area, _scale);
      _cutGlowing = false;
      return;
    }
    final end = _resolvedEnd(lock, aim);
    if (end == null) return;
    final next = commitCut(_area, lock.sheetId, lock.point, end);
    if (next == null) return;
    _apply(next);
    _clearCut();
  }

  /// Model-space end of the locked cut. The reticle picks a grid or crease
  /// point, and the stroke continues through that point to the far edge.
  Offset? _resolvedEnd(CutLock lock, Offset aim) {
    final piece = pieceForKey(_area, mixedPieceKey(lock.sheetId, lock.pieceId));
    final separation = piece?.separation ?? Offset.zero;
    final through = snapCraft(aim, _scale, _area) - separation;
    final ring = piece?.vertices;
    if (ring == null) return through;
    return cutSpanEnd(lock.point, through, ring) ?? through;
  }

  void _foldTap(Offset aim) {
    final start = _foldStart;
    if (start == null) {
      final lock = lockFold(aim, _area, _scale);
      if (lock != null) {
        final piece = pieceForKey(
          _area,
          mixedPieceKey(lock.sheetId, lock.pieceId),
        );
        _foldSheetId = lock.sheetId;
        _foldStart = lock.point + (piece?.separation ?? Offset.zero);
        _foldGlowing = false;
        return;
      }
      final opened = unfoldUnder(_area, aim);
      if (opened != null) _apply(opened);
      return;
    }
    if (_foldEnd == null) {
      final end = snapCraft(aim, _scale, _area);
      if ((end - start).distance < 1e-3) return;
      _foldEnd = end;
      _foldGlowing = true;
      return;
    }
    _foldFaceTap(aim);
  }

  void _foldFaceTap(Offset aim) {
    final sheetId = _foldSheetId;
    final start = _foldStart;
    final end = _foldEnd;
    if (sheetId == null || start == null || end == null) return;
    final now = DateTime.now();
    if (_foldTapAt != null && now.difference(_foldTapAt!) <= stackTapInterval) {
      _foldTimer?.cancel();
      _foldTapAt = null;
      _apply(foldSpan(_area, sheetId, start, end, aim));
      _clearFold();
      return;
    }
    _foldTapAt = now;
    _foldTimer?.cancel();
    _foldTimer = Timer(stackTapInterval, () {
      if (!mounted || _foldEnd == null || _foldSheetId != sheetId) return;
      setState(() {
        _apply(scoreSpan(_area, sheetId, start, end, aim));
        _clearFold();
      });
    });
  }

  void _dragMove(Offset world) {
    final origin = _moveOrigin;
    final anchor = _moveAnchor;
    final center = _moveCenter;
    if (origin == null || anchor == null || center == null) return;
    final snapped = snapCraft(center + (world - anchor), _scale, origin);
    _area = movePieces(origin, snapped - center) ?? origin;
  }

  void _finishMove() {
    final origin = _moveOrigin;
    if (origin != null && !identical(_area, origin)) {
      _history.push(origin);
    }
    _moveOrigin = null;
    _moveAnchor = null;
    _moveCenter = null;
    _moving = false;
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
    _area = _area.copy(
      selected: mixedMarqueeHits(_area, world, marqueePick(start, end)),
    );
  }

  Rect? _worldRect(Offset a, Offset b) {
    final corners = <Offset>[];
    for (final screen in [a, Offset(b.dx, a.dy), b, Offset(a.dx, b.dy)]) {
      final world = _world(screen);
      if (world == null) return null;
      corners.add(world);
    }
    var minX = corners.first.dx;
    var minY = corners.first.dy;
    var maxX = corners.first.dx;
    var maxY = corners.first.dy;
    for (final point in corners) {
      minX = math.min(minX, point.dx);
      minY = math.min(minY, point.dy);
      maxX = math.max(maxX, point.dx);
      maxY = math.max(maxY, point.dy);
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  (Offset, Offset)? _segment() {
    final aim = _aim();
    if (_tool == _CraftTool.scissors) {
      final lock = _cut;
      if (lock == null || aim == null) return null;
      final piece = pieceForKey(
        _area,
        mixedPieceKey(lock.sheetId, lock.pieceId),
      );
      final separation = piece?.separation ?? Offset.zero;
      final end = _resolvedEnd(lock, aim);
      if (end == null) return null;
      return (lock.point + separation, end + separation);
    }
    final start = _foldStart;
    if (_tool != _CraftTool.folder || start == null) return null;
    final end = _foldEnd;
    if (end != null) return (start, end);
    if (aim == null) return null;
    return (start, snapCraft(aim, _scale, _area));
  }

  void _queueScissorSync() {
    if (_scissorSyncQueued) return;
    _scissorSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scissorSyncQueued = false;
      if (!mounted) return;
      _syncScissors();
    });
  }

  void _syncScissors() {
    if (!mounted || _viewport.width < 2) return;
    if (_flight.phase == ToolFlightPhase.cut) return;
    final next = _scissorCue();
    final duration = _flight.offer(
      next,
      t: _flightAnim.value,
      approach: _approachFor(next),
    );
    if (duration != null) _playFlight(duration);
  }

  ToolCue? _scissorCue() {
    if (_tool != _CraftTool.scissors) return null;
    final aim = _aim();
    if (aim == null) return null;
    final lock = _cut;
    if (lock == null) {
      final preview = lockCut(aim, _area, _scale, maxCells: null);
      if (preview == null) return null;
      final piece = pieceForKey(
        _area,
        mixedPieceKey(preview.sheetId, preview.pieceId),
      );
      if (piece == null) return null;
      final march = placeOnRing(preview.point, piece.vertices);
      if (march == null) return null;
      return ToolCue(
        anchor: preview.point + piece.separation,
        direction: march.direction,
        aim: aim,
        reach: _scale * 0.75,
      );
    }
    final line = _segment();
    if (line == null) return null;
    final delta = line.$2 - line.$1;
    if (delta.distance < 1e-6) return null;
    return ToolCue(
      anchor: line.$1,
      direction: delta / delta.distance,
      aim: aim,
      reach: _scale * 0.75,
    );
  }

  ScreenApproach? _approachFor(ToolCue? next) {
    final pose = _flight.pose(_flightAnim.value);
    final anchor = next?.anchor ?? pose.tip;
    final direction = next?.direction ?? pose.direction;
    final screen = _project(anchor);
    final ahead = _project(anchor + direction * 10);
    if (screen == null || ahead == null) return null;
    return approachFor(
      anchor: screen,
      heading: ahead - screen,
      viewport: _viewport,
    );
  }

  Offset? _project(Offset world) {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.camera.projectToScreen(
      Vector3(world.dx, world.dy, 0),
      _viewport,
    );
  }

  void _playFlight(Duration duration) {
    if (!mounted) return;
    _flightAnim.duration = duration;
    _flightAnim.forward(from: 0);
  }

  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final phase = _flight.phase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _flight.phase != phase) return;
      _flight.land();
      _syncScissors();
      setState(() {});
    });
  }

  void _queueFoldSync() {
    if (_foldSyncQueued) return;
    _foldSyncQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _foldSyncQueued = false;
      if (!mounted) return;
      _syncFolder();
    });
  }

  void _syncFolder() {
    if (!mounted || _viewport.width < 2) return;
    if (_foldFlight.phase == ToolFlightPhase.cut) return;
    final next = _folderCue();
    final duration = _foldFlight.offer(
      next,
      t: _foldFlightAnim.value,
      approach: _foldApproach(next),
    );
    if (duration != null) _playFoldFlight(duration);
  }

  ToolCue? _folderCue() {
    if (_tool != _CraftTool.folder) return null;
    final aim = _aim();
    if (aim == null) return null;
    final start = _foldStart;
    if (start == null) {
      final preview = lockFold(aim, _area, _scale, maxCells: null);
      if (preview == null) return null;
      final piece = pieceForKey(
        _area,
        mixedPieceKey(preview.sheetId, preview.pieceId),
      );
      if (piece == null) return null;
      final march = placeOnRing(preview.point, piece.vertices);
      if (march == null) return null;
      return ToolCue(
        anchor: preview.point + piece.separation,
        direction: march.direction,
        aim: aim,
        reach: _scale * 0.75,
      );
    }
    final end = _foldEnd ?? snapCraft(aim, _scale, _area);
    final delta = end - start;
    final direction = delta.distance < 1e-6
        ? (_foldFlight.target?.direction ?? const Offset(1, 0))
        : delta / delta.distance;
    return ToolCue(
      anchor: start,
      direction: direction,
      aim: aim,
      reach: _scale * 0.75,
    );
  }

  ScreenApproach? _foldApproach(ToolCue? next) {
    final pose = _foldFlight.pose(_foldFlightAnim.value);
    final anchor = next?.anchor ?? pose.tip;
    final direction = next?.direction ?? pose.direction;
    final screen = _project(anchor);
    final ahead = _project(anchor + direction * 10);
    if (screen == null || ahead == null) return null;
    return approachFor(
      anchor: screen,
      heading: ahead - screen,
      viewport: _viewport,
    );
  }

  void _playFoldFlight(Duration duration) {
    if (!mounted) return;
    _foldFlightAnim.duration = duration;
    _foldFlightAnim.forward(from: 0);
  }

  void _onFoldFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final phase = _foldFlight.phase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _foldFlight.phase != phase) return;
      _foldFlight.land();
      _syncFolder();
      setState(() {});
    });
  }

  double _chrome(Size size) {
    final short = math.min(size.width, size.height);
    return (short * 0.11).clamp(44.0, 72.0);
  }

  @override
  Widget build(BuildContext context) {
    _queueScissorSync();
    _queueFoldSync();
    return FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: const [FmDevBackButton()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          if (!_framed && _viewport.width > 2) {
            _framed = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              _frame();
              setState(() {});
            });
          }
          final chrome = _chrome(_viewport);
          final aim = _aim();
          final snap = aim == null ? null : snapCraft(aim, _scale, _area);
          final cutMark = _tool == _CraftTool.scissors && _cut != null
              ? snap
              : null;
          final foldMark = _tool == _CraftTool.folder && _foldStart != null
              ? (_foldEnd ?? snap)
              : null;
          final hover = _tool == _CraftTool.select || aim == null
              ? null
              : pieceUnderAim(_area, aim);
          final segment = _segment();
          final screenCenter = selectionCenter(_area);
          final menuCenter = screenCenter == null
              ? null
              : _camera.camera.projectToScreen(
                  Vector3(screenCenter.dx, screenCenter.dy, 0),
                  _viewport,
                );
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent ||
                        event.scrollDelta.dy == 0) {
                      return;
                    }
                    _zoom(math.exp(-event.scrollDelta.dy * 0.002));
                    setState(() {});
                  },
                  onPointerDown: _onPointerDown,
                  onPointerMove: _onPointerMove,
                  onPointerUp: _onPointerUp,
                  onPointerCancel: _onPointerCancel,
                  child: AnimatedBuilder(
                    animation: _camera,
                    builder: (context, _) {
                      return CustomPaint(
                        key: const Key('mixed-craft-canvas'),
                        painter: MixedCraftPainter(
                          camera: _camera,
                          area: _area,
                          grids: _grids.opacities(_gridFade.value),
                          view: _visible(),
                          hoverKey: hover,
                          segment: segment,
                          segmentGlows: _tool == _CraftTool.scissors
                              ? _cutGlowing
                              : _foldGlowing || _foldEnd != null,
                          foldSegment: _tool == _CraftTool.folder,
                          marquee: _marqueeRect(),
                          marqueeCross:
                              _marqueeStart != null &&
                              _marqueeCurrent != null &&
                              marqueePick(_marqueeStart!, _marqueeCurrent!) ==
                                  MarqueePick.cross,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
              if (_tool == _CraftTool.scissors ||
                  _flight.phase != ToolFlightPhase.absent)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _flightAnim,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: ScissorGlyphPainter(
                            camera: _camera,
                            pose: _flight.pose(_flightAnim.value),
                            tool: _scissors,
                            glyphScale: 0.5,
                            destination: cutMark,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              if (_tool == _CraftTool.folder ||
                  _foldFlight.phase != ToolFlightPhase.absent)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _foldFlightAnim,
                      builder: (context, _) {
                        return CustomPaint(
                          painter: FoldGlyphPainter(
                            camera: _camera,
                            pose: _foldFlight.pose(_foldFlightAnim.value),
                            destination: foldMark,
                          ),
                        );
                      },
                    ),
                  ),
                ),
              const IgnorePointer(child: ViewCrosshair()),
              if (_tool == _CraftTool.select &&
                  menuCenter != null &&
                  _area.selected.isNotEmpty &&
                  _marqueeStart == null &&
                  _moveOrigin == null)
                Positioned.fill(
                  child: ObjectRadialMenu(
                    center: menuCenter,
                    actions: [
                      RadialAction(
                        icon: Icons.open_with,
                        label: 'Move',
                        tint: const Color(0xFF90A4AE),
                        onTap: () => setState(() => _moving = true),
                      ),
                      RadialAction(
                        icon: Icons.rotate_right,
                        label: 'Rotate',
                        tint: const Color(0xFFFFD54F),
                        onTap: () =>
                            setState(() => _apply(rotateSelection(_area))),
                      ),
                      RadialAction(
                        icon: Icons.visibility_off,
                        label: 'Hide',
                        tint: const Color(0xFF78909C),
                        onTap: () =>
                            setState(() => _apply(hideSelection(_area))),
                      ),
                    ],
                  ),
                ),
              FmSafePositioned(
                right: 8,
                top: 56,
                minimum: kFmScreenInset,
                child: _paperRail(chrome),
              ),
              FmSafePositioned(
                left: 8,
                bottom: 8,
                minimum: kFmScreenInset,
                child: _cornerColumn(
                  chrome: chrome,
                  top: _historyButton(
                    key: const Key('mixed-undo'),
                    icon: Icons.undo,
                    enabled: _history.canUndo,
                    onTap: () {
                      final previous = _history.undo(_area);
                      if (previous == null) return;
                      setState(() {
                        _area = previous;
                        _clearCut();
                        _clearFold();
                      });
                    },
                  ),
                  bottom: _scaleButton(
                    key: const Key('mixed-plus'),
                    icon: Icons.add,
                    onTap: () => _stepScale(finer: true),
                  ),
                ),
              ),
              FmSafePositioned(
                right: 8,
                bottom: 8,
                minimum: kFmScreenInset,
                child: _cornerColumn(
                  chrome: chrome,
                  top: _historyButton(
                    key: const Key('mixed-redo'),
                    icon: Icons.redo,
                    enabled: _history.canRedo,
                    onTap: () {
                      final next = _history.redo(_area);
                      if (next == null) return;
                      setState(() {
                        _area = next;
                        _clearCut();
                        _clearFold();
                      });
                    },
                  ),
                  bottom: _scaleButton(
                    key: const Key('mixed-minus'),
                    icon: Icons.remove,
                    onTap: () => _stepScale(finer: false),
                  ),
                ),
              ),
              FmSafePositioned(
                left: 0,
                right: 0,
                bottom: 8,
                minimum: kFmScreenInset,
                child: _toolbar(chrome),
              ),
            ],
          );
        },
      ),
    );
  }

  Rect? _marqueeRect() {
    final start = _marqueeStart;
    final end = _marqueeCurrent;
    if (start == null || end == null) return null;
    return Rect.fromPoints(start, end);
  }

  Widget _toolbar(double chrome) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: chrome + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_tool == _CraftTool.select) _selectModes(chrome),
          HudToolCarousel<_CraftTool>(
            items: [
              HudCarouselItem(
                value: _CraftTool.select,
                icon: Icons.near_me,
                label: 'Select',
                fill: CraftPalette.kentuckyBlue.fill,
              ),
              HudCarouselItem(
                value: _CraftTool.scissors,
                icon: Icons.content_cut,
                label: 'Scissors',
                fill: CraftPalette.scarlet.fill,
              ),
              HudCarouselItem(
                value: _CraftTool.folder,
                icon: Icons.flip,
                label: 'Folder',
                fill: CraftPalette.carmel.fill,
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
              _moving = false;
            }),
          ),
        ],
      ),
    );
  }

  Widget _paperRail(double chrome) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _paperButton(kPapercutYellow, 'Yellow', chrome),
        const SizedBox(height: 8),
        _paperButton(kPapercutGreen, 'Green', chrome),
        for (final key in _area.hidden) ...[
          const SizedBox(height: 8),
          _hiddenButton(key, chrome),
        ],
      ],
    );
  }

  Widget _paperButton(Color color, String label, double chrome) {
    return GestureDetector(
      onTap: () => setState(() {
        _apply(placeSheet(_area, color, _scale));
      }),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: chrome,
            height: chrome,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: const Color(0xBFFFFFFF)),
              boxShadow: const [
                BoxShadow(color: Color(0x33000000), offset: Offset(2, 2)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: Colors.white, fontSize: chrome * 0.22),
          ),
        ],
      ),
    );
  }

  Widget _hiddenButton(String key, double chrome) {
    final piece = pieceForKey(_area, key);
    return GestureDetector(
      onTap: () => setState(() => _apply(showPiece(_area, key))),
      child: Container(
        width: chrome * 0.72,
        height: chrome * 0.72,
        color: (piece?.color ?? kPapercutYellow).withValues(alpha: 0.45),
      ),
    );
  }

  Widget _cornerColumn({
    required double chrome,
    required Widget top,
    required Widget bottom,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [top, const SizedBox(height: 8), bottom],
    );
  }

  Widget _historyButton({
    required Key key,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        key: key,
        onTap: enabled ? onTap : null,
        child: Container(
          width: _chrome(_viewport),
          height: _chrome(_viewport),
          decoration: const BoxDecoration(
            color: Color(0xFF9A9AA4),
            border: Border(
              top: BorderSide(color: Color(0xFFE4E4EC), width: 2),
              left: BorderSide(color: Color(0xFFE4E4EC), width: 2),
              right: BorderSide(color: Color(0xFF5A5A64), width: 2),
              bottom: BorderSide(color: Color(0xFF5A5A64), width: 2),
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: _chrome(_viewport) * 0.46,
          ),
        ),
      ),
    );
  }

  Widget _scaleButton({
    required Key key,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    final size = _chrome(_viewport);
    return GestureDetector(
      key: key,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        color: Colors.black,
        alignment: Alignment.center,
        child: Icon(icon, color: Colors.white, size: size * 0.5),
      ),
    );
  }
}

bool _sameKeys(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  final other = b.toSet();
  return a.every(other.contains);
}
