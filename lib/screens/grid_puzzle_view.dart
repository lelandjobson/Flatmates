import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../geometry/polygon_union.dart';
import '../gridcraft/blueprint.dart';
import '../gridcraft/edit.dart';
import '../gridcraft/level_io.dart';
import '../gridcraft/painter.dart';
import '../gridcraft/scissor.dart';
import '../gridcraft/scissor_glyph.dart';
import '../gridcraft/tool_animation.dart';
import '../gridcraft/tool_animation_io.dart';
import '../gridcraft/tool_flight.dart';
import '../gridcraft/twin_ls.dart';
import '../papercut/camera.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../papercut/split.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';

enum _GridTool { scissors, straightEdge }

enum _Stamp { paint, rectangle, circle }

const Duration _kTurnDuration = Duration(milliseconds: 750);
const Duration _kFocusDuration = Duration(milliseconds: 320);

/// Grid-locked puzzle play and a paint editor for blueprint steps.
class GridPuzzleView extends StatefulWidget {
  const GridPuzzleView({super.key, this.store});

  final LevelStore? store;

  @override
  State<GridPuzzleView> createState() => _GridPuzzleViewState();
}

class _GridPuzzleViewState extends State<GridPuzzleView>
    with TickerProviderStateMixin {
  final LevelStore _store = LevelStore();
  late PapercutCamera _camera;
  late AnimationController _flash;
  late AnimationController _turnAnim;
  late AnimationController _splitAnim;
  late AnimationController _rollNudge;
  late AnimationController _flightAnim;
  late AnimationController _focusAnim;
  final ToolFlight _flight = ToolFlight();
  Offset _focusFrom = Offset.zero;
  Offset _focusTo = Offset.zero;
  bool _armingCut = false;
  Offset? _armedFrom;
  Offset? _armedTo;
  ToolAnimation _scissors = ScissorToolAnimation();
  final FocusNode _keys = FocusNode();
  List<Offset> _splitFrom = const [];
  List<Offset> _splitTo = const [];
  double _rollFrom = 0;
  double _rollTo = 0;
  GridStep? _turnFromStep;
  PapercutSheet? _turnFromSheet;
  ScissorMarch? _turnFromMarch;
  PapercutSheet? _turnFromBase;
  Offset? _turnOrigin;
  bool _turnClockwise = true;

  List<GridBlueprint> _levels = [twinLsBlueprint()];
  GridBlueprint _blueprint = twinLsBlueprint();
  GridStep _baseline = twinLsBlueprint().steps.first;
  int _stepIndex = 0;
  late PapercutSheet _sheet;
  ScissorMarch? _march;
  PapercutSheet? _marchBase;
  final List<PapercutSheet> _undo = [];

  _GridTool _tool = _GridTool.scissors;
  bool _fold = false;
  bool _editing = false;
  _Stamp _stamp = _Stamp.paint;
  Set<(int, int)> _painted = {};
  (int, int)? _stampAnchor;
  Set<int> _selected = {};
  double? _rulerX;
  bool _rolling = false;
  Offset? _strokeDirection;
  bool _needsFrame = true;
  double _rollStart = 0;
  double _moved = 0;
  double _gestureScale = 1;
  bool _zoomed = false;
  Size _viewport = Size.zero;

  LevelStore get _levelsStore => widget.store ?? _store;

  GridStep get _step => _blueprint.steps[_stepIndex];

  bool get _locked => _march?.locked ?? false;

  @override
  void initState() {
    super.initState();
    _camera = PapercutCamera()..addListener(_onCamera);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..repeat(reverse: true);
    _turnAnim = AnimationController(vsync: this, duration: _kTurnDuration)
      ..addListener(_onTurnTick)
      ..addStatusListener(_onTurnStatus);
    _splitAnim = AnimationController(vsync: this, duration: _kTurnDuration)
      ..addListener(_onSplitTick)
      ..addStatusListener(_onSplitStatus);
    _rollNudge = AnimationController(vsync: this, duration: _kTurnDuration)
      ..addListener(_onRollNudge);
    _flightAnim = AnimationController(vsync: this, duration: kArriveDuration)
      ..addListener(_followCut)
      ..addStatusListener(_onFlightStatus);
    _focusAnim = AnimationController(vsync: this, duration: _kFocusDuration)
      ..addListener(_onFocusTick)
      ..addStatusListener(_onFocusStatus);
    _loadStep(0, _blueprint);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _keys.requestFocus();
      _syncFlight();
    });
    _refreshLevels();
    _loadToolAnimations();
  }

  Future<void> _loadToolAnimations() async {
    final tools = await ToolAnimationStore().load();
    if (!mounted) return;
    ToolAnimation? scissors;
    for (final tool in tools) {
      if (tool.id == 'scissors') scissors = tool;
    }
    final chosen = scissors;
    if (chosen == null) return;
    setState(() => _scissors = chosen);
  }

  @override
  void dispose() {
    _focusAnim.dispose();
    _flightAnim.dispose();
    _rollNudge.dispose();
    _keys.dispose();
    _splitAnim.dispose();
    _turnAnim.dispose();
    _flash.dispose();
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    _syncFlight();
    if (mounted) setState(() {});
  }

  Future<void> _refreshLevels() async {
    final saved = await _levelsStore.loadAll();
    if (!mounted) return;
    setState(() {
      _levels = [twinLsBlueprint(), ...saved.where((level) => level.id != 'twin-ls')];
    });
  }

  void _loadStep(int index, GridBlueprint blueprint) {
    if (_turnAnim.isAnimating) _turnAnim.stop();
    if (_splitAnim.isAnimating) _splitAnim.stop();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _armingCut = false;
    _armedFrom = null;
    _armedTo = null;
    _flight.reset();
    _strokeDirection = null;
    _turnFromStep = null;
    _blueprint = blueprint;
    _stepIndex = index.clamp(0, blueprint.steps.length - 1);
    _baseline = _step;
    _sheet = _freshSheet(_step);
    _march = null;
    _marchBase = null;
    _undo.clear();
    _painted = {};
    _selected = {};
    _rulerX = _snap(_step.paper.center.dx, _step.gridSpacing);
    _needsFrame = true;
    _frame();
    _syncFlight();
  }

  PapercutSheet _freshSheet(GridStep step) {
    final paper = step.paper;
    return PapercutSheet(
      pieces: [
        PapercutPiece(
          id: 'paper',
          color: kPapercutYellow,
          vertices: [
            paper.topLeft,
            paper.topRight,
            paper.bottomRight,
            paper.bottomLeft,
          ],
        ),
      ],
    );
  }

  void _frame() {
    final paper = _step.paper;
    _camera.frameSheet(
      _viewport,
      sheetMm: math.max(paper.width, paper.height),
      center: paper.center,
    );
  }

  double _snap(double value, double spacing) =>
      (value / spacing).roundToDouble() * spacing;

  bool get _cutting => _flight.phase == ToolFlightPhase.cut || _armingCut;

  void _onScissorTap(Offset world) {
    if (_cutting) return;
    if (_march == null) {
      final edge = _nearestEdge(world);
      if (edge == null) return;
      final placed = _place(edge);
      if (placed == null) return;
      setState(() {
        _marchBase = _sheet;
        _march = placed;
      });
    }
    final ghost = _scissorGhost(world);
    if (ghost == null) {
      _pinScissor();
      _syncFlight();
      return;
    }
    _startCut();
  }

  void _startCut() {
    final ghost = _scissorGhost(_aimWorld());
    if (ghost == null) return;
    final from = _shown(ghost.$1);
    final to = _shown(ghost.$2);
    final delta = to - from;
    if (delta.distance < 1e-6) return;
    _strokeDirection = delta / delta.distance;
    _armedFrom = from;
    _armedTo = to;
    _armingCut = true;
    _animateFocus(from);
  }

  /// Eases [lookAt] onto [point]. A point already under the crosshair finishes
  /// immediately. The cut itself starts when this arrival completes.
  void _animateFocus(Offset point) {
    if ((_camera.lookAt - point).distance < 1e-3) {
      if (_focusAnim.isAnimating) _focusAnim.stop();
      _camera.focusOn(point);
      _finishFocus();
      return;
    }
    _focusFrom = _camera.lookAt;
    _focusTo = point;
    _focusAnim.forward(from: 0);
  }

  void _onFocusTick() {
    if (!_armingCut) return;
    final t = Curves.easeInOutCubic.transform(_focusAnim.value);
    _camera.focusOn(Offset.lerp(_focusFrom, _focusTo, t)!);
  }

  void _onFocusStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _finishFocus();
  }

  void _finishFocus() {
    if (!_armingCut) return;
    final from = _armedFrom;
    final to = _armedTo;
    final direction = _strokeDirection;
    _armingCut = false;
    if (from == null || to == null || direction == null) return;
    _flight.beginCut(
      from: from,
      to: to,
      direction: direction,
      t: _flightAnim.value,
      present: (_march?.path.length ?? 1) <= 1,
    );
    _playFlight(kCutDuration);
  }

  Offset _screenUp() =>
      rotateGridPointBy(const Offset(0, 1), Offset.zero, -_camera.roll);

  Offset _shown(Offset model) {
    for (final piece in _sheet.pieces) {
      if (ownsPoint(piece.vertices, model)) return model + piece.separation;
    }
    return model;
  }

  void _pinScissor() {
    final march = _march;
    if (march == null || _viewport.width < 2) return;
    _camera.focusOn(_shown(march.position));
  }

  /// Keeps the crosshair on the blade while a stroke is in progress.
  void _followCut() {
    if (_flight.phase != ToolFlightPhase.cut || _viewport.width < 2) return;
    _camera.focusOn(_flight.pose(_flightAnim.value).tip);
  }

  Offset? _nearestEdge(Offset aim) {
    Offset? best;
    var bestDistance = double.infinity;
    for (final piece in _sheet.pieces) {
      final shown = [for (final vertex in piece.vertices) vertex + piece.separation];
      final hit = closestGridEdgePoint(aim, [shown], _step.gridSpacing);
      if (hit == null) continue;
      final distance = (hit - aim).distance;
      if (distance >= bestDistance) continue;
      best = hit - piece.separation;
      bestDistance = distance;
    }
    return best;
  }

  ScissorMarch? _place(Offset point) {
    for (final piece in _sheet.pieces) {
      final march = placeOnRing(point, piece.vertices);
      if (march != null) return march;
    }
    return placeScissor(point, _step.paper);
  }

  /// Maps a point on the drawn paper back to grid space.
  Offset _toModel(Offset aim) {
    for (final piece in _sheet.pieces) {
      if (piece.separation == Offset.zero) continue;
      final shown = [for (final vertex in piece.vertices) vertex + piece.separation];
      if (ownsPoint(shown, aim)) return aim - piece.separation;
    }
    return aim;
  }

  /// True when the cut split a piece off. Null when the cut did not apply.
  bool? _commitMarch() {
    final march = _march;
    final base = _marchBase;
    if (march == null || base == null) return null;
    final commit = commitScissor(
      march: march,
      step: _step,
      base: base,
      direction: _strokeDirection ?? _screenUp(),
    );
    _strokeDirection = null;
    if (commit == null) return null;
    _pushUndo();
    final split = commit.march == null;
    final spread = split
        ? spreadPieces(base, commit.sheet, _step.gridSpacing)
        : commit.sheet;
    setState(() {
      _sheet = split ? commit.sheet : spread;
      _march = commit.march;
      if (split) _marchBase = null;
    });
    if (!split) {
      _pinScissor();
      return false;
    }
    _splitFrom = [for (final piece in commit.sheet.pieces) piece.separation];
    _splitTo = [for (final piece in spread.pieces) piece.separation];
    _splitAnim.forward(from: 0);
    return true;
  }

  void _onSplitTick() {
    if (_splitFrom.length != _sheet.pieces.length ||
        _splitTo.length != _sheet.pieces.length) {
      return;
    }
    final t = Curves.easeOutCubic.transform(_splitAnim.value);
    setState(() {
      _sheet = PapercutSheet(
        pieces: [
          for (var i = 0; i < _sheet.pieces.length; i++)
            _sheet.pieces[i].copyWith(
              separation: Offset.lerp(_splitFrom[i], _splitTo[i], t)!,
            ),
        ],
        cutStrokes: _sheet.cutStrokes,
        creases: _sheet.creases,
        nextPieceId: _sheet.nextPieceId,
      );
    });
  }

  void _onStraightTap(Offset aim) {
    final world = _toModel(aim);
    final x = _snap(world.dx, _step.gridSpacing);
    final span = verticalSpan(
      contact: Offset(x, world.dy),
      step: _step,
      sheet: _sheet,
    );
    if (span == null) return;
    final next = _fold
        ? applyPapercutCrease(
            _sheet,
            a: span.$1,
            b: span.$2,
            groupId: 'fold-${_sheet.creases.length}',
            angleDegrees: 90,
          )
        : applyPapercutCut(_sheet, [span.$1, span.$2]);
    if (next == null) return;
    if (!_locked) _pushUndo();
    setState(() => _sheet = next);
  }

  void _rotatePiece(bool clockwise) {
    if (_splitAnim.isAnimating) return;
    _animateQuarter(!clockwise);
  }

  void _onTurnTick() {
    final origin = _turnOrigin;
    final fromStep = _turnFromStep;
    final fromSheet = _turnFromSheet;
    if (origin == null || fromStep == null || fromSheet == null) return;
    final t = Curves.easeOutCubic.transform(_turnAnim.value);
    final radians = (_turnClockwise ? -1 : 1) * math.pi / 2 * t;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = rotateStepBy(fromStep, origin, radians);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _sheet = rotateSheetBy(fromSheet, origin, radians);
      _showMarch(origin, radians);
    });
    _pinScissor();
    _syncFlight();
  }

  void _onTurnStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final origin = _turnOrigin;
    final fromStep = _turnFromStep;
    final fromSheet = _turnFromSheet;
    if (origin == null || fromStep == null || fromSheet == null) return;
    final radians = (_turnClockwise ? -1 : 1) * math.pi / 2;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = rotateStep(fromStep, clockwise: _turnClockwise);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _baseline = steps[_stepIndex];
      _sheet = rotateSheet(fromSheet, origin, clockwise: _turnClockwise);
      _showMarch(origin, radians);
      _rulerX = _snap(_step.paper.center.dx, _step.gridSpacing);
      _turnFromStep = null;
      _turnFromSheet = null;
      _turnFromMarch = null;
      _turnFromBase = null;
    });
    _pinScissor();
    _syncFlight();
  }

  void _showMarch(Offset origin, double radians) {
    final march = _turnFromMarch;
    if (march == null) return;
    _march = ScissorMarch(
      path: [
        for (final point in march.path) rotateGridPointBy(point, origin, radians),
      ],
      direction: rotateGridPointBy(march.direction, Offset.zero, radians),
      locked: march.locked,
    );
    final base = _turnFromBase;
    if (base != null) {
      _marchBase = rotateSheetBy(base, origin, radians);
    }
  }

  void _clear() {
    _turnAnim.stop();
    _splitAnim.stop();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _armingCut = false;
    _armedFrom = null;
    _armedTo = null;
    _flight.reset();
    _strokeDirection = null;
    _turnFromStep = null;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = _baseline;
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _sheet = _freshSheet(_step);
      _march = null;
      _marchBase = null;
      _undo.clear();
      _painted = {};
      _selected = {};
    });
    _syncFlight();
  }

  void _toggleEdit() {
    if (_locked) return;
    setState(() {
      _editing = !_editing;
      _painted = {};
      _stampAnchor = null;
      if (!_editing) _selected = {};
    });
    _syncFlight();
  }

  void _paintCell(Offset world) {
    final spacing = _step.gridSpacing;
    final cell = ((world.dx / spacing).floor(), (world.dy / spacing).floor());
    if (_stamp == _Stamp.paint) {
      _painted.add(cell);
      return;
    }
    _stampAnchor ??= cell;
    final anchor = _stampAnchor!;
    _painted = _stamp == _Stamp.circle
        ? circleCells(anchor.$1, anchor.$2, math.max((cell.$1 - anchor.$1).abs(), (cell.$2 - anchor.$2).abs()))
        : rectangleCells(anchor.$1, anchor.$2, cell.$1, cell.$2);
  }

  void _fusePaint() {
    if (_painted.isEmpty) return;
    final formed = polygonsFromCells(_painted, _step.gridSpacing);
    if (formed.isEmpty) return;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = _step.copyWith(polygons: [..._step.polygons, ...formed]);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _painted = {};
      _stampAnchor = null;
    });
  }

  void _select(Offset world) {
    final index = _polygonIndex(world);
    if (index == null) return;
    setState(() {
      if (!_selected.add(index)) _selected.remove(index);
    });
  }

  void _merge() {
    if (_selected.length < 2) return;
    final chosen = [
      for (final index in _selected) _step.polygons[index],
    ];
    final rest = [
      for (var i = 0; i < _step.polygons.length; i++)
        if (!_selected.contains(i)) _step.polygons[i],
    ];
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = _step.copyWith(polygons: [...rest, ...mergeSelected(chosen)]);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _selected = {};
    });
  }

  Future<void> _save() async {
    await _levelsStore.save(_blueprint);
    await _refreshLevels();
  }

  void _pushUndo() {
    _undo.add(_sheet.clone());
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_locked || _undo.isEmpty) return;
    _splitAnim.stop();
    setState(() {
      _sheet = _undo.removeLast();
      _march = null;
      _marchBase = null;
    });
    _syncFlight();
  }

  /// Side taps and arrow keys. Right is counterclockwise.
  void _nudgeRoll({required bool counterclockwise}) {
    if (_editing || _tool != _GridTool.scissors) return;
    if (_cutting) return;
    _animateQuarter(counterclockwise);
  }

  /// Lands on the next 0/90/180/270. An in-between angle does not add a full
  /// extra quarter on top of itself.
  void _animateQuarter(bool counterclockwise) {
    final base = _rollNudge.isAnimating ? _rollTo : _camera.roll;
    _rollFrom = _camera.roll;
    _rollTo = PapercutCamera.nextQuarterTurn(
      base,
      counterclockwise: counterclockwise,
    );
    _rollNudge.forward(from: 0);
  }

  void _onRollNudge() {
    final t = Curves.easeOutCubic.transform(_rollNudge.value);
    _camera.setRoll(_rollFrom + (_rollTo - _rollFrom) * t);
    _pinScissor();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _nudgeRoll(counterclockwise: true);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _nudgeRoll(counterclockwise: false);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: const [FmDevBackButton()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          if (_needsFrame && _viewport.width > 2) {
            _needsFrame = false;
            _frame();
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (event) {
                    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) {
                      return;
                    }
                    _camera.zoomByScale(math.exp(-event.scrollDelta.dy * 0.002));
                  },
                  child: GestureDetector(
                    key: const Key('grid-puzzle-canvas'),
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: AnimatedBuilder(
                      animation: Listenable.merge([_flash, _flightAnim]),
                      builder: (context, _) {
                        final aim = _aimWorld();
                        return CustomPaint(
                          painter: GridPuzzlePainter(
                            camera: _camera,
                            step: _step,
                            sheet: _sheet,
                            march: null,
                            flash: _flash.value,
                            rulerX: aim == null
                                ? _rulerX
                                : _snap(_toModel(aim).dx, _step.gridSpacing),
                            showRuler:
                                _tool == _GridTool.straightEdge && !_editing,
                            selected: _selected,
                            painted: _painted,
                            ghostCells: _editing ? _stampGhost(aim) : const {},
                            ghostCut: _displayGhost(aim),
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                ),
              ),
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
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),
              const Positioned.fill(
                child: IgnorePointer(child: ViewCrosshair()),
              ),
              FmSafePositioned(top: 8, left: 8, right: 8, child: _topBar()),
              FmSafePositioned(left: 0, right: 0, bottom: 8, child: _toolbar()),
              FmSafePositioned(left: 8, bottom: 8, child: _undoButton()),
            ],
          );
        },
      ),
      ),
    );
  }

  Offset? _lastFocal;
  double _rollAnchor = 0;

  void _onScaleStart(ScaleStartDetails details) {
    _lastFocal = details.localFocalPoint;
    _rollAnchor = details.localFocalPoint.dx;
    _rollStart = _camera.roll;
    _moved = 0;
    _gestureScale = 1;
    _zoomed = false;
    _stampAnchor = null;
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    final local = details.localFocalPoint;
    final previous = _lastFocal ?? local;
    final delta = local - previous;
    _lastFocal = local;
    _moved += delta.distance;
    if (details.pointerCount >= 2 || (details.scale - 1).abs() > 0.02) {
      _zoomed = true;
    }
    if (_rolling && details.pointerCount < 2) {
      if (_cutting) return;
      _camera.setRoll(_rollStart + (local.dx - _rollAnchor) * 0.01);
      _pinScissor();
      return;
    }
    if (details.pointerCount >= 2) {
      if (_gestureScale > 0) {
        _camera.zoomByScale(details.scale / _gestureScale);
      }
      _gestureScale = details.scale;
      _camera.panByScreen(delta, _viewport);
      return;
    }
    if (_editing) {
      final world = _camera.planePoint(local, _viewport);
      if (world != null) setState(() => _paintCell(_toModel(world)));
      return;
    }
    if (_march != null && _tool == _GridTool.scissors) return;
    _camera.panByScreen(delta, _viewport);
    if (_tool == _GridTool.straightEdge) {
      final world = _camera.planePoint(local, _viewport);
      if (world != null) {
        setState(() => _rulerX = _snap(_toModel(world).dx, _step.gridSpacing));
      }
    }
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_zoomed) {
      if (_rolling) {
        _camera.setRoll(PapercutCamera.snapRoll(_camera.roll));
        _pinScissor();
      }
      return;
    }
    if (_rolling) {
      _camera.setRoll(PapercutCamera.snapRoll(_camera.roll));
      _pinScissor();
      return;
    }
    if (_editing) {
      if (_moved < 12) {
        final aim = _aimWorld();
        if (aim != null && _polygonIndex(aim) != null) {
          _select(aim);
          return;
        }
        final ghost = _stampGhost(aim);
        if (ghost.isEmpty) return;
        setState(() => _painted = ghost);
        _fusePaint();
      } else {
        _fusePaint();
      }
      return;
    }
    if (_moved > 12) return;
    if (_tool == _GridTool.scissors) {
      if (_cutting) return;
      final x = _lastFocal?.dx ?? _viewport.width / 2;
      final side = _viewport.width * 0.3;
      if (x < side) {
        _nudgeRoll(counterclockwise: false);
        return;
      }
      if (x > _viewport.width - side) {
        _nudgeRoll(counterclockwise: true);
        return;
      }
    }
    final world = _aimWorld();
    if (world == null) return;
    if (_tool == _GridTool.scissors) {
      _onScissorTap(world);
    } else {
      _onStraightTap(world);
    }
  }

  Offset? _aimWorld() {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.planePoint(
      Offset(_viewport.width / 2, _viewport.height / 2),
      _viewport,
    );
  }

  (Offset, Offset)? _scissorGhost(Offset? aim) {
    if (_tool != _GridTool.scissors) return null;
    final from = _march?.position ?? (aim == null ? null : _nearestEdge(aim));
    if (from == null) return null;
    final end = nextOutlineHit(
      from: from,
      direction: _screenUp(),
      closed: cutOutlines(_step, _sheet),
      open: _sheet.cutStrokes,
    );
    if (end == null) return null;
    return (from, end);
  }

  (Offset, Offset)? _displayGhost(Offset? aim) {
    if (_editing) return null;
    final ghost = _scissorGhost(aim);
    if (ghost == null) return null;
    if (_flight.phase != ToolFlightPhase.cut) return ghost;
    return (_toModel(_flight.pose(_flightAnim.value).tip), ghost.$2);
  }

  void _syncFlight() {
    final march = _march;
    _flight.presented = march == null || march.path.length <= 1;
    if (!mounted || _viewport.width < 2) return;
    if (_flight.phase == ToolFlightPhase.cut) return;
    final next = _splitAnim.isAnimating ? null : _cue();
    final duration = _flight.offer(
      next,
      t: _flightAnim.value,
      approach: _approachFor(next),
      follow: _turnAnim.isAnimating,
    );
    if (duration != null) _playFlight(duration);
  }

  ToolCue? _cue() {
    if (_editing || _tool != _GridTool.scissors) return null;
    final aim = _aimWorld();
    if (aim == null) return null;
    final ghost = _scissorGhost(aim);
    if (ghost == null) return null;
    final anchor = _shown(ghost.$1);
    final end = _shown(ghost.$2);
    final delta = end - anchor;
    if (delta.distance < 1e-6) return null;
    return ToolCue(
      anchor: anchor,
      direction: delta / delta.distance,
      aim: aim,
      reach: _step.gridSpacing * 0.75,
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
    void start() {
      if (!mounted) return;
      _flightAnim.duration = duration;
      _flightAnim.forward(from: 0);
    }

    final phase = WidgetsBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => start());
      return;
    }
    start();
  }

  void _onFlightStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final phase = _flight.phase;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _flight.phase != phase) return;
      switch (_flight.phase) {
        case ToolFlightPhase.cut:
          final split = _commitMarch();
          final cue = _cue();
          if (split == true || cue == null) {
            _playFlight(_flight.depart(1, _approachFor(null)));
            return;
          }
          _flight.seat(cue);
          _syncFlight();
        case ToolFlightPhase.arrive:
        case ToolFlightPhase.relocate:
          _flight.land();
          _syncFlight();
        case ToolFlightPhase.leave:
          _flight.land();
          _syncFlight();
        case ToolFlightPhase.hold:
        case ToolFlightPhase.absent:
          break;
      }
    });
  }

  void _onSplitStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _syncFlight();
  }

  int? _polygonIndex(Offset aim) {
    final world = _toModel(aim);
    for (var i = 0; i < _step.polygons.length; i++) {
      if (isInsidePolygon(world, _step.polygons[i])) return i;
    }
    return null;
  }

  Set<(int, int)> _stampGhost(Offset? aim) {
    if (aim == null || _polygonIndex(aim) != null) return const {};
    final world = _toModel(aim);
    final spacing = _step.gridSpacing;
    final cell = ((world.dx / spacing).floor(), (world.dy / spacing).floor());
    return switch (_stamp) {
      _Stamp.paint => {cell},
      _Stamp.circle => circleCells(cell.$1, cell.$2, 1),
      _Stamp.rectangle => rectangleCells(cell.$1, cell.$2, cell.$1 + 1, cell.$2 + 1),
    };
  }

  Widget _topBar() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 76),
              child: _header(),
            ),
            Row(
              children: [
                _turnButton(clockwise: true),
                const Spacer(),
                _compassButton(),
                const Spacer(),
                _turnButton(clockwise: false),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _dropdown<String>(
          keyName: 'grid-level-dropdown',
          value: _blueprint.id,
          items: {for (final level in _levels) level.id: level.name},
          onChanged: (id) {
            final level = _levels.where((item) => item.id == id).firstOrNull;
            if (level == null) return;
            setState(() => _loadStep(0, level));
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            TextButton(onPressed: _locked ? null : _toggleEdit, child: Text(_editing ? 'Play' : 'Edit')),
            TextButton(onPressed: _clear, child: const Text('Clear')),
            TextButton(onPressed: _save, child: const Text('Save')),
            if (_editing && _selected.length >= 2)
              TextButton(onPressed: _merge, child: const Text('Merge')),
          ],
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_editing)
          HudToolCarousel<_Stamp>(
            items: const [
              HudCarouselItem(
                value: _Stamp.paint,
                icon: Icons.brush,
                label: 'Paint',
                fill: Color(0xFF1A1A1A),
              ),
              HudCarouselItem(
                value: _Stamp.rectangle,
                icon: Icons.crop_square,
                label: 'Rectangle',
                fill: Color(0xFF1A1A1A),
              ),
              HudCarouselItem(
                value: _Stamp.circle,
                icon: Icons.circle_outlined,
                label: 'Circle',
                fill: Color(0xFF1A1A1A),
              ),
            ],
            selected: _stamp,
            onSelect: (stamp) => setState(() {
              _stamp = stamp;
              _painted = {};
              _stampAnchor = null;
            }),
          )
        else ...[
          if (_tool == _GridTool.straightEdge)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextButton(
                  onPressed: () => setState(() => _fold = false),
                  child: Text('Cut', style: TextStyle(color: _fold ? Colors.white54 : Colors.white)),
                ),
                TextButton(
                  onPressed: () => setState(() => _fold = true),
                  child: Text('Fold', style: TextStyle(color: _fold ? Colors.white : Colors.white54)),
                ),
              ],
            ),
          HudToolCarousel<_GridTool>(
            items: const [
              HudCarouselItem(
                value: _GridTool.scissors,
                icon: Icons.content_cut,
                label: 'Scissors',
                fill: Color(0xFF1A1A1A),
              ),
              HudCarouselItem(
                value: _GridTool.straightEdge,
                icon: Icons.straighten,
                label: 'Straight edge',
                fill: Color(0xFF1A1A1A),
              ),
            ],
            selected: _tool,
            onSelect: (tool) {
              setState(() => _tool = tool);
              _syncFlight();
            },
          ),
        ],
      ],
    );
  }

  Widget _undoButton() {
    final enabled = !_locked && _undo.isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: IconButton(
        tooltip: 'Undo',
        onPressed: enabled ? _undoLast : null,
        icon: Icon(Icons.undo, color: enabled ? Colors.white : Colors.white24),
      ),
    );
  }

  Widget _turnButton({required bool clockwise}) {
    return IconButton(
      tooltip: clockwise ? 'Rotate clockwise' : 'Rotate counterclockwise',
      onPressed: _turnAnim.isAnimating || _splitAnim.isAnimating
          ? null
          : () => _rotatePiece(clockwise),
      icon: Icon(
        clockwise ? Icons.rotate_right : Icons.rotate_left,
        color: Colors.white,
      ),
    );
  }

  Widget _compassButton() {
    return IconButton(
      key: const Key('grid-compass'),
      tooltip: 'Free rotate',
      onPressed: () => setState(() => _rolling = !_rolling),
      icon: Icon(
        Icons.explore,
        color: _rolling ? const Color(0xFFFFD54F) : Colors.white,
      ),
    );
  }

  Widget _dropdown<T>({
    required String keyName,
    required T value,
    required Map<T, String> items,
    required ValueChanged<T> onChanged,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            key: Key(keyName),
            isDense: true,
            dropdownColor: const Color(0xFF1A1A1A),
            value: items.containsKey(value) ? value : items.keys.first,
            items: [
              for (final entry in items.entries)
                DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value, style: const TextStyle(color: Colors.white70)),
                ),
            ],
            onChanged: (next) {
              if (next != null) onChanged(next);
            },
          ),
        ),
      ),
    );
  }
}
