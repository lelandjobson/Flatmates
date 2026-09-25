import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../gestures/gesture_system.dart';
import '../papercut/camera.dart';
import '../papercut/craft_puzzle.dart';
import '../papercut/craft_v1.dart';
import '../papercut/cut_graph.dart';
import '../papercut/measure.dart';
import '../papercut/models.dart';
import '../papercut/painter.dart';
import '../papercut/paper.dart';
import '../papercut/samples.dart';
import '../papercut/score.dart';
import '../papercut/split.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_safe_area.dart';
import '../ui/fm_screen.dart';
import '../ui/game/game_tool_carousel.dart';

enum PapercutTool { scissors, exacto, straightEdge }

enum StraightEdgeAction { cut, fold }

enum _RotationPhase { idle, armed, rotating, settling, cooldown }

const double _kTapSlop = 10;
const Duration _kRotationGrace = Duration(seconds: 3);
const Duration _kRotationCooldown = Duration(milliseconds: 250);
const Duration _kRollSettle = Duration(milliseconds: 200);

class PapercutPuzzlesView extends StatefulWidget {
  const PapercutPuzzlesView({super.key, this.crafts});

  /// When set, these crafts are listed and assets are not loaded.
  /// Null loads `assets/craft_viewer`.
  final List<CraftV1>? crafts;

  @override
  State<PapercutPuzzlesView> createState() => _PapercutPuzzlesViewState();
}

class _PapercutPuzzlesViewState extends State<PapercutPuzzlesView>
    with TickerProviderStateMixin {
  static const _sampleId = 'papercut-samples';

  PapercutBlueprint _blueprint = papercutSampleBlueprint();
  List<CraftV1> _crafts = const [];
  late final PapercutCamera _camera;
  late final AnimationController _dolly;
  late final AnimationController _rollSettle;

  int _stepIndex = 0;
  late PapercutSheet _sheet;
  late PapercutScore _score;
  PapercutCutGraph _cutGraph = const PapercutCutGraph();
  final List<PapercutSheet> _undo = [];

  PapercutTool _tool = PapercutTool.scissors;
  StraightEdgeAction _edgeAction = StraightEdgeAction.cut;
  double _foldAngle = 90;
  bool _safeZonePanelOpen = false;
  bool _showBlueprintZones = false;
  bool _showCutZones = false;
  bool _showOutlineMeasure = false;
  bool _showGraphMeasure = false;
  bool _showNearestMeasure = false;
  bool _showIssueMeasure = false;

  Size _viewport = Size.zero;
  List<Offset>? _liveStroke;
  _Drag? _drag;

  _RotationPhase _phase = _RotationPhase.idle;
  Timer? _grace;
  Timer? _cooldown;
  _RollSweep? _sweep;
  double _rollFrom = 0;
  double _rollTo = 0;

  bool get _rotationEngaged => _phase != _RotationPhase.idle;

  PapercutStep get _step => _blueprint.steps[_stepIndex];

  bool get _canCut {
    final geometry = _step.geometry;
    return geometry is PapercutCurveGeometry && geometry.hasSheet;
  }

  bool get _onLastStep => _stepIndex >= _blueprint.steps.length - 1;

  @override
  void initState() {
    super.initState();
    _camera = PapercutCamera()..addListener(_onCamera);
    _dolly = AnimationController(
      vsync: this,
      duration: PapercutCamera.dollyDuration,
    )..addListener(() => _camera.setBlend(_dolly.value));
    _rollSettle = AnimationController(vsync: this, duration: _kRollSettle)
      ..addListener(_onRollTick)
      ..addStatusListener(_onRollStatus);
    _loadStep(0);
    _loadCrafts();
  }

  Future<void> _loadCrafts() async {
    final crafts = widget.crafts ?? await CraftV1.loadAll();
    if (!mounted) return;
    setState(() => _crafts = crafts);
  }

  void _selectCraft(String id) {
    if (id == _sampleId) {
      _blueprint = papercutSampleBlueprint();
    } else {
      final craft = _crafts.where((item) => item.craft == id).firstOrNull;
      if (craft == null) return;
      _blueprint = papercutBlueprintFromCraft(craft);
    }
    _loadStep(0);
  }

  @override
  void dispose() {
    _grace?.cancel();
    _cooldown?.cancel();
    _rollSettle.dispose();
    _dolly.dispose();
    _camera.removeListener(_onCamera);
    _camera.dispose();
    super.dispose();
  }

  void _onCamera() {
    if (mounted) setState(() {});
  }

  void _loadStep(int index) {
    _stepIndex = index.clamp(0, _blueprint.steps.length - 1);
    _sheet = _sheetFor(_step);
    _undo.clear();
    _liveStroke = null;
    _score = scorePapercutStep(_step, _sheet);
    _cutGraph = buildCutGraph(_sheet.cutStrokes);
    _camera.frameSheet(
      _viewport,
      sheetMm: _sheetSpan(),
      center: _sheetCenter(),
    );
  }

  double _sheetSpan() {
    final geometry = _step.geometry;
    if (geometry is! PapercutCurveGeometry || geometry.nets.isEmpty) {
      return kPapercutSheetMm;
    }
    final bounds = _netBounds(geometry);
    return math.max(bounds.width, bounds.height);
  }

  Offset _sheetCenter() {
    final geometry = _step.geometry;
    if (geometry is! PapercutCurveGeometry || geometry.nets.isEmpty) {
      return Offset.zero;
    }
    return _netBounds(geometry).center;
  }

  Rect _netBounds(PapercutCurveGeometry geometry) {
    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = -double.infinity;
    var maxY = -double.infinity;
    for (final net in geometry.nets) {
      for (final point in net.outer) {
        minX = math.min(minX, point.dx);
        minY = math.min(minY, point.dy);
        maxX = math.max(maxX, point.dx);
        maxY = math.max(maxY, point.dy);
      }
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  PapercutSheet _sheetFor(PapercutStep step) {
    final geometry = step.geometry;
    if (geometry is PapercutCurveGeometry && geometry.hasSheet) {
      if (geometry.nets.isNotEmpty) {
        return PapercutSheet(
          pieces: [
            for (var i = 0; i < geometry.nets.length; i++)
              PapercutPiece(
                id: 'net-$i',
                color: step.paperColor,
                vertices: geometry.nets[i].outer,
                holes: geometry.nets[i].holes,
              ),
          ],
        );
      }
      return PapercutSheet.square(color: step.paperColor);
    }
    return PapercutSheet.empty();
  }

  void _toggleCamera() {
    _camera.beginToggle();
    _dolly.forward(from: 0);
  }

  void _onRotatePressed() {
    if (_phase == _RotationPhase.idle) {
      _armRotation();
      return;
    }
    final snap =
        _phase == _RotationPhase.rotating || _phase == _RotationPhase.settling;
    _disengage(snap: snap);
  }

  void _armRotation() {
    _grace?.cancel();
    _cooldown?.cancel();
    _sweep = null;
    _drag = null;
    _liveStroke = null;
    setState(() => _phase = _RotationPhase.armed);
    _grace = Timer(_kRotationGrace, () {
      if (!mounted || _phase != _RotationPhase.armed) return;
      setState(() => _phase = _RotationPhase.idle);
    });
  }

  void _disengage({required bool snap}) {
    _grace?.cancel();
    _cooldown?.cancel();
    _sweep = null;
    _phase = _RotationPhase.idle;
    _rollSettle.stop();
    if (snap) _camera.setRoll(PapercutCamera.snapRoll(_camera.roll));
    if (mounted) setState(() {});
  }

  void _onRotationGesture(GestureState state) {
    if (_phase != _RotationPhase.armed && _phase != _RotationPhase.rotating) {
      return;
    }
    if (state.pointers.isEmpty) {
      // Trackpad pan-zoom has no touch points; it must not scale or end a roll.
      if (state.type != GestureType.idle) return;
      if (_phase == _RotationPhase.rotating) _beginSettle();
      return;
    }

    final center = Offset(_viewport.width / 2, _viewport.height / 2);
    final angle = PapercutCamera.rotationAngle(state.positions, center);
    if (_phase == _RotationPhase.armed) {
      final multi = state.pointerCount >= 2;
      final dragged = state.pointerCount == 1 && state.type.isDrag;
      if (!multi && !dragged) return;
      if (angle == null) return;
      final start = state.pointerCount == 1
          ? PapercutCamera.rotationAngle([
                  state.pointers.single.initialPosition,
                ], center) ??
                angle
          : angle;
      _grace?.cancel();
      _sweep = _RollSweep(
        baseRoll: _camera.roll,
        pointerCount: state.pointerCount,
        angle: start,
      );
      _phase = _RotationPhase.rotating;
      _sweep!.apply(_camera, angle);
      return;
    }

    final sweep = _sweep;
    if (sweep == null || angle == null) return;
    if (state.pointerCount != sweep.pointerCount) {
      sweep.rebaseline(_camera.roll, state.pointerCount, angle);
      return;
    }
    sweep.apply(_camera, angle);
  }

  void _beginSettle() {
    _sweep = null;
    _rollFrom = _camera.roll;
    _rollTo = PapercutCamera.snapRoll(_rollFrom);
    _phase = _RotationPhase.settling;
    if ((_rollTo - _rollFrom).abs() < 1e-4) {
      _camera.setRoll(_rollTo);
      _scheduleCooldown();
      return;
    }
    _rollSettle.forward(from: 0);
  }

  void _onRollTick() {
    if (_phase != _RotationPhase.settling) return;
    final t = Curves.easeOutCubic.transform(_rollSettle.value);
    _camera.setRoll(_rollFrom + (_rollTo - _rollFrom) * t);
  }

  void _onRollStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (_phase != _RotationPhase.settling) return;
    _scheduleCooldown();
  }

  void _scheduleCooldown() {
    if (_phase == _RotationPhase.idle) return;
    _phase = _RotationPhase.cooldown;
    _cooldown?.cancel();
    _cooldown = Timer(_kRotationCooldown, () {
      if (!mounted || _phase != _RotationPhase.cooldown) return;
      setState(() => _phase = _RotationPhase.idle);
    });
    if (mounted) setState(() {});
  }

  void _onScaleStart(ScaleStartDetails details) {
    if (_rotationEngaged) return;
    _drag = _Drag(details.localFocalPoint);
  }

  void _onScaleUpdate(ScaleUpdateDetails details) {
    if (_rotationEngaged) return;
    final drag = _drag;
    if (drag == null) return;
    final local = details.localFocalPoint;
    final delta = local - drag.lastFocal;
    drag.lastFocal = local;

    final scaleChanged = (details.scale - drag.lastScale).abs() > 1e-4;
    if (details.pointerCount >= 2 || (scaleChanged && details.pointerCount != 1)) {
      drag.pinching = true;
      if (_tool != PapercutTool.exacto) {
        _camera.zoomByScale(details.scale / drag.lastScale);
      }
      drag.lastScale = details.scale;
      return;
    }

    drag.moved += delta.distance;
    if (_tool == PapercutTool.exacto) {
      if (!_canCut) return;
      drag.stroke.add(local);
      setState(() => _liveStroke = List<Offset>.of(drag.stroke));
      return;
    }
    if (drag.moved > _kTapSlop) {
      drag.panned = true;
      _camera.panByScreen(delta, _viewport);
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (_rotationEngaged || event is! PointerScrollEvent) return;
    if (event.scrollDelta.dy == 0) return;
    _camera.zoomByScale(math.exp(-event.scrollDelta.dy * 0.002));
  }

  void _onScaleEnd(ScaleEndDetails details) {
    if (_rotationEngaged) return;
    final drag = _drag;
    _drag = null;
    if (_liveStroke != null) setState(() => _liveStroke = null);
    if (drag == null || !_canCut) return;
    if (_tool == PapercutTool.exacto) {
      if (!drag.pinching) _commitExacto(drag.stroke);
      return;
    }
    if (drag.panned || drag.pinching || drag.moved > _kTapSlop) return;
    if (_tool == PapercutTool.scissors) {
      final plan = _scissorPlan;
      if (plan != null) _commitCut(plan.stroke, join: false);
    } else if (_tool == PapercutTool.straightEdge) {
      _commitStraightEdge();
    }
  }

  (Offset, Offset) _scissorScreen() {
    return (
      Offset(_viewport.width / 2, _viewport.height),
      Offset(_viewport.width / 2, _viewport.height / 2),
    );
  }

  (Offset, Offset) _rulerScreen() {
    final y = _viewport.height / 2;
    return (Offset(0, y), Offset(_viewport.width, y));
  }

  List<Offset>? _planeSegment((Offset, Offset) screen) {
    final a = _camera.planePoint(screen.$1, _viewport);
    final b = _camera.planePoint(screen.$2, _viewport);
    if (a == null || b == null) return null;
    return [a, b];
  }

  void _commitExacto(List<Offset> screenStroke) {
    final smoothed = smoothOffsets(screenStroke);
    final world = <Offset>[];
    for (final point in smoothed) {
      final hit = _camera.planePoint(point, _viewport);
      if (hit != null) world.add(hit);
    }
    _commitCut(resampleOffsets(world, 2));
  }

  void _commitCut(List<Offset>? world, {bool join = true}) {
    if (world == null) return;
    final stroke = join ? connectNewCut(world, _sheet.cutStrokes) : world;
    final next = applyPapercutCut(_sheet, stroke);
    if (next == null) return;
    _pushUndo();
    setState(() {
      _sheet = next;
      _score = scorePapercutStep(_step, _sheet);
      _cutGraph = buildCutGraph(_sheet.cutStrokes);
    });
  }

  void _commitStraightEdge() {
    final world = _planeSegment(_rulerScreen());
    if (world == null) return;
    if (_edgeAction == StraightEdgeAction.cut) {
      _commitCut(world);
      return;
    }
    final next = applyPapercutCrease(
      _sheet,
      a: world[0],
      b: world[1],
      groupId: 'fold-${_sheet.creases.length}',
      angleDegrees: _foldAngle,
    );
    if (next == null) return;
    _pushUndo();
    setState(() => _sheet = next);
  }

  void _pushUndo() {
    _undo.add(_sheet.clone());
    if (_undo.length > 40) _undo.removeAt(0);
  }

  void _undoLast() {
    if (_undo.isEmpty) return;
    setState(() {
      _sheet = _undo.removeLast();
      _score = scorePapercutStep(_step, _sheet);
      _cutGraph = buildCutGraph(_sheet.cutStrokes);
    });
  }

  ScissorCutPlan? get _scissorPlan {
    if (!_canCut || _viewport.width < 2 || _viewport.height < 2) return null;
    final segment = _planeSegment(_scissorScreen());
    if (segment == null) return null;
    return planScissorCut(segment, _sheet);
  }

  bool get _measureOn =>
      _showOutlineMeasure ||
      _showGraphMeasure ||
      _showNearestMeasure ||
      _showIssueMeasure ||
      _safeZonePanelOpen;

  PapercutMeasure? get _measure {
    if (!_measureOn) return null;
    return buildPapercutMeasure(_step, _sheet);
  }

  String get _status {
    if (_step.geometry is PapercutMeshGeometry) return 'Mesh step';
    if (_score.passed) return 'Close enough';
    return _score.reason ?? 'Cut the outlines';
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: kPapercutBackground,
      overlays: const [FmDevBackButton()],
      background: LayoutBuilder(
        builder: (context, constraints) {
          _viewport = Size(constraints.maxWidth, constraints.maxHeight);
          _camera.ensureFramed(_viewport, sheetMm: kPapercutSheetMm);
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                child: GestureClassifier(
                  onGestureUpdate: _onRotationGesture,
                  child: Listener(
                    onPointerSignal: _onPointerSignal,
                    child: GestureDetector(
                    key: const Key('papercut-canvas'),
                    behavior: HitTestBehavior.opaque,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: CustomPaint(
                      painter: PapercutPainter(
                        camera: _camera,
                        step: _step,
                        sheet: _sheet,
                        showScissors: _tool == PapercutTool.scissors && _canCut,
                        scissorsAllowed: _scissorPlan != null,
                        scissorJoint: _scissorPlan?.joint,
                        cutJoints: _cutGraph.joints,
                        showRuler:
                            _tool == PapercutTool.straightEdge && _canCut,
                        showBlueprintZones: _showBlueprintZones,
                        showCutZones: _showCutZones,
                        measure: _measure,
                        showOutlineMeasure: _showOutlineMeasure,
                        showGraphMeasure: _showGraphMeasure,
                        showNearestMeasure: _showNearestMeasure,
                        showIssueMeasure: _showIssueMeasure,
                        liveStroke: _liveStroke,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                  ),
                ),
              ),
              FmSafePositioned(
                top: 8,
                left: 96,
                right: 12,
                child: _buildHeader(),
              ),
              FmSafePositioned(
                left: 0,
                right: 0,
                bottom: 8,
                child: Padding(
                  padding: const EdgeInsets.only(right: 72),
                  child: _buildToolbar(),
                ),
              ),
              FmSafePositioned(
                right: 8,
                bottom: 8,
                child: _buildTransformControls(),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _buildCraftDropdown(),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildDropdown()),
            const SizedBox(width: 8),
            if (_score.passed && !_onLastStep)
              TextButton(
                key: const Key('papercut-next'),
                onPressed: () => setState(() => _loadStep(_stepIndex + 1)),
                child: const Text('Next'),
              )
            else if (_score.passed)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8),
                child: Text('Complete', style: TextStyle(color: Colors.white)),
              ),
            IconButton(
              tooltip: 'Dev tools',
              onPressed: () => setState(() {
                _safeZonePanelOpen = !_safeZonePanelOpen;
                if (_safeZonePanelOpen &&
                    !_showOutlineMeasure &&
                    !_showGraphMeasure &&
                    !_showNearestMeasure &&
                    !_showIssueMeasure) {
                  _showOutlineMeasure = true;
                  _showGraphMeasure = true;
                  _showNearestMeasure = true;
                  _showIssueMeasure = true;
                }
              }),
              icon: Icon(
                Icons.tune,
                color: _safeZonePanelOpen ? Colors.white : Colors.white70,
              ),
            ),
          ],
        ),
        if (_safeZonePanelOpen) _buildSafeZonePanel(),
      ],
    );
  }

  Widget _buildSafeZonePanel() {
    return Container(
      width: 220,
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xF01A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _zoneSwitch(
            'Blueprint',
            _showBlueprintZones,
            (value) => setState(() => _showBlueprintZones = value),
          ),
          _zoneSwitch(
            'Cuts',
            _showCutZones,
            (value) => setState(() => _showCutZones = value),
          ),
          const Divider(color: Colors.white24, height: 16),
          _measureSwitch(
            'Outline',
            const Color(0xFF4FC3F7),
            _showOutlineMeasure,
            (value) => setState(() => _showOutlineMeasure = value),
          ),
          _measureSwitch(
            'Graph',
            const Color(0xFFFFB74D),
            _showGraphMeasure,
            (value) => setState(() => _showGraphMeasure = value),
          ),
          _measureSwitch(
            'Nearest',
            const Color(0xFF69F0AE),
            _showNearestMeasure,
            (value) => setState(() => _showNearestMeasure = value),
          ),
          _measureSwitch(
            'Issues',
            const Color(0xFFFF5252),
            _showIssueMeasure,
            (value) => setState(() => _showIssueMeasure = value),
          ),
          if (_measure != null && _measure!.outlines.isNotEmpty) ...[
            const SizedBox(height: 4),
            const Text(
              'outline / counted',
              style: TextStyle(color: Colors.white38, fontSize: 11),
            ),
            for (final row in _measure!.outlines)
              Text(
                '${row.outlineMm} / ${row.countedMm}',
                style: TextStyle(
                  color: row.off ? const Color(0xFFFF5252) : Colors.white,
                  fontSize: 13,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _measureSwitch(
    String label,
    Color color,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _zoneSwitch(String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(label, style: const TextStyle(color: Colors.white70)),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }

  Widget _buildCraftDropdown() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            key: const Key('papercut-craft-dropdown'),
            isExpanded: true,
            isDense: true,
            dropdownColor: const Color(0xFF1A1A1A),
            value: _blueprint.id,
            items: [
              const DropdownMenuItem(
                value: _sampleId,
                child: Text(
                  'Papercut samples',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
              for (final craft in _crafts)
                DropdownMenuItem(
                  value: craft.craft,
                  child: Text(
                    craft.craft,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
            onChanged: (id) {
              if (id == null) return;
              setState(() => _selectCraft(id));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildDropdown() {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<int>(
            key: const Key('papercut-step-dropdown'),
            isExpanded: true,
            isDense: true,
            dropdownColor: const Color(0xFF1A1A1A),
            value: _stepIndex,
            items: [
              for (var i = 0; i < _blueprint.steps.length; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(
                    _blueprint.steps[i].label,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
            ],
            onChanged: (index) {
              if (index == null) return;
              setState(() => _loadStep(index));
            },
          ),
        ),
      ),
    );
  }

  Widget _buildTransformControls() {
    return _circleButton(
      key: const Key('papercut-rotate'),
      icon: Icons.rotate_right,
      label: 'Rotate',
      selected: _rotationEngaged,
      onTap: _onRotatePressed,
    );
  }

  Widget _buildToolbar() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _status,
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_tool == PapercutTool.straightEdge && _canCut) _buildEdgeMenu(),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _toolButton(
              tool: PapercutTool.scissors,
              icon: Icons.content_cut,
              label: 'Scissors',
            ),
            _toolButton(
              tool: PapercutTool.exacto,
              icon: Icons.gesture,
              label: 'Exacto',
            ),
            _toolButton(
              tool: PapercutTool.straightEdge,
              icon: Icons.straighten,
              label: 'Straight edge',
            ),
            _circleButton(
              icon: Icons.undo,
              label: 'Undo',
              selected: false,
              enabled: _undo.isNotEmpty,
              onTap: _undoLast,
            ),
            _circleButton(
              icon: Icons.threed_rotation,
              label: _camera.targetFlat ? 'Perspective' : 'Flat',
              selected: !_camera.targetFlat,
              onTap: _toggleCamera,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEdgeMenu() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _circleButton(
            icon: Icons.content_cut,
            label: 'Cut',
            selected: _edgeAction == StraightEdgeAction.cut,
            onTap: () => setState(() => _edgeAction = StraightEdgeAction.cut),
          ),
          _circleButton(
            icon: Icons.architecture,
            label: 'Fold',
            selected: _edgeAction == StraightEdgeAction.fold,
            onTap: () => setState(() => _edgeAction = StraightEdgeAction.fold),
          ),
          if (_edgeAction == StraightEdgeAction.fold) ...[
            _circleButton(
              icon: Icons.north,
              label: '+90 toward camera',
              selected: _foldAngle > 0,
              onTap: () => setState(() => _foldAngle = 90),
            ),
            _circleButton(
              icon: Icons.south,
              label: '-90 away from camera',
              selected: _foldAngle < 0,
              onTap: () => setState(() => _foldAngle = -90),
            ),
          ],
        ],
      ),
    );
  }

  Widget _toolButton({
    required PapercutTool tool,
    required IconData icon,
    required String label,
  }) {
    return _circleButton(
      icon: icon,
      label: label,
      selected: _tool == tool,
      onTap: () => setState(() => _tool = tool),
    );
  }

  Widget _circleButton({
    Key? key,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return SizedBox(
      key: key,
      width: 56,
      height: 72,
      child: HudToolButton(
        icon: icon,
        label: label,
        fill: kHudSelectFill,
        selected: selected,
        enabled: enabled,
        onTap: onTap,
      ),
    );
  }
}

class _RollSweep {
  _RollSweep({
    required this.baseRoll,
    required this.pointerCount,
    required double angle,
  }) : start = angle,
       unwrapped = angle;

  double baseRoll;
  int pointerCount;
  double start;
  double unwrapped;

  void rebaseline(double roll, int count, double angle) {
    baseRoll = roll;
    pointerCount = count;
    start = angle;
    unwrapped = angle;
  }

  void apply(PapercutCamera camera, double angle) {
    unwrapped = PapercutCamera.advanceAngle(unwrapped, angle);
    camera.setRoll(
      PapercutCamera.rollAfterScreenSweep(
        baseRoll: baseRoll,
        startAngle: start,
        currentAngle: unwrapped,
      ),
    );
  }
}

class _Drag {
  _Drag(this.lastFocal) : stroke = [lastFocal];

  Offset lastFocal;
  double moved = 0;
  bool panned = false;
  bool pinching = false;
  double lastScale = 1;
  final List<Offset> stroke;
}
