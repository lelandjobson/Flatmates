import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:vector_math/vector_math_64.dart' hide Colors;

import '../gridcraft/blueprint.dart';
import '../gridcraft/blueprint_board.dart';
import '../gridcraft/blueprint_board_painter.dart';
import '../gridcraft/cube_blueprint.dart';
import '../gridcraft/dimension_measure.dart';
import '../gridcraft/edit.dart';
import '../gridcraft/fold.dart';
import '../gridcraft/fold_glyph.dart';
import '../gridcraft/level_io.dart';
import '../gridcraft/mixed_craft.dart';
import '../gridcraft/mixed_craft_painter.dart';
import '../gridcraft/paper_stack.dart';
import '../gridcraft/scissor.dart';
import '../gridcraft/scissor_glyph.dart';
import '../gridcraft/tool_animation.dart';
import '../gridcraft/tool_flight.dart';
import '../gridcraft/twin_ls.dart';
import '../papercut/camera.dart';
import '../papercut/models.dart';
import '../papercut/paper.dart';
import '../ui/craft_palette.dart';
import '../ui/fm_haptics.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/game_tool_carousel.dart';
import '../ui/game/view_crosshair.dart';
import '../ui/object_radial_menu.dart';
import 'blueprint_board_page.dart';
import 'craft_model_page.dart';

enum _CraftTool { select, scissors, folder }

enum _SelectMode { point, marquee }

enum _CutPulse { idle, engage, wipe }

/// One performed stroke, in drawn space, while the blade travels it.
class _CutWipe {
  const _CutWipe({
    required this.from,
    required this.to,
    required this.direction,
    required this.stroke,
    required this.sheetId,
    required this.pieceId,
    required this.fromScale,
    required this.roll,
    required this.open,
  });

  final Offset from;
  final Offset to;
  final Offset direction;
  final List<Offset> stroke;
  final String sheetId;
  final String pieceId;
  final double fromScale;

  /// Seated glyph, frozen so the travel does not roll or recock the blades.
  final double roll;
  final double open;
}

/// One performed crease, in drawn space, while the folder travels it.
class _FoldWipe {
  const _FoldWipe({
    required this.from,
    required this.to,
    required this.direction,
    required this.sheetId,
    required this.pieceId,
    required this.face,
    required this.fold,
    required this.fromScale,
    required this.roll,
    required this.open,
  });

  final Offset from;
  final Offset to;
  final Offset direction;
  final String sheetId;
  final String pieceId;
  final Offset face;

  /// True folds the flap. False scores the crease.
  final bool fold;
  final double fromScale;
  final double roll;
  final double open;
}

/// How long the cut point grows before a stroke, and how long a fold mark travels.
const Duration _kCutPulse = Duration(milliseconds: 200);

/// Horizontal settle when the carets change boards.
const Duration _kBoardPan = Duration(milliseconds: 320);
const int _kBoardCount = 3;

/// The paper lifts and settles flat after a crease, matching the grid puzzles.
const Duration _kCreaseFlutter = Duration(milliseconds: 300);

/// A scored crease swinging back to flat. The joint is not part of the sheet.
class _CreaseFlutter {
  const _CreaseFlutter({required this.sheetId, required this.joint});

  final String sheetId;
  final FoldJoint joint;
}

/// Folded model, dimension board, and papercraft bench, in that order.
///
/// The sheet is 24×24 real units and reads as 6×6 at the opening grid scale.
/// Carets at the top step one board at a time. Pieces travel with the radial arrows.
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
  int _page = 0;
  late GridBlueprint _blueprint;
  late List<BoardStepChoice> _choices;
  late String _choiceKey;
  int _stepIndex = 0;
  final Map<String, StepBoard> _boards = {};
  bool _showPlacedDimensions = false;
  final List<BoardTransfer?> _undoTransfers = [];
  final List<BoardTransfer?> _redoTransfers = [];
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
  _CutPulse _cutPulseKind = _CutPulse.idle;
  _CutWipe? _cutWipe;
  double _pointScale = 1;
  late final AnimationController _cutPulse;

  CutLock? _fold;
  _CutPulse _foldPulseKind = _CutPulse.idle;
  _FoldWipe? _foldWipe;
  double _foldPointScale = 1;
  late final AnimationController _foldPulse;
  _CreaseFlutter? _flutter;
  late final AnimationController _creaseAnim;

  Offset? _marqueeStart;
  Offset? _marqueeCurrent;

  bool _moving = false;
  MixedCraftArea? _moveOrigin;
  bool _transforming = false;
  MixedCraftArea? _transformOrigin;
  Rect? _transformBounds;
  TransformHandle? _transformHandle;
  bool _turning = false;
  Offset? _turnPivot;
  double? _turnStart;
  double _turnDegrees = 0;
  Offset? _ringCenter;
  double? _ringRadius;

  /// Unsnapped translation of this move, following the reticle.
  Offset _moveFree = Offset.zero;

  List<String> _pickStack = const [];
  int _pickClicks = 0;
  DateTime? _pickTapAt;
  bool _scissorSyncQueued = false;
  bool _foldSyncQueued = false;

  @override
  void initState() {
    super.initState();
    final opened = cubeBlueprint();
    _blueprint = opened;
    _choices = choicesForBlueprint(opened);
    _choiceKey = boardStepKey(opened.id, _stepIndex);
    _loadBoardChoices();
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
    _cutPulse = AnimationController(vsync: this, duration: _kCutPulse)
      ..addListener(_onCutPulseTick)
      ..addStatusListener(_onCutPulseStatus);
    _foldPulse = AnimationController(vsync: this, duration: _kCutPulse)
      ..addListener(_onFoldPulseTick)
      ..addStatusListener(_onFoldPulseStatus);
    _creaseAnim = AnimationController(vsync: this, duration: _kCreaseFlutter)
      ..addListener(() {
        if (mounted) setState(() {});
      })
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed || !mounted) return;
        setState(() => _flutter = null);
      });
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
    _creaseAnim.dispose();
    _foldPulse.dispose();
    _cutPulse.dispose();
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

  StepBoard get _board => _boards.putIfAbsent(_choiceKey, StepBoard.new);

  GridStep? get _currentStep {
    if (_blueprint.steps.isEmpty) return null;
    return _blueprint.steps[_stepIndex.clamp(0, _blueprint.steps.length - 1)];
  }

  void _pushCraft(MixedCraftArea before, {BoardTransfer? transfer}) {
    _history.push(before);
    _undoTransfers.add(transfer);
    if (_undoTransfers.length > kMixedHistoryDepth) {
      _undoTransfers.removeAt(0);
    }
    _redoTransfers.clear();
  }

  void _apply(MixedCraftArea? next, {BoardTransfer? transfer}) {
    if (next == null) return;
    _pushCraft(_area, transfer: transfer);
    _area = next;
  }

  bool _undoCraft() {
    final previous = _history.undo(_area);
    if (previous == null) return false;
    final transfer = _undoTransfers.isEmpty
        ? null
        : _undoTransfers.removeLast();
    _redoTransfers.add(transfer);
    transfer?.undo(_boards);
    _area = previous;
    return true;
  }

  bool _redoCraft() {
    final next = _history.redo(_area);
    if (next == null) return false;
    final transfer = _redoTransfers.isEmpty
        ? null
        : _redoTransfers.removeLast();
    _undoTransfers.add(transfer);
    transfer?.redo(_boards);
    _area = next;
    return true;
  }

  Future<void> _loadBoardChoices() async {
    final store = LevelStore(bundle: rootBundle);
    final collections = await store.loadCollections();
    final side = [
      for (final collection in collections)
        if (collection.id == 'side-table') ...collection.puzzles,
    ];
    if (!mounted) return;
    final choices = choicesForBlueprint(cubeBlueprint());
    final seen = {for (final choice in choices) choice.key};
    for (final choice in choicesForBlueprint(twinLsBlueprint())) {
      if (seen.add(choice.key)) choices.add(choice);
    }
    for (final puzzle in side) {
      for (final choice in choicesForBlueprint(puzzle)) {
        if (seen.add(choice.key)) choices.add(choice);
      }
    }
    setState(() {
      _choices = choices;
      if (!_choices.any((choice) => choice.key == _choiceKey)) {
        final first = _choices.first;
        _choiceKey = first.key;
        _blueprint = first.blueprint;
        _stepIndex = first.stepIndex;
      }
    });
  }

  void _selectBoardStep(String? key) {
    if (key == null || key == _choiceKey) return;
    final choice = _choices.where((item) => item.key == key).firstOrNull;
    if (choice == null) return;
    setState(() {
      _choiceKey = key;
      _blueprint = choice.blueprint;
      _stepIndex = choice.stepIndex;
    });
  }

  void _sendSelectionToBoard() {
    final step = _currentStep;
    if (step == null || _area.selected.isEmpty) return;
    final board = _board;
    final center = vertexBounds(step.vertices)?.center ?? Offset.zero;
    final taken = takeCraftSelection(
      _area,
      center: center,
      nextId: board.nextId,
    );
    if (taken == null) return;
    setState(() {
      _moving = false;
      board.nextId = taken.nextId;
      board.addPieces(taken.pieces);
      board.selected
        ..clear()
        ..addAll(taken.pieces.map((piece) => piece.id));
      _apply(
        taken.craft,
        transfer: BoardTransfer(
          stepKey: _choiceKey,
          pieces: [for (final piece in taken.pieces) piece.clone()],
          addedToBoard: true,
        ),
      );
    });
  }

  void _receiveFromBoard() {
    final board = _board;
    final selected = [
      for (final piece in board.pieces)
        if (board.selected.contains(piece.id)) piece.clone(),
    ];
    if (selected.isEmpty) return;
    final placed = placePiecesOnCraft(_area, selected, center: Offset.zero);
    setState(() {
      board.removeIds(selected.map((piece) => piece.id));
      _apply(
        placed,
        transfer: BoardTransfer(
          stepKey: _choiceKey,
          pieces: selected,
          addedToBoard: false,
        ),
      );
    });
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
    _cutWipe = null;
    _cutPulseKind = _CutPulse.idle;
    _pointScale = 1;
    if (_cutPulse.isAnimating) _cutPulse.stop();
  }

  void _clearFold() {
    _fold = null;
    _foldWipe = null;
    _flutter = null;
    if (_creaseAnim.isAnimating) _creaseAnim.stop();
    _foldPulseKind = _CutPulse.idle;
    _foldPointScale = 1;
    if (_foldPulse.isAnimating) _foldPulse.stop();
  }

  void _setTool(_CraftTool tool) {
    setState(() {
      _tool = tool;
      _moving = false;
      _clearTransform();
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
    if (_transforming) {
      _transformDown(event.localPosition);
    } else if (_tool == _CraftTool.select && _selectMode == _SelectMode.marquee) {
      _marqueeStart = event.localPosition;
      _marqueeCurrent = event.localPosition;
    } else if (_moving) {
      _moveOrigin = _area;
      _moveFree = Offset.zero;
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
    if (_moving && _moveOrigin != null) {
      if (!_dragged) return;
      _followReticle(event.localPosition - previous);
      setState(() {});
      return;
    }
    if (_transforming && _transformHandle != null && _dragged) {
      _dragTransformHandle(event.localPosition);
      setState(() {});
      return;
    }
    if (_transforming && _turning && _dragged) {
      _dragTransformTurn(event.localPosition);
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
    } else if (_transforming) {
      _finishTransform(dragged);
    } else if (!dragged) {
      _onTap();
    } else if (_tool == _CraftTool.scissors && _cut != null) {
      _cutGlowing = true;
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
    _moveFree = Offset.zero;
    if (_transformOrigin != null) _area = _transformOrigin!;
    _transformOrigin = null;
    _transformHandle = null;
    _turning = false;
    _turnDegrees = 0;
    _ringCenter = null;
    _ringRadius = null;
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
    if (_cutWipe != null) return;
    final lock = _cut;
    if (lock == null) {
      // The glyph is already on the nearest edge. The tap starts there even
      // when the reticle sits well inside the paper.
      _cut = lockCut(aim, _area, _scale, maxCells: null);
      _cutGlowing = false;
      if (_cut != null) _beginEngage();
      return;
    }
    final end = _dictatedEnd(lock, aim);
    if (end == null || (end - lock.point).distance < 1e-3) return;
    final piece = pieceForKey(_area, mixedPieceKey(lock.sheetId, lock.pieceId));
    final separation = piece?.separation ?? Offset.zero;
    final from = lock.point + separation;
    final to = end + separation;
    final delta = to - from;
    if (delta.distance < 1e-3) return;
    final direction = delta / delta.distance;
    _seatTool(_flight, _flightAnim, anchor: to, direction: direction);
    final seated = _flight.pose(0);
    _cutWipe = _CutWipe(
      from: from,
      to: to,
      direction: direction,
      stroke: [...lock.path, end],
      sheetId: lock.sheetId,
      pieceId: lock.pieceId,
      fromScale: _pointScale,
      roll: seated.roll,
      open: seated.open,
    );
    _cutPulseKind = _CutPulse.wipe;
    unawaited(fmHaptic(FmHapticStyle.lightImpact));
    _cutPulse.duration = cutWipeDuration(delta.distance);
    _cutPulse.forward(from: 0);
  }

  void _beginEngage() {
    _cutPulseKind = _CutPulse.engage;
    _pointScale = 1;
    unawaited(fmHaptic(FmHapticStyle.mediumImpact));
    _cutPulse.duration = _kCutPulse;
    _cutPulse.forward(from: 0);
  }

  void _onCutPulseTick() {
    final t = _cutPulse.value;
    if (_cutPulseKind == _CutPulse.engage) {
      _pointScale = 1 + 3 * Curves.easeOut.transform(t);
    } else if (_cutPulseKind == _CutPulse.wipe) {
      final from = _cutWipe?.fromScale ?? 4;
      _pointScale = from + (1 - from) * _approach(t);
    }
    if (mounted) setState(() {});
  }

  void _onCutPulseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final kind = _cutPulseKind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _cutPulseKind != kind) return;
      if (kind == _CutPulse.engage) {
        _cutPulseKind = _CutPulse.idle;
        _pointScale = 4;
        setState(() {});
        return;
      }
      if (kind == _CutPulse.wipe) _finishCutWipe();
    });
  }

  void _finishCutWipe() {
    final wipe = _cutWipe;
    _cutWipe = null;
    _cutPulseKind = _CutPulse.idle;
    if (wipe == null) return;
    final committed = commitCut(_area, wipe.sheetId, wipe.stroke);
    if (committed == null) {
      _seatTool(
        _flight,
        _flightAnim,
        anchor: wipe.from,
        direction: wipe.direction,
      );
      _pointScale = 4;
      setState(() {});
      return;
    }
    _apply(committed.area);
    if (!committed.stoppedInside) {
      _seatTool(
        _flight,
        _flightAnim,
        anchor: wipe.to,
        direction: wipe.direction,
      );
      _cut = null;
      _cutGlowing = false;
      _pointScale = 1;
      setState(() {});
      return;
    }
    final end = wipe.stroke.last;
    final previous = wipe.stroke[wipe.stroke.length - 2];
    final delta = end - previous;
    final piece = pieceForKey(
      committed.area,
      mixedPieceKey(wipe.sheetId, wipe.pieceId),
    );
    final direction = delta.distance < 1e-6
        ? wipe.direction
        : delta / delta.distance;
    _cut = CutLock(
      sheetId: wipe.sheetId,
      pieceId: piece?.id ?? wipe.pieceId,
      path: wipe.stroke,
      direction: direction,
    );
    _cutGlowing = false;
    _seatTool(
      _flight,
      _flightAnim,
      anchor: end + (piece?.separation ?? Offset.zero),
      direction: direction,
    );
    setState(() {});
    _beginEngage();
  }

  /// Model-space end under the reticle. The stroke stops on a grid point or
  /// a piece vertex, including when that point is still inside the paper.
  Offset? _dictatedEnd(CutLock lock, Offset aim) {
    final piece = pieceForKey(_area, mixedPieceKey(lock.sheetId, lock.pieceId));
    final separation = piece?.separation ?? Offset.zero;
    return snapCut(aim, _scale, _area) - separation;
  }

  void _foldTap(Offset aim) {
    if (_foldWipe != null) return;
    final lock = _fold;
    if (lock == null) {
      _fold = lockCut(aim, _area, _scale, maxCells: null);
      if (_fold != null) {
        _beginFoldEngage();
        return;
      }
      final opened = unfoldUnder(_area, aim);
      if (opened != null) _apply(opened);
      return;
    }
    final chord = _foldChord(aim);
    if (chord == null) return;
    _beginFoldWipe(chord);
  }

  /// Crease from the locked edge through the reticle, out the far side.
  FoldChord? _foldChord(Offset aim) {
    final lock = _fold;
    if (lock == null) return null;
    final piece = pieceForKey(_area, mixedPieceKey(lock.sheetId, lock.pieceId));
    final separation = piece?.separation ?? Offset.zero;
    return foldThroughPiece(
      _area,
      lock.point + separation,
      snapCut(aim, _scale, _area),
    );
  }

  /// A point just beside the crease, so the fold has a side to turn.
  Offset _flapBeside(Offset start, Offset end) {
    final delta = end - start;
    final dir = delta / delta.distance;
    final mid = Offset.lerp(start, end, 0.5)!;
    return mid + Offset(-dir.dy, dir.dx);
  }

  void _beginFoldEngage() {
    _foldPulseKind = _CutPulse.engage;
    _foldPointScale = 1;
    unawaited(fmHaptic(FmHapticStyle.mediumImpact));
    _foldPulse.duration = _kCutPulse;
    _foldPulse.forward(from: 0);
  }

  void _beginFoldWipe(FoldChord chord) {
    if (_foldWipe != null) return;
    final delta = chord.end - chord.start;
    if (delta.distance < 1e-3) return;
    final direction = delta / delta.distance;
    _seatTool(
      _foldFlight,
      _foldFlightAnim,
      anchor: chord.end,
      direction: direction,
    );
    final seated = _foldFlight.pose(0);
    _foldWipe = _FoldWipe(
      from: chord.start,
      to: chord.end,
      direction: direction,
      sheetId: chord.sheetId,
      pieceId: chord.pieceId,
      face: _flapBeside(chord.start, chord.end),
      fold: false,
      fromScale: _foldPointScale,
      roll: seated.roll,
      open: seated.open,
    );
    _foldPulseKind = _CutPulse.wipe;
    unawaited(fmHaptic(FmHapticStyle.lightImpact));
    _foldPulse.duration = cutWipeDuration(delta.distance);
    _foldPulse.forward(from: 0);
    setState(() {});
  }

  void _onFoldPulseTick() {
    final t = _foldPulse.value;
    if (_foldPulseKind == _CutPulse.engage) {
      _foldPointScale = 1 + 3 * Curves.easeOut.transform(t);
    } else if (_foldPulseKind == _CutPulse.wipe) {
      final from = _foldWipe?.fromScale ?? 4;
      _foldPointScale = from + (1 - from) * _approach(t);
    }
    if (mounted) setState(() {});
  }

  void _onFoldPulseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    final kind = _foldPulseKind;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _foldPulseKind != kind) return;
      if (kind == _CutPulse.engage) {
        _foldPulseKind = _CutPulse.idle;
        _foldPointScale = 4;
        setState(() {});
        return;
      }
      if (kind == _CutPulse.wipe) _finishFoldWipe();
    });
  }

  void _finishFoldWipe() {
    final wipe = _foldWipe;
    _foldWipe = null;
    _foldPulseKind = _CutPulse.idle;
    if (wipe == null) return;
    final next = wipe.fold
        ? foldSpan(_area, wipe.sheetId, wipe.from, wipe.to, wipe.face)
        : scoreSpan(_area, wipe.sheetId, wipe.from, wipe.to, wipe.face);
    if (next == null) {
      _seatTool(
        _foldFlight,
        _foldFlightAnim,
        anchor: wipe.from,
        direction: wipe.direction,
      );
      _foldPointScale = 4;
      setState(() {});
      return;
    }
    _apply(next);
    _seatTool(
      _foldFlight,
      _foldFlightAnim,
      anchor: wipe.to,
      direction: wipe.direction,
    );
    _fold = null;
    _foldPointScale = 1;
    _beginCreaseFlutter(wipe, next);
    setState(() {});
  }

  /// Lifts the scored flap and lets it fall flat, the way a grid puzzle creases.
  void _beginCreaseFlutter(_FoldWipe wipe, MixedCraftArea scored) {
    final sheet = scored.sheetById(wipe.sheetId);
    final piece = pieceForKey(
      scored,
      mixedPieceKey(wipe.sheetId, wipe.pieceId),
    );
    if (sheet == null || piece == null) return;
    final shift = piece.separation;
    final a = wipe.from - shift;
    final b = wipe.to - shift;
    final side = sideOfLine(wipe.face - shift, a, b);
    if (side.abs() < 1e-4) return;
    _flutter = _CreaseFlutter(
      sheetId: wipe.sheetId,
      joint: FoldJoint(
        a: a,
        b: b,
        side: side,
        facing: FoldFacing.toward,
        pieceIds: {piece.id},
      ),
    );
    _creaseAnim.forward(from: 0);
  }

  /// Slides the sheet under the reticle and carries the selection with it.
  /// A vertex within [kMixedSnapPixels] of a grid point lands on that point.
  /// Otherwise the piece stays where the pan left it.
  void _followReticle(Offset screenDelta) {
    final origin = _moveOrigin;
    if (origin == null || screenDelta == Offset.zero) return;
    final before = _aim();
    _pan(screenDelta);
    final after = _aim();
    if (before != null && after != null) _moveFree += after - before;
    final placed = movePieces(origin, _moveFree) ?? origin;
    final snap = vertexGridSnap(placed, _scale, _snapRadius());
    _area = snap == null ? placed : (movePieces(placed, snap) ?? placed);
  }

  double _snapRadius() {
    final shorter = math.min(_viewport.width, _viewport.height);
    return snapWorldRadius(
      pixels: kMixedSnapPixels,
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

  void _clearTransform() {
    _transforming = false;
    _transformOrigin = null;
    _transformHandle = null;
    _transformBounds = null;
    _turning = false;
    _turnPivot = null;
    _turnStart = null;
    _turnDegrees = 0;
    _ringCenter = null;
    _ringRadius = null;
  }

  void _transformDown(Offset screen) {
    final bounds = craftSelectionBounds(_area);
    if (bounds == null) return;
    final ring = _rotationWidget(bounds);
    if (ring != null && kCombinedTransform.rotation && ring.hits(screen)) {
      _turning = true;
      _transformOrigin = _area;
      _transformBounds = bounds;
      _turnPivot = bounds.center;
      _turnStart = math.atan2(
        screen.dy - ring.center.dy,
        screen.dx - ring.center.dx,
      );
      _turnDegrees = 0;
      _ringCenter = ring.center;
      _ringRadius = ring.radius;
      return;
    }
    final world = _world(screen);
    if (world == null) return;
    final handle = hitTransformHandle(
      world,
      bounds,
      _handleRadius(),
      box: kCombinedTransform,
    );
    if (handle == null) return;
    _transformHandle = handle;
    _transformOrigin = _area;
    _transformBounds = bounds;
  }

  void _dragTransformHandle(Offset screen) {
    final origin = _transformOrigin;
    final bounds = _transformBounds;
    final handle = _transformHandle;
    final world = _world(screen);
    if (origin == null || bounds == null || handle == null || world == null) {
      return;
    }
    final stretch = stretchToPointer(
      handle: handle,
      bounds: bounds,
      pointer: world,
      blueprintVertices: const [],
      spacing: _scale.toDouble(),
      radius: _snapRadius(),
      uniform: !kCombinedTransform.stretch,
    );
    _area =
        mapSelectedGeometry(
          origin,
          (point) => applyStretchPoint(point, stretch),
        ) ??
        origin;
  }

  void _dragTransformTurn(Offset screen) {
    final origin = _transformOrigin;
    final pivot = _turnPivot;
    final start = _turnStart;
    final center = _ringCenter;
    if (origin == null || pivot == null || start == null || center == null) {
      return;
    }
    final arm = screen - center;
    if (arm.distance < 1e-6) return;
    final degrees = RotationWidget.degreesFromScreen(
      startAngle: start,
      currentAngle: math.atan2(arm.dy, arm.dx),
    );
    _turnDegrees = degrees;
    _area =
        mapSelectedGeometry(
          origin,
          (point) => rotateAround(point, pivot, degrees * math.pi / 180),
        ) ??
        origin;
  }

  void _finishTransform(bool dragged) {
    final dismiss = !dragged && _transformHandle == null && !_turning;
    final origin = _transformOrigin;
    if (dragged && origin != null && !identical(_area, origin)) {
      _pushCraft(origin);
    } else if (!dragged && origin != null) {
      _area = origin;
    }
    _transformOrigin = null;
    _transformHandle = null;
    _transformBounds = null;
    _turning = false;
    _turnPivot = null;
    _turnStart = null;
    _turnDegrees = 0;
    _ringCenter = null;
    _ringRadius = null;
    if (dismiss) _transforming = false;
  }

  RotationWidget? _rotationWidget(Rect bounds) {
    if (_ringCenter != null && _ringRadius != null) {
      return RotationWidget(
        center: _ringCenter!,
        radius: _ringRadius!,
        degrees: _turnDegrees,
      );
    }
    final center = _project(bounds.center);
    final corner = _project(bounds.topLeft);
    if (center == null || corner == null) return null;
    return RotationWidget.layout(
      center: center,
      halfDiagonal: (corner - center).distance,
      degrees: _turnDegrees,
    );
  }

  void _finishMove() {
    final origin = _moveOrigin;
    if (origin != null && !identical(_area, origin)) {
      _pushCraft(origin);
    }
    _moveOrigin = null;
    _moveFree = Offset.zero;
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
      final wipe = _cutWipe;
      if (wipe != null) {
        final tip = Offset.lerp(
          wipe.from,
          wipe.to,
          _approach(_cutPulse.value),
        )!;
        if ((wipe.to - tip).distance < 0.05) return null;
        return (tip, wipe.to);
      }
      final lock = _cut;
      if (lock == null || aim == null) return null;
      final piece = pieceForKey(
        _area,
        mixedPieceKey(lock.sheetId, lock.pieceId),
      );
      final separation = piece?.separation ?? Offset.zero;
      final end = _dictatedEnd(lock, aim);
      if (end == null) return null;
      return (lock.point + separation, end + separation);
    }
    if (_tool != _CraftTool.folder || _fold == null) return null;
    final wipe = _foldWipe;
    if (wipe != null) {
      final tip = Offset.lerp(wipe.from, wipe.to, _approach(_foldPulse.value))!;
      if ((wipe.to - tip).distance < 0.05) return null;
      return (tip, wipe.to);
    }
    if (aim == null) return null;
    final chord = _foldChord(aim);
    if (chord == null) return null;
    return (chord.start, chord.end);
  }

  /// Stroke progress that leaves quickly and settles at the end.
  double _approach(double t) => Curves.easeOutCubic.transform(t);

  /// Parks the flight on [anchor] so the next frame does not play a second trip.
  void _seatTool(
    ToolFlight flight,
    AnimationController anim, {
    required Offset anchor,
    required Offset direction,
  }) {
    final aim = _aim() ?? anchor;
    final length = direction.distance;
    final dir = length < 1e-6 ? const Offset(1, 0) : direction / length;
    flight.seat(
      ToolCue(anchor: anchor, direction: dir, aim: aim, reach: _scale * 0.75),
    );
    if (anim.isAnimating) anim.stop();
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

  ToolPose _scissorPose() {
    final pose = _flight.pose(_flightAnim.value);
    final wipe = _cutWipe;
    if (wipe == null) return pose;
    final t = _approach(_cutPulse.value);
    // The seated glyph travels the line. A cutting pose would zero its yaw
    // and leave a second graphic behind when the wipe ends.
    return ToolPose(
      tip: Offset.lerp(wipe.from, wipe.to, t)!,
      direction: wipe.direction,
      roll: wipe.roll,
      open: wipe.open,
      lateral: 0,
      visible: pose.visible <= 0 ? 1 : pose.visible,
    );
  }

  ToolPose _folderPose() {
    final pose = _foldFlight.pose(_foldFlightAnim.value);
    final wipe = _foldWipe;
    if (wipe == null) return pose;
    return ToolPose(
      tip: Offset.lerp(wipe.from, wipe.to, _approach(_foldPulse.value))!,
      direction: wipe.direction,
      roll: wipe.roll,
      open: wipe.open,
      lateral: 0,
      visible: pose.visible <= 0 ? 1 : pose.visible,
    );
  }

  void _syncScissors() {
    if (!mounted || _viewport.width < 2 || _cutWipe != null) return;
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
    if (lock == null) return _shownEdgeCue(aim);
    final piece = pieceForKey(_area, mixedPieceKey(lock.sheetId, lock.pieceId));
    if (piece == null) return null;
    var direction = lock.direction;
    final line = _segment();
    if (line != null) {
      final delta = line.$2 - line.$1;
      if (delta.distance > 1e-6) direction = delta / delta.distance;
    }
    if (direction.distance < 1e-6) direction = const Offset(1, 0);
    return ToolCue(
      anchor: lock.point + piece.separation,
      direction: direction,
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
    if (!mounted || _viewport.width < 2 || _foldWipe != null) return;
    if (_foldFlight.phase == ToolFlightPhase.cut) return;
    final next = _folderCue();
    final duration = _foldFlight.offer(
      next,
      t: _foldFlightAnim.value,
      approach: _foldApproach(next),
    );
    if (duration != null) _playFoldFlight(duration);
  }

  /// Nearest paper edge, with no distance cutoff. Cut and fold both start here.
  ToolCue? _shownEdgeCue(Offset aim) {
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

  ToolCue? _folderCue() {
    if (_tool != _CraftTool.folder) return null;
    final aim = _aim();
    if (aim == null) return null;
    final lock = _fold;
    if (lock == null) return _shownEdgeCue(aim);
    final piece = pieceForKey(_area, mixedPieceKey(lock.sheetId, lock.pieceId));
    if (piece == null) return null;
    var direction = lock.direction;
    final chord = _foldWipe == null ? _foldChord(aim) : null;
    final along = chord == null ? null : chord.end - chord.start;
    if (along != null && along.distance > 1e-6) {
      direction = along / along.distance;
    }
    if (direction.distance < 1e-6) direction = const Offset(1, 0);
    return ToolCue(
      anchor: lock.point + piece.separation,
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
    const background = kPapercutBackground;
    return FmScreen(
      backgroundColor: background,
      overlays: [const FmDevBackButton(), _pageCarets()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final height = constraints.maxHeight;
          return ClipRect(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(end: _page.toDouble()),
              duration: _kBoardPan,
              curve: Curves.easeOutCubic,
              builder: (context, page, child) {
                return OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: width * _kBoardCount,
                  maxWidth: width * _kBoardCount,
                  minHeight: height,
                  maxHeight: height,
                  child: Transform.translate(
                    offset: Offset(-page * width, 0),
                    child: child,
                  ),
                );
              },
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: width,
                    child: CraftModelPage(
                      blueprint: _blueprint,
                      stepIndex: _stepIndex,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: BlueprintBoardPage(
                      stepKey: _choiceKey,
                      blueprint: _blueprint,
                      stepIndex: _stepIndex,
                      choices: _choices,
                      board: _board,
                      showPlacedDimensions: _showPlacedDimensions,
                      onShowPlacedDimensions: (value) =>
                          setState(() => _showPlacedDimensions = value),
                      onStep: _selectBoardStep,
                      onSendToCraft: _receiveFromBoard,
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        _viewport = Size(
                          constraints.maxWidth,
                          constraints.maxHeight,
                        );
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
                        final snap = aim == null
                            ? null
                            : snapCut(aim, _scale, _area);
                        final cutMark = _cutWipe != null
                            ? _cutWipe!.to
                            : (_tool == _CraftTool.scissors && _cut != null
                                  ? snap
                                  : null);
                        final foldMark = _foldWipe != null
                            ? _foldWipe!.to
                            : (_tool == _CraftTool.folder &&
                                      _fold != null &&
                                      aim != null
                                  ? _foldChord(aim)?.end
                                  : null);
                        final hover = aim == null
                            ? null
                            : pieceUnderAim(_area, aim);
                        final segment = _segment();
                        final transformBounds = _transforming
                            ? craftSelectionBounds(_area)
                            : null;
                        final ring = transformBounds == null
                            ? null
                            : _rotationWidget(transformBounds);
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
                                  _zoom(
                                    math.exp(-event.scrollDelta.dy * 0.002),
                                  );
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
                                        grids: _grids.opacities(
                                          _gridFade.value,
                                        ),
                                        view: _visible(),
                                        hoverKey: hover,
                                        segment: segment,
                                        segmentGlows:
                                            _tool == _CraftTool.scissors
                                            ? _cutGlowing
                                            : _fold != null,
                                        foldSegment: _tool == _CraftTool.folder,
                                        marquee: _marqueeRect(),
                                        marqueeCross:
                                            _marqueeStart != null &&
                                            _marqueeCurrent != null &&
                                            marqueePick(
                                                  _marqueeStart!,
                                                  _marqueeCurrent!,
                                                ) ==
                                                MarqueePick.cross,
                                        flutterSheetId: _flutter?.sheetId,
                                        flutterJoint: _flutter?.joint,
                                        flutterBendT: _flutter == null
                                            ? 0
                                            : creaseFoldBend(_creaseAnim.value),
                                        background: background,
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
                                    animation: Listenable.merge([
                                      _flightAnim,
                                      _cutPulse,
                                    ]),
                                    builder: (context, _) {
                                      return CustomPaint(
                                        painter: ScissorGlyphPainter(
                                          camera: _camera,
                                          pose: _scissorPose(),
                                          tool: _scissors,
                                          glyphScale: 0.5,
                                          pointScale:
                                              _cut == null && _cutWipe == null
                                              ? 1
                                              : _pointScale,
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
                                    animation: Listenable.merge([
                                      _foldFlightAnim,
                                      _foldPulse,
                                    ]),
                                    builder: (context, _) {
                                      return CustomPaint(
                                        painter: FoldGlyphPainter(
                                          camera: _camera,
                                          pose: _folderPose(),
                                          destination: foldMark,
                                          pointScale:
                                              _fold == null && _foldWipe == null
                                              ? 1
                                              : _foldPointScale,
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            if (transformBounds != null)
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: BlueprintBoardPainter(
                                      camera: _camera,
                                      pieces: const [],
                                      selected: const {},
                                      transform: transformBounds,
                                      box: kCombinedTransform,
                                      rotation: ring,
                                    ),
                                  ),
                                ),
                              ),
                            if (!_transforming)
                              const IgnorePointer(child: ViewCrosshair()),
                            if (_tool == _CraftTool.select &&
                                menuCenter != null &&
                                _area.selected.isNotEmpty &&
                                _marqueeStart == null &&
                                _moveOrigin == null &&
                                !_transforming)
                              Positioned.fill(
                                child: ObjectRadialMenu(
                                  center: menuCenter,
                                  actions: [
                                    RadialAction(
                                      icon: Icons.arrow_back,
                                      label: 'Dimension',
                                      tint: const Color(0xFF90CAF9),
                                      side: RadialActionSide.left,
                                      onTap: _sendSelectionToBoard,
                                    ),
                                    RadialAction(
                                      icon: Icons.open_with,
                                      label: 'Move',
                                      tint: const Color(0xFF90A4AE),
                                      onTap: () =>
                                          setState(() => _moving = true),
                                    ),
                                    RadialAction(
                                      icon: Icons.crop_rotate,
                                      label: 'Transform',
                                      tint: const Color(0xFF80CBC4),
                                      onTap: () => setState(() {
                                        _moving = false;
                                        _transforming = true;
                                      }),
                                    ),
                                    RadialAction(
                                      icon: Icons.visibility_off,
                                      label: 'Hide',
                                      tint: const Color(0xFF78909C),
                                      onTap: () => setState(
                                        () => _apply(hideSelection(_area)),
                                      ),
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
                                    if (!_undoCraft()) return;
                                    setState(() {
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
                                    if (!_redoCraft()) return;
                                    setState(() {
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
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageCarets() {
    return FmSafePositioned(
      top: 8,
      left: 0,
      right: 0,
      minimum: kFmScreenInset,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _caret(
            key: const Key('board-caret-left'),
            icon: Icons.chevron_left,
            enabled: _page > 0,
            onTap: () => setState(() => _page -= 1),
          ),
          const SizedBox(width: 8),
          _caret(
            key: const Key('board-caret-right'),
            icon: Icons.chevron_right,
            enabled: _page < _kBoardCount - 1,
            onTap: () => setState(() => _page += 1),
          ),
        ],
      ),
    );
  }

  Widget _caret({
    required Key key,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(
          icon,
          size: 32,
          color: Colors.white.withValues(alpha: enabled ? 0.92 : 0.28),
        ),
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
