import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gridcraft/blueprint.dart';
import '../gridcraft/edit.dart';
import '../gridcraft/fold.dart';
import '../gridcraft/level_io.dart';
import '../gridcraft/painter.dart';
import '../gridcraft/piece_quadtree.dart';
import '../gridcraft/rules.dart';
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
import '../ui/game/dev_tools_button.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';

enum _GridTool { select, scissors, folder, holePunch }

/// Screen side of a tap, measured from the crosshair. Up is toward the top.
enum _CutSide { up, down, left, right }

/// Taps inside the crosshair disc keep going forward. Anything past it uses
/// the larger axis of the offset, so a click beside the crosshair is left
/// or right rather than another forward cut.
const double _kCrosshairCutRadius = 28;

const Duration _kTurnDuration = Duration(milliseconds: 600);
const Duration _kSplitDuration = Duration(milliseconds: 750);
const Duration _kFocusDuration = Duration(milliseconds: 320);

/// Plays one level of a blueprint. Authoring lives in the puzzle editor.
class GridPuzzleView extends StatefulWidget {
  const GridPuzzleView({
    super.key,
    this.store,
    this.initial,
    this.returnToEditor = false,
  });

  final LevelStore? store;

  /// Blueprint opened from the puzzle editor. Unsaved edits win over a file.
  final GridBlueprint? initial;

  /// Back returns to the editor instead of the dev menu.
  final bool returnToEditor;

  @override
  State<GridPuzzleView> createState() => _GridPuzzleViewState();
}

class _GridPuzzleViewState extends State<GridPuzzleView>
    with TickerProviderStateMixin {
  final LevelStore _store = LevelStore();
  late PapercutCamera _camera;
  late AnimationController _flash;
  late AnimationController _failAnim;
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
  Offset? _modelEnd;
  double? _cutRoll;
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
  late GridBlueprint _blueprint;
  GridStep _baseline = twinLsBlueprint().steps.first;
  int _stepIndex = 0;
  late PapercutSheet _sheet;
  ScissorMarch? _march;
  PapercutSheet? _marchBase;
  String? _bladePieceId;
  final List<PapercutSheet> _undo = [];
  final List<CutProgress> _undoProgress = [];
  CutProgress _progress = const CutProgress();

  /// Screen sides tapped while a stroke is still traveling. Null is forward.
  final List<_CutSide?> _cutQueue = [];

  _GridTool _tool = _GridTool.scissors;
  double _startRoll = 0;
  int _folderUses = 0;
  int _punchUses = 0;
  PunchShape _punchShape = PunchShape.circle;
  double _punchSize = 1;
  List<int?> _collisionLeft = const [];
  Set<int> _touching = {};
  (Offset, Offset)? _foldLine;
  int? _picked;
  int? _dragPiece;
  bool _dragNudged = false;
  Offset? _dragSample;
  Offset? _dragFree;
  double? _rulerX;
  bool _rolling = false;
  Offset? _strokeDirection;
  bool _needsFrame = true;
  double _rollStart = 0;
  double _moved = 0;
  double _gestureScale = 1;
  bool _zoomed = false;
  bool _showTapDebug = false;
  Offset? _debugTap;
  String _debugSide = '';
  Size _viewport = Size.zero;

  LevelStore get _levelsStore => widget.store ?? _store;

  GridStep get _step => _blueprint.steps[_stepIndex];

  bool get _locked => _march?.locked ?? false;

  @override
  void initState() {
    super.initState();
    _camera = PapercutCamera()..addListener(_onCamera);
    _blueprint = widget.initial ?? twinLsBlueprint();
    _levels = _seedLevels(_blueprint);
    _flash = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    )..repeat(reverse: true);
    _failAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..addStatusListener(_onFailStatus);
    _turnAnim = AnimationController(vsync: this, duration: _kTurnDuration)
      ..addListener(_onTurnTick)
      ..addStatusListener(_onTurnStatus);
    _splitAnim = AnimationController(vsync: this, duration: _kSplitDuration)
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
    _failAnim.dispose();
    _flash.dispose();
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    _syncFlight();
    if (mounted) setState(() {});
  }

  List<GridBlueprint> _seedLevels(GridBlueprint blueprint) {
    if (blueprint.id == 'twin-ls') return [blueprint];
    return [blueprint, twinLsBlueprint()];
  }

  Future<void> _refreshLevels() async {
    final saved = await _levelsStore.loadAll();
    if (!mounted) return;
    final initial = widget.initial;
    final levels = <GridBlueprint>[
      twinLsBlueprint(),
      ...saved.where((level) => level.id != 'twin-ls'),
    ];
    if (initial != null) {
      final merged = [
        for (final level in levels)
          if (level.id == initial.id) initial else level,
      ];
      if (!merged.any((level) => level.id == initial.id)) {
        merged.insert(0, initial);
      }
      setState(() => _levels = merged);
      return;
    }
    setState(() {
      _levels = levels;
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
    _modelEnd = null;
    _cutRoll = null;
    _flight.reset();
    _strokeDirection = null;
    _turnFromStep = null;
    _blueprint = blueprint;
    _stepIndex = index.clamp(0, blueprint.steps.length - 1);
    _baseline = _step;
    _sheet = _freshSheet(_step);
    _march = null;
    _marchBase = null;
    _bladePieceId = null;
    _undo.clear();
    _undoProgress.clear();
    _progress = const CutProgress();
    _cutQueue.clear();
    _startRoll = _camera.roll;
    _folderUses = 0;
    _punchUses = 0;
    _collisionLeft = [
      for (var i = 0; i < _step.polygons.length; i++) _step.collisionOf(i),
    ];
    _touching = {};
    _foldLine = null;
    if (_step.tools != null &&
        _tool == _GridTool.scissors &&
        !_step.tools!.allows(CraftTool.scissors)) {
      _tool = _GridTool.select;
    }
    _picked = null;
    _dragPiece = null;
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

  Offset _snapOffset(Offset value) {
    final spacing = _step.gridSpacing;
    if (spacing <= 1e-9) return value;
    return Offset(_snap(value.dx, spacing), _snap(value.dy, spacing));
  }

  /// Drops a scissor march, a cut in flight, and anything queued behind it.
  void _abandonOtherTools() {
    if (_focusAnim.isAnimating) _focusAnim.stop();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    if (_rollNudge.isAnimating && _cutRoll != null) _rollNudge.stop();
    _armingCut = false;
    _armedFrom = null;
    _armedTo = null;
    _modelEnd = null;
    _cutRoll = null;
    _strokeDirection = null;
    _cutQueue.clear();
    _march = null;
    _marchBase = null;
    _bladePieceId = null;
    _flight.reset();
  }

  bool get _gemsRemain => gemsRemain(_step.rules, _progress);

  /// Nearest gem the blade may still enter through.
  Offset? _openGemNear(Offset world) {
    final rules = _step.rules;
    final reach = _step.gridSpacing * 1.5;
    Offset? best;
    var bestDistance = reach;
    void consider(Offset point) {
      final distance = (point - world).distance;
      if (distance >= bestDistance) return;
      bestDistance = distance;
      best = point;
    }

    for (var i = 0; i < rules.colors.length; i++) {
      if (_progress.collectedColors.contains(i)) continue;
      consider(rules.colors[i].point);
    }
    for (final mark in rules.numbers) {
      if (mark.number < _progress.nextNumber) continue;
      consider(mark.point);
    }
    return best;
  }

  bool get _cutting => _flight.phase == ToolFlightPhase.cut || _armingCut;

  /// True after the first stroke, when side taps choose the next cut.
  bool get _directing {
    final march = _march;
    return march != null && march.path.length > 1;
  }

  void _onScissorTap(Offset world) {
    if (_cutting || _failing) return;
    if (_march == null) {
      if (_gemsRemain) {
        final gem = _openGemNear(world);
        if (gem == null) return;
        final edge = _nearestEdge(gem);
        setState(() {
          _marchBase = _sheet;
          _march = placeAtEntry(gem, _step.paper);
          _bladePieceId = edge == null
              ? (_sheet.pieces.isEmpty ? null : _sheet.pieces.first.id)
              : _sheet.pieces[edge.index].id;
        });
      } else {
        final edge = _nearestEdge(world);
        if (edge == null) return;
        final placed = _placeOn(edge);
        if (placed == null) return;
        setState(() {
          _marchBase = _sheet;
          _march = placed;
          _bladePieceId = _sheet.pieces[edge.index].id;
        });
      }
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
    _beginStroke(ghost.$1, ghost.$2);
  }

  bool _beginStroke(Offset modelFrom, Offset modelTo) {
    if (!_liveRules.allows(
      modelFrom,
      modelTo,
      _progress,
      paper: _step.paper,
    )) {
      return false;
    }
    final from = _shown(modelFrom);
    final to = _shown(modelTo);
    final delta = to - from;
    if (delta.distance < 1e-6) return false;
    _strokeDirection = delta / delta.distance;
    _modelEnd = modelTo;
    _armedFrom = from;
    _armedTo = to;
    _cutRoll = PapercutCamera.rollForScreenUp(
      modelTo - modelFrom,
      near: _rollNudge.isAnimating ? _rollTo : _camera.roll,
    );
    _armingCut = true;
    _animateFocus(from);
    return true;
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
    final target = _cutRoll;
    _cutRoll = null;
    final turning = target != null && (target - _camera.roll).abs() > 1e-3;
    _flight.beginCut(
      from: from,
      to: to,
      direction: direction,
      t: _flightAnim.value,
      present: (_march?.path.length ?? 1) <= 1,
    );
    _playFlight(kCutDuration);
    if (turning) _animateRollTo(target);
  }

  Offset _screenUp() =>
      rotateGridPointBy(const Offset(0, 1), Offset.zero, -_camera.roll);

  Offset? _lightOrigin() {
    final pose = _flight.pose(_flightAnim.value);
    if (pose.visible > 0.2) return pose.tip;
    return _aimWorld();
  }

  Offset _lightDirection() {
    final pose = _flight.pose(_flightAnim.value);
    if (pose.visible > 0.2 && pose.direction.distance > 1e-6) {
      return pose.direction;
    }
    final march = _march?.direction;
    if (march != null && march.distance > 1e-6) return march;
    return _screenUp();
  }

  PapercutPiece? _bladePiece() {
    final id = _bladePieceId;
    if (id == null) return null;
    for (final piece in _sheet.pieces) {
      if (piece.id == id) return piece;
    }
    return null;
  }

  Offset _shown(Offset model) {
    final blade = _bladePiece();
    if (blade != null) return model + blade.separation;
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

  PieceEdgeTarget? _nearestEdge(Offset aim) => closestPieceEdge(
    aim: aim,
    pieces: _sheet.pieces,
    spacing: _step.gridSpacing,
  );

  /// Outlines of the piece being cut, plus the blueprint. Sibling pieces stay
  /// out of the ray: in model space they still cover the area that was cut out.
  List<List<Offset>> _bladeOutlines(PapercutPiece? piece) {
    if (piece == null) return cutOutlines(_step, _sheet);
    return [
      for (var i = 0; i < _step.polygons.length; i++)
        if (_step.isRingClosed(i)) _step.polygons[i],
      piece.vertices,
      ...piece.holes,
    ];
  }

  ScissorMarch? _placeOn(PieceEdgeTarget edge) {
    final piece = _sheet.pieces[edge.index];
    final onPiece = placeOnRing(edge.model, piece.vertices);
    if (onPiece != null) return onPiece;
    for (final hole in piece.holes) {
      final onHole = placeOnRing(edge.model, hole);
      if (onHole != null) return onHole;
    }
    return placeScissor(edge.model, _step.paper);
  }

  /// Maps a point on the drawn paper back to grid space.
  Offset _toModel(Offset aim) {
    for (final piece in _sheet.pieces) {
      if (piece.separation == Offset.zero) continue;
      final shown = [
        for (final vertex in piece.vertices) vertex + piece.separation,
      ];
      if (ownsPoint(shown, aim)) return aim - piece.separation;
    }
    return aim;
  }

  GridRules get _liveRules {
    final cap = _step.scissorLengthBudget;
    if (cap == _step.rules.maxLength) return _step.rules;
    if (cap == null) return _step.rules.copyWith(clearLength: true);
    return _step.rules.copyWith(maxLength: cap);
  }

  bool _skipPenciled(Offset a, Offset b) {
    return penciledRidesPennedNeighbor(
      _step.polygons,
      _step.edgeStyles,
      a,
      b,
      closed: _step.ringClosed,
    );
  }

  bool _canSpend(CraftTool tool, num used) {
    final filter = _step.tools;
    if (filter == null) return true;
    if (!filter.allows(tool)) return false;
    final cap = filter.budget(tool);
    if (cap == null) return true;
    return used + 1 <= cap + 1e-6;
  }

  bool _failed = false;
  bool _failing = false;
  FailureCue? _failureCue;

  void _failLevel(FailureCue cue) {
    if (_failing) return;
    _failing = true;
    _failed = true;
    setState(() => _failureCue = cue);
    _failAnim.forward(from: 0);
  }

  void _onFailStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    _commitFailure();
  }

  void _commitFailure() {
    final origin = _baseline;
    final steps = [..._blueprint.steps];
    steps[_stepIndex] = origin;
    _turnAnim.stop();
    _splitAnim.stop();
    if (_flightAnim.isAnimating) _flightAnim.stop();
    if (_focusAnim.isAnimating) _focusAnim.stop();
    _flight.reset();
    _camera.setRoll(_startRoll);
    setState(() {
      _blueprint = _blueprint.copyWith(steps: steps);
      _sheet = _freshSheet(origin);
      _march = null;
      _marchBase = null;
      _bladePieceId = null;
      _undo.clear();
      _undoProgress.clear();
      _progress = const CutProgress();
      _cutQueue.clear();
      _folderUses = 0;
      _punchUses = 0;
      _collisionLeft = [
        for (var i = 0; i < origin.polygons.length; i++) origin.collisionOf(i),
      ];
      _touching = {};
      _foldLine = null;
      _strokeDirection = null;
      _modelEnd = null;
      _picked = null;
      _dragPiece = null;
      _failureCue = null;
      _failing = false;
      _failed = false;
    });
    _armingCut = false;
    _syncFlight();
  }

  void _noteTouch(Offset a, Offset b) {
    final now = piecesTouched(
      _step.polygons,
      a,
      b,
      closed: _step.ringClosed,
    ).toSet();
    final released = _touching.difference(now);
    _touching = now;
    for (final index in released) {
      if (_spendTouch(index)) return;
    }
  }

  void _releaseTouches() {
    final released = Set<int>.of(_touching);
    _touching = {};
    for (final index in released) {
      if (_spendTouch(index)) return;
    }
  }

  bool _spendTouch(int index) {
    if (index < 0 || index >= _collisionLeft.length) return false;
    final left = _collisionLeft[index];
    if (left == null) return false;
    final next = left - 1;
    _collisionLeft[index] = next;
    if (next <= 0 && !blueprintPieceCutOut(_step.polygons[index], _sheet)) {
      _failLevel(FailureCue(FailureKind.piece, index));
      return true;
    }
    return false;
  }

  /// Cutting a hits piece free while its count is still positive fails the level.
  bool _failIfRemovedEarly() {
    if (_failed) return true;
    for (var i = 0; i < _step.polygons.length; i++) {
      if (!_step.isRingClosed(i)) continue;
      final left = i < _collisionLeft.length ? _collisionLeft[i] : null;
      if (!paperRemovedEarly(
        left,
        cutOut: blueprintPieceCutOut(_step.polygons[i], _sheet),
      )) {
        continue;
      }
      _failLevel(FailureCue(FailureKind.piece, i));
      return true;
    }
    return false;
  }

  PapercutSheet _withMirrors(PapercutSheet sheet, List<Offset> path) {
    final perm = _step.permutation;
    if (!perm.mirrorX && !perm.mirrorY) return sheet;
    var current = sheet;
    for (final image in mirroredPolylines(
      path,
      _step.paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final next = cutThroughFolds(
        current,
        image,
        thickCut: _step.attachment.thickCut,
        blueprintPieces: _step.closedPolygons,
      );
      if (next != null) current = next;
    }
    return current;
  }

  FailureCue? _mirrorCause(Offset from, Offset to) {
    final perm = _step.permutation;
    if (!perm.mirrorX && !perm.mirrorY) return null;
    for (final image in mirroredPolylines(
      [from, to],
      _step.paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final ruling = _liveRules.consider(
        image.first,
        image.last,
        _progress,
        paper: _step.paper,
      );
      if (ruling.failed) return ruling.cause;
    }
    return null;
  }

  bool _mirrorsBlocked(Offset from, Offset to) {
    final perm = _step.permutation;
    if (!perm.mirrorX && !perm.mirrorY) return false;
    for (final image in mirroredPolylines(
      [from, to],
      _step.paper.center,
      mirrorX: perm.mirrorX,
      mirrorY: perm.mirrorY,
    )) {
      final ruling = _liveRules.consider(
        image.first,
        image.last,
        _progress,
        paper: _step.paper,
      );
      if (!ruling.allowed && !ruling.failed) return true;
    }
    return false;
  }

  /// True when the cut split a piece off. Null when the cut did not apply.
  bool? _commitMarch() {
    if (_failing) return null;
    final march = _march;
    final base = _marchBase;
    if (march == null || base == null) return null;
    _failed = false;
    final direction = _strokeDirection ?? _screenUp();
    final end = march.previewEnd(
      _step,
      base,
      direction: direction,
      closed: _bladeOutlines(_bladePiece()),
      skipCollinear: _skipPenciled,
    );
    if (end == null ||
        cutRidesBoundary(march.position, end, _paperEdges(_bladePiece()))) {
      return null;
    }
    final ruling = _liveRules.consider(
      march.position,
      end,
      _progress,
      paper: _step.paper,
    );
    if (!ruling.allowed) return null;
    if (ruling.failed) {
      _failLevel(
        ruling.cause ?? const FailureCue(FailureKind.color, 0),
      );
      return null;
    }
    final mirror = _mirrorCause(march.position, end);
    if (mirror != null) {
      _failLevel(mirror);
      return null;
    }
    if (_mirrorsBlocked(march.position, end)) return null;
    final commit = commitScissor(
      march: march,
      step: _step,
      base: base,
      direction: direction,
      closed: _bladeOutlines(_bladePiece()),
    );
    _strokeDirection = null;
    _modelEnd = null;
    _cutRoll = null;
    if (commit == null) return null;
    final mirrored = _withMirrors(commit.sheet, [...march.path, end]);
    _pushUndo();
    _progress = ruling.progress;
    final split = commit.march == null;
    final spread = split
        ? spreadPieces(base, mirrored, _step.gridSpacing)
        : mirrored;
    setState(() {
      _sheet = split ? mirrored : spread;
      _march = commit.march;
      if (split) {
        _marchBase = null;
        _bladePieceId = null;
      }
    });
    _noteTouch(march.position, end);
    if (_failed || _failIfRemovedEarly()) return null;
    if (!split) {
      _pinScissor();
      return false;
    }
    _releaseTouches();
    if (_failed || _failIfRemovedEarly()) return null;
    _splitFrom = [for (final piece in mirrored.pieces) piece.separation];
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
      _sheet = _sheet.copyWith(
        pieces: [
          for (var i = 0; i < _sheet.pieces.length; i++)
            _sheet.pieces[i].copyWith(
              separation: Offset.lerp(_splitFrom[i], _splitTo[i], t)!,
            ),
        ],
      );
    });
  }

  void _onFolderTap(Offset aim) {
    if (_failing) return;
    final world = _toModel(aim);
    final opened = unfoldAt(_sheet, world);
    if (opened != null) {
      if (!_canSpend(CraftTool.folder, _folderUses)) return;
      _pushUndo();
      setState(() {
        _sheet = opened;
        _folderUses += 1;
        _foldLine = null;
      });
      return;
    }
    final span = creaseSpan(world, _screenUp(), _step.paper);
    if (span == null) return;
    setState(() => _foldLine = span);
  }

  void _onFolderSwipe(Offset screenDelta, Offset flapWorld) {
    if (_failing) return;
    final line = _foldLine;
    if (line == null || screenDelta.dy.abs() < 8) return;
    if (!_canSpend(CraftTool.folder, _folderUses)) return;
    final facing = screenDelta.dy < 0 ? FoldFacing.toward : FoldFacing.away;
    final next = foldSheet(
      sheet: _sheet,
      spanA: line.$1,
      spanB: line.$2,
      flapPoint: flapWorld,
      facing: facing,
      noFold: _step.permutation.noFold,
      blueprintPieces: _step.closedPolygons,
    );
    if (next == null) return;
    _pushUndo();
    setState(() {
      _sheet = next;
      _folderUses += 1;
      _foldLine = null;
    });
  }

  void _onPunch(Offset aim) {
    if (_failing) return;
    if (!_canSpend(CraftTool.holePunch, _punchUses)) return;
    final world = _toModel(aim);
    final outline = punchOutline(world, _punchShape, _punchSize);
    if (punchCrossesBlueprint(outline, _step.closedPolygons)) return;
    var next = subtractRegion(_sheet, outline);
    if (next == null) return;
    for (final joint in _sheet.folds) {
      if (joint.facing == FoldFacing.unfolded) continue;
      final mirrored = [
        for (final point in outline)
          reflectAcrossLine(point, joint.a, joint.b),
      ];
      next = subtractRegion(next!, mirrored) ?? next;
    }
    _pushUndo();
    setState(() {
      _sheet = next!;
      _punchUses += 1;
    });
    for (var i = 0; i < outline.length; i++) {
      _noteTouch(outline[i], outline[(i + 1) % outline.length]);
    }
    _releaseTouches();
    _failIfRemovedEarly();
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
        for (final point in march.path)
          rotateGridPointBy(point, origin, radians),
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
    _modelEnd = null;
    _cutRoll = null;
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
      _bladePieceId = null;
      _undo.clear();
      _undoProgress.clear();
      _progress = const CutProgress();
      _cutQueue.clear();
      _picked = null;
      _dragPiece = null;
    });
    _syncFlight();
  }

  Future<void> _save() async {
    await _levelsStore.save(_blueprint);
    await _refreshLevels();
  }

  void _pushUndo() {
    _undo.add(_sheet.clone());
    _undoProgress.add(_progress);
    if (_undo.length > 40) {
      _undo.removeAt(0);
      _undoProgress.removeAt(0);
    }
  }

  void _undoLast() {
    if (_locked || _undo.isEmpty) return;
    _splitAnim.stop();
    setState(() {
      _sheet = _undo.removeLast();
      if (_undoProgress.isNotEmpty) _progress = _undoProgress.removeLast();
      _march = null;
      _marchBase = null;
      _bladePieceId = null;
      _cutQueue.clear();
      if (_picked != null && _picked! >= _sheet.pieces.length) _picked = null;
    });
    _syncFlight();
  }

  Offset _screenCardinal(_CutSide side) {
    final screen = switch (side) {
      _CutSide.up => const Offset(0, 1),
      _CutSide.down => const Offset(0, -1),
      _CutSide.left => const Offset(-1, 0),
      _CutSide.right => const Offset(1, 0),
    };
    return rotateGridPointBy(screen, Offset.zero, -_camera.roll);
  }

  List<Offset> get _screenCardinals => [
    for (final side in _CutSide.values) _screenCardinal(side),
  ];

  Offset? _arrival() {
    final path = _march?.path;
    if (path == null || path.length < 2) return null;
    return path.last - path[path.length - 2];
  }

  List<ForwardCut> _forwardOptions() {
    final march = _march;
    final forward = _arrival();
    if (march == null || forward == null) return const [];
    final piece = _bladePiece();
    return forwardCuts(
      from: march.position,
      forward: forward,
      directions: _screenCardinals,
      closed: _bladeOutlines(piece),
      open: [...openBlueprint(_step), ..._sheet.cutStrokes],
      boundary: _paperEdges(piece),
      skipCollinear: _skipPenciled,
    );
  }

  /// The crosshair is the center of the screen. ViewCrosshair is centered
  /// on this same point.
  Offset get _crosshair => Offset(_viewport.width / 2, _viewport.height / 2);

  /// Larger offset from the crosshair. A tap above and left is up when the
  /// vertical component is greater, and left when the horizontal one is.
  _CutSide? _tapSide(Offset? local) {
    if (local == null || _viewport.width < 2 || _viewport.height < 2) {
      return null;
    }
    final side = dominantScreenSide(
      local - _crosshair,
      deadZone: _kCrosshairCutRadius,
    );
    return switch (side) {
      ScreenSide.up => _CutSide.up,
      ScreenSide.down => _CutSide.down,
      ScreenSide.left => _CutSide.left,
      ScreenSide.right => _CutSide.right,
      null => null,
    };
  }

  void _noteTap(Offset? local) {
    if (!_showTapDebug || local == null || _viewport.width < 2) return;
    final side = _tapSide(local);
    setState(() {
      _debugTap = local;
      _debugSide = side?.name ?? 'forward';
    });
  }

  void _chooseCut(Offset? local) {
    if (_cutting) {
      _enqueueCut(_tapSide(local));
      return;
    }
    if (!_directing) return;
    _performCut(_tapSide(local));
  }

  void _enqueueCut(_CutSide? side) {
    _cutQueue.add(side);
    if (!_showTapDebug) return;
    setState(() {
      _debugSide = '${side?.name ?? 'forward'}  queued ${_cutQueue.length}';
    });
  }

  /// Starts the next stored tap once the blade is free. A side with no legal
  /// cut is dropped so a later tap can still run.
  bool _takeQueuedCut() {
    while (_cutQueue.isNotEmpty) {
      if (_performCut(_cutQueue.removeAt(0))) return true;
    }
    return false;
  }

  /// True when a stroke actually starts. Null continues the arrival direction.
  bool _performCut(_CutSide? side) {
    if (!_directing) return false;
    final from = _march?.position;
    if (from == null) return false;
    final ForwardCut? cut;
    if (side == null) {
      final forward = _arrival();
      if (forward == null) return false;
      cut = mostForwardCut(_forwardOptions(), forward);
    } else {
      cut = cutFacing(_forwardOptions(), _screenCardinal(side));
    }
    if (cut == null) return false;
    return _beginStroke(from, cut.end);
  }

  void _cutCardinal(_CutSide side) {
    if (_cutting) {
      _enqueueCut(side);
      return;
    }
    _performCut(side);
  }

  /// Side taps and arrow keys. Right is counterclockwise.
  void _nudgeRoll({required bool counterclockwise}) {
    if (_tool != _GridTool.scissors) return;
    if (_cutting) return;
    _animateQuarter(counterclockwise);
  }

  /// Lands on the next 0/90/180/270. An in-between angle does not add a full
  /// extra quarter on top of itself.
  void _animateQuarter(bool counterclockwise) {
    final base = _rollNudge.isAnimating ? _rollTo : _camera.roll;
    _animateRollTo(
      PapercutCamera.nextQuarterTurn(base, counterclockwise: counterclockwise),
    );
  }

  /// Turns the sheet so [target] is the roll. Independent of the cut's
  /// world direction: the stroke already knows where it is going.
  void _animateRollTo(double target) {
    _rollFrom = _camera.roll;
    _rollTo = target;
    if ((_rollTo - _rollFrom).abs() < 1e-3) return;
    _rollNudge.forward(from: 0);
  }

  void _onRollNudge() {
    final t = Curves.easeOutCubic.transform(_rollNudge.value);
    _camera.setRoll(_rollFrom + (_rollTo - _rollFrom) * t);
    if (_cutting) return;
    _pinScissor();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (_directing && _tool == _GridTool.scissors) {
      final side = switch (event.logicalKey) {
        LogicalKeyboardKey.arrowUp => _CutSide.up,
        LogicalKeyboardKey.arrowDown => _CutSide.down,
        LogicalKeyboardKey.arrowLeft => _CutSide.left,
        LogicalKeyboardKey.arrowRight => _CutSide.right,
        _ => null,
      };
      if (side != null) {
        if (_cutting && event is KeyRepeatEvent) return KeyEventResult.handled;
        _cutCardinal(side);
        return KeyEventResult.handled;
      }
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
        overlays: [
          FmDevBackButton(
            label: widget.returnToEditor ? '← Editor' : '← Dev',
            onPressed: widget.returnToEditor ? () => context.pop() : null,
          ),
        ],
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
                      if (event is! PointerScrollEvent ||
                          event.scrollDelta.dy == 0) {
                        return;
                      }
                      _camera.zoomByScale(
                        math.exp(-event.scrollDelta.dy * 0.002),
                      );
                    },
                    child: GestureDetector(
                      key: const Key('grid-puzzle-canvas'),
                      behavior: HitTestBehavior.opaque,
                      onScaleStart: _onScaleStart,
                      onScaleUpdate: _onScaleUpdate,
                      onScaleEnd: _onScaleEnd,
                      child: AnimatedBuilder(
                        animation: Listenable.merge([
                          _flash,
                          _failAnim,
                          _flightAnim,
                        ]),
                        builder: (context, _) {
                          final aim = _aimWorld();
                          final ghosts = _ruledGhosts(_displayGhosts(aim));
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
                              showRuler: false,
                              selected: const {},
                              pickedPiece: _tool == _GridTool.select
                                  ? (_dragPiece ?? _picked)
                                  : null,
                              ghostCuts: ghosts.$1,
                              blockedCuts: ghosts.$2,
                              ghostSeparation: _ghostShift(aim),
                              gatheredColors: _progress.collectedColors,
                              nextNumber: _progress.nextNumber,
                              failure: _failureCue,
                              failureFlash: _failAnim.value,
                              darkness: _step.permutation.darkness,
                              lightOrigin: _tool == _GridTool.scissors
                                  ? _lightOrigin()
                                  : null,
                              lightDirection: _tool == _GridTool.scissors
                                  ? _lightDirection()
                                  : null,
                              lightThrow: _step.attachment.flashlightThrow,
                              foldLine: _foldLine,
                              collisionLeft: _collisionLeft,
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
                if (_showTapDebug)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _TapDebugPainter(
                          centroid: _crosshair,
                          tap: _debugTap,
                          side: _debugSide,
                          deadZone: _kCrosshairCutRadius,
                        ),
                      ),
                    ),
                  ),
                FmSafePositioned(top: 8, left: 8, right: 8, child: _topBar()),
                FmSafePositioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: _toolbar(),
                ),
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
    _dragNudged = false;
    _dragSample = details.localFocalPoint;
    _dragFree = null;
    _dragPiece = null;
    if (_tool != _GridTool.select || _cutting || _locked) return;
    final world = _camera.planePoint(details.localFocalPoint, _viewport);
    if (world == null) return;
    final index = closestPieceIndex(
      point: world,
      pieces: _sheet.pieces,
      unit: _step.gridSpacing,
    );
    if (index == null) return;
    _dragPiece = index;
    setState(() => _picked = index);
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
    if (_dragPiece != null) {
      _dragSelected(local);
      return;
    }
    if (_march != null && _tool == _GridTool.scissors) return;
    _camera.panByScreen(delta, _viewport);
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_failing) return;
    final dragPiece = _dragPiece;
    final nudged = _dragNudged;
    _dragPiece = null;
    _dragNudged = false;
    _dragFree = null;
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
    if (_tool == _GridTool.folder && _foldLine != null && _moved > 18) {
      final start = _dragSample;
      final end = _lastFocal;
      if (start != null && end != null) {
        final world = _camera.planePoint(start, _viewport);
        if (world != null) _onFolderSwipe(end - start, _toModel(world));
      }
      return;
    }
    if (_moved > 12) return;
    if (_tool == _GridTool.select) {
      if (!nudged) setState(() => _picked = dragPiece);
      return;
    }
    if (_tool == _GridTool.scissors) {
      _noteTap(_lastFocal);
      if (_cutting) {
        _enqueueCut(_tapSide(_lastFocal));
        return;
      }
      final side = _tapSide(_lastFocal);
      if (_directing) {
        _chooseCut(_lastFocal);
        return;
      }
      if (side == _CutSide.left) {
        _nudgeRoll(counterclockwise: false);
        return;
      }
      if (side == _CutSide.right) {
        _nudgeRoll(counterclockwise: true);
        return;
      }
    }
    final world = _aimWorld();
    if (world == null) return;
    if (_tool == _GridTool.scissors) {
      _onScissorTap(world);
    } else if (_tool == _GridTool.folder) {
      _onFolderTap(world);
    } else if (_tool == _GridTool.holePunch) {
      _onPunch(world);
    }
  }

  void _dragSelected(Offset screen) {
    final index = _dragPiece;
    final from = _dragSample;
    if (index == null || from == null || index >= _sheet.pieces.length) return;
    if (!_dragNudged) {
      if (_moved < 12) return;
      _pushUndo();
      _dragNudged = true;
      _dragFree = _sheet.pieces[index].separation;
    }
    final start = _camera.planePoint(from, _viewport);
    final end = _camera.planePoint(screen, _viewport);
    _dragSample = screen;
    if (start == null || end == null) return;
    final world = end - start;
    if (world == Offset.zero) return;
    final free = (_dragFree ?? _sheet.pieces[index].separation) + world;
    _dragFree = free;
    final snapped = _snapOffset(free);
    final pieces = [..._sheet.pieces];
    final piece = pieces[index];
    if (snapped == piece.separation) return;
    pieces[index] = piece.copyWith(separation: snapped);
    setState(() {
      _sheet = _sheet.copyWith(pieces: pieces);
    });
  }

  Offset? _aimWorld() {
    if (_viewport.width < 2 || _viewport.height < 2) return null;
    return _camera.planePoint(
      Offset(_viewport.width / 2, _viewport.height / 2),
      _viewport,
    );
  }

  (Offset, Offset)? _cueSegment(Offset? aim) {
    if (_directing) {
      final from = _march?.position;
      final forward = _arrival();
      if (from == null || forward == null) return null;
      final cut = mostForwardCut(_forwardOptions(), forward);
      if (cut == null) return null;
      return (from, cut.end);
    }
    return _scissorGhost(aim);
  }

  PapercutPiece? _targetPiece(Offset? aim) {
    final blade = _bladePiece();
    if (blade != null) return blade;
    if (aim == null) return null;
    final edge = _nearestEdge(aim);
    if (edge == null) return null;
    return _sheet.pieces[edge.index];
  }

  Offset? _ghostShift(Offset? aim) => _targetPiece(aim)?.separation;

  (Offset, Offset)? _scissorGhost(Offset? aim) {
    if (_tool != _GridTool.scissors || _failing) return null;
    final edge = _march != null || aim == null || _gemsRemain
        ? null
        : _nearestEdge(aim);
    final gem = _march == null && aim != null && _gemsRemain
        ? _openGemNear(aim)
        : null;
    final from = _march?.position ?? gem ?? edge?.model;
    if (from == null) return null;
    final piece =
        _bladePiece() ?? (edge == null ? null : _sheet.pieces[edge.index]);
    final rings = _paperEdges(piece);
    final outlines = _bladeOutlines(piece);
    final aimed = nextOutlineHit(
      from: from,
      direction: _screenUp(),
      closed: outlines,
      open: [...openBlueprint(_step), ..._sheet.cutStrokes],
      skipCollinear: _skipPenciled,
    );
    if (aimed != null && !cutRidesBoundary(from, aimed, rings)) {
      return (from, aimed);
    }
    if (aimed == null || !cutRidesBoundary(from, aimed, rings)) return null;
    final inward = piece == null
        ? null
        : inwardOnRing(from, piece.vertices) ??
              _inwardOnHoles(from, piece.holes);
    if (inward == null) return null;
    final end = nextOutlineHit(
      from: from,
      direction: inward,
      closed: outlines,
      open: [...openBlueprint(_step), ..._sheet.cutStrokes],
      skipCollinear: _skipPenciled,
    );
    if (end == null || cutRidesBoundary(from, end, rings)) return null;
    return (from, end);
  }

  List<List<Offset>> _paperEdges(PapercutPiece? piece) {
    if (piece != null) return [piece.vertices, ...piece.holes];
    return [
      for (final piece in _sheet.pieces) ...[piece.vertices, ...piece.holes],
    ];
  }

  Offset? _inwardOnHoles(Offset point, List<List<Offset>> holes) {
    for (final hole in holes) {
      final direction = inwardOnRing(point, hole);
      if (direction != null) return direction;
    }
    return null;
  }

  (List<(Offset, Offset)>, List<(Offset, Offset)>) _ruledGhosts(
    List<(Offset, Offset)> ghosts,
  ) {
    if (_liveRules.isEmpty) return (ghosts, const []);
    final open = <(Offset, Offset)>[];
    final blocked = <(Offset, Offset)>[];
    for (final ghost in ghosts) {
      if (_liveRules.allows(
        ghost.$1,
        ghost.$2,
        _progress,
        paper: _step.paper,
      )) {
        open.add(ghost);
      } else {
        blocked.add(ghost);
      }
    }
    return (open, blocked);
  }

  List<(Offset, Offset)> _displayGhosts(Offset? aim) {
    if (_tool != _GridTool.scissors) return const [];
    if (_flight.phase == ToolFlightPhase.cut) {
      final end = _modelEnd;
      if (end == null) return const [];
      final shift = _bladePiece()?.separation ?? Offset.zero;
      return [(_flight.pose(_flightAnim.value).tip - shift, end)];
    }
    if (_directing) {
      final from = _march?.position;
      if (from == null) return const [];
      return [for (final cut in _forwardOptions()) (from, cut.end)];
    }
    final ghost = _scissorGhost(aim);
    if (ghost == null) return const [];
    return [ghost];
  }

  String? _ruleStatus() {
    final rules = _step.rules;
    if (rules.isEmpty && _step.tools == null && _step.scissorLengthBudget == null) {
      return null;
    }
    final parts = <String>[];
    if (rules.maxExits != null) {
      parts.add('exits ${_progress.exitsUsed}/${rules.maxExits}');
    }
    if (rules.maxLength != null || _step.scissorLengthBudget != null) {
      final cap = _step.scissorLengthBudget ?? rules.maxLength!;
      parts.add(
        'length ${_progress.lengthUsed.toStringAsFixed(0)}/${cap.toStringAsFixed(0)}',
      );
    }
    if (rules.numbers.isNotEmpty) parts.add('next ${_progress.nextNumber}');
    final color = _progress.openColor;
    if (color != null && color >= 0 && color < kRuleColorNames.length) {
      parts.add(kRuleColorNames[color]);
    }
    if (rules.seams.isNotEmpty) {
      parts.add('seams ${_progress.severedSeams.length}/${rules.seams.length}');
    }
    if (rules.colors.isNotEmpty || rules.numbers.isNotEmpty) {
      final spentNumbers = rules.numbers
          .where((mark) => mark.number < _progress.nextNumber)
          .length;
      final got = _progress.collectedColors.length + spentNumbers;
      final total = rules.colors.length + rules.numbers.length;
      if (got < total) parts.add('gems $got/$total');
    }
    if (collectiblesCleared(rules, _progress)) parts.add('cleared');
    final filter = _step.tools;
    if (filter != null && filter.allows(CraftTool.folder)) {
      final cap = filter.budget(CraftTool.folder);
      parts.add(cap == null ? 'folds $_folderUses' : 'folds $_folderUses/${cap.toStringAsFixed(0)}');
    }
    if (filter != null && filter.allows(CraftTool.holePunch)) {
      final cap = filter.budget(CraftTool.holePunch);
      parts.add(cap == null ? 'punches $_punchUses' : 'punches $_punchUses/${cap.toStringAsFixed(0)}');
    }
    if (parts.isEmpty) return null;
    return parts.join('  ');
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
    if (_tool != _GridTool.scissors) return null;
    final aim = _aimWorld();
    if (aim == null) return null;
    final ghost = _cueSegment(aim);
    if (ghost == null) return null;
    final shift = _targetPiece(aim)?.separation ?? Offset.zero;
    final anchor = ghost.$1 + shift;
    final end = ghost.$2 + shift;
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
          if (split == true || _tool != _GridTool.scissors) _cutQueue.clear();
          if (split == false && _takeQueuedCut()) return;
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
            Padding(padding: const EdgeInsets.only(left: 76), child: _header()),
            Row(
              children: [
                _turnButton(clockwise: true),
                const Spacer(),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [_activeRuleBadge(), _compassButton()],
                ),
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
            DevToolsButton(
              active: _showTapDebug,
              onPressed: () => setState(() => _showTapDebug = !_showTapDebug),
            ),
            TextButton(onPressed: _clear, child: const Text('Clear')),
            TextButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
        if (_ruleStatus() case final status?)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              status,
              key: const Key('grid-rule-status'),
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _toolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_tool == _GridTool.holePunch) _punchBar(),
        if (_tool == _GridTool.folder)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'Tap a vertical crease, then swipe the side. Up folds toward you.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
          ),
        HudToolCarousel<_GridTool>(
          items: _carouselItems(),
          selected: _tool,
          onSelect: (tool) {
            setState(() {
              if (tool == _GridTool.select && _tool != _GridTool.select) {
                _abandonOtherTools();
              }
              _tool = tool;
            });
            _syncFlight();
          },
        ),
      ],
    );
  }

  List<HudCarouselItem<_GridTool>> _carouselItems() {
    final items = <HudCarouselItem<_GridTool>>[
      const HudCarouselItem(
        value: _GridTool.select,
        icon: Icons.near_me,
        label: 'Select',
        fill: Color(0xFF1A1A1A),
      ),
    ];
    bool show(CraftTool tool) {
      final filter = _step.tools;
      return filter == null || filter.allows(tool);
    }

    if (show(CraftTool.scissors)) {
      items.add(
        const HudCarouselItem(
          value: _GridTool.scissors,
          icon: Icons.content_cut,
          label: 'Scissors',
          fill: Color(0xFF1A1A1A),
        ),
      );
    }
    if (show(CraftTool.folder)) {
      items.add(
        const HudCarouselItem(
          value: _GridTool.folder,
          icon: Icons.flip,
          label: 'Folder',
          fill: Color(0xFF1A1A1A),
        ),
      );
    }
    if (show(CraftTool.holePunch)) {
      items.add(
        const HudCarouselItem(
          value: _GridTool.holePunch,
          icon: Icons.circle_outlined,
          label: 'Hole punch',
          fill: Color(0xFF1A1A1A),
        ),
      );
    }
    return items;
  }

  Widget _punchBar() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TextButton(
            onPressed: () => setState(() {
              const shapes = PunchShape.values;
              _punchShape = shapes[(_punchShape.index + 1) % shapes.length];
            }),
            child: Text(
              _punchShape.name,
              style: const TextStyle(color: Colors.white),
            ),
          ),
          TextButton(
            onPressed: () => setState(() {
              final index = punchSizes.indexOf(_punchSize);
              _punchSize = punchSizes[(index + 1) % punchSizes.length];
            }),
            child: Text(
              _punchSize.toString(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
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

  Widget _activeRuleBadge() {
    final cue = ruleCue(_step.rules, _progress);
    if (cue.isEmpty) return const SizedBox.shrink();
    return Row(
      key: const Key('grid-rule-badge'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (cue.color != null) _colorChip(cue.color!),
        if (cue.number != null) ...[
          if (cue.color != null) const SizedBox(width: 6),
          _numberChip(cue.number!),
        ],
        if (cue.link != null) ...[
          if (cue.color != null || cue.number != null) const SizedBox(width: 6),
          _linkChip(cue.link!),
        ],
        if (cue.seamsLeft != null) ...[
          if (cue.color != null || cue.number != null || cue.link != null)
            const SizedBox(width: 6),
          _seamChip(cue.seamsLeft!),
        ],
      ],
    );
  }

  Widget _colorChip(int color) {
    final ink = kRulePalette[color];
    return Container(
      key: const Key('grid-rule-badge-color'),
      width: 22,
      height: 22,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ink,
        border: Border.all(color: Colors.white, width: 1.6),
      ),
    );
  }

  Widget _numberChip(int number) {
    return Container(
      key: const Key('grid-rule-badge-number'),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _linkChip(int pair) {
    final ink = kRulePalette[pair.abs() % kRulePalette.length];
    return Container(
      key: const Key('grid-rule-badge-link'),
      width: 22,
      height: 22,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: ink,
        border: Border.all(color: Colors.white, width: 1.5),
      ),
      child: Text(
        '$pair',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _seamChip(int left) {
    return Container(
      key: const Key('grid-rule-badge-seams'),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: const Color(0xFFFF8A65), width: 1.4),
      ),
      child: Text(
        '$left',
        style: const TextStyle(color: Color(0xFFFF8A65), fontSize: 12),
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
                  child: Text(
                    entry.value,
                    style: const TextStyle(color: Colors.white70),
                  ),
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

/// Orange markers for the last click and the crosshair, with the delta labeled.
class _TapDebugPainter extends CustomPainter {
  _TapDebugPainter({
    required this.centroid,
    required this.tap,
    required this.side,
    required this.deadZone,
  });

  final Offset centroid;
  final Offset? tap;
  final String side;
  final double deadZone;

  static const _orange = Color(0xFFFF9800);

  @override
  void paint(Canvas canvas, Size size) {
    final zone = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _orange.withValues(alpha: 0.7);
    canvas.drawRect(
      Rect.fromCenter(
        center: centroid,
        width: deadZone * 2,
        height: deadZone * 2,
      ),
      zone,
    );
    _dot(canvas, centroid);
    _label(canvas, centroid + const Offset(12, -28), _xy('centroid', centroid));

    final click = tap;
    if (click == null) return;
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = _orange;
    canvas.drawLine(centroid, click, line);
    _dot(canvas, click);
    final delta = click - centroid;
    _label(canvas, click + const Offset(12, 8), _xy('click', click));
    _label(
      canvas,
      Offset.lerp(centroid, click, 0.5)! + const Offset(12, -8),
      'dx ${delta.dx.toStringAsFixed(0)}   dy ${delta.dy.toStringAsFixed(0)}\n$side',
    );
  }

  void _dot(Canvas canvas, Offset point) {
    canvas.drawCircle(point, 6, Paint()..color = _orange);
    canvas.drawCircle(
      point,
      6,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = const Color(0xFF1A1A1A),
    );
  }

  String _xy(String name, Offset point) =>
      '$name\n${point.dx.toStringAsFixed(0)}, ${point.dy.toStringAsFixed(0)}';

  void _label(Canvas canvas, Offset at, String text) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: _orange,
          fontSize: 12,
          height: 1.25,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _TapDebugPainter oldDelegate) {
    return oldDelegate.centroid != centroid ||
        oldDelegate.tap != tap ||
        oldDelegate.side != side ||
        oldDelegate.deadZone != deadZone;
  }
}
