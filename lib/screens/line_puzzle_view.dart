import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;

import '../linepuzzle/line_puzzle_models.dart';
import '../linepuzzle/line_puzzle_painter.dart';
import '../linepuzzle/line_puzzle_puzzles.dart';
import '../linepuzzle/line_puzzle_rules.dart';
import '../papercut/camera.dart';
import '../ui/fm_dev_back_button.dart';
import '../ui/fm_haptics.dart';
import '../ui/fm_screen.dart';

/// Witness-style tool path on the crafting sheet.
class LinePuzzleView extends StatefulWidget {
  const LinePuzzleView({super.key});

  @override
  State<LinePuzzleView> createState() => _LinePuzzleViewState();
}

class _Contact {
  _Contact(this.origin) : current = origin, previous = origin;

  final Offset origin;
  Offset current;
  Offset previous;
  bool dragged = false;
}

class _LinePuzzleViewState extends State<LinePuzzleView>
    with TickerProviderStateMixin {
  static const double _slop = 10;
  static const double _startReach = 40;

  late final PapercutCamera _camera;
  late final AnimationController _glide;
  late final AnimationController _spring;
  late final AnimationController _failFlash;

  late LineSession _session;
  int _index = 0;
  Size _viewport = Size.zero;
  double _baseHalf = 0;
  bool _frameQueued = false;

  Offset _slack = Offset.zero;
  LinePeg? _peg;
  bool _springing = false;
  double _springFromT = 0;
  LinePoint? _springToward;
  Offset _browseLook = Offset.zero;
  double _browseHalf = 0;
  Offset _fromLook = Offset.zero;
  Offset _toLook = Offset.zero;
  double _fromHalf = 0;
  double _toHalf = 0;

  final Map<int, _Contact> _contacts = {};

  @override
  void initState() {
    super.initState();
    _camera = PapercutCamera()..addListener(_rebuild);
    _glide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    )..addListener(_onGlide);
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    )..addListener(_onSpring);
    _failFlash =
        AnimationController(
            vsync: this,
            duration: const Duration(milliseconds: 720),
          )
          ..addListener(_rebuild)
          ..addStatusListener(_onFailDone);
    _session = LineSession.start(kLinePuzzles.first);
  }

  @override
  void dispose() {
    _camera.removeListener(_rebuild);
    _camera.dispose();
    _glide.dispose();
    _spring.dispose();
    _failFlash.dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  void _onGlide() {
    final t = Curves.easeOutCubic.transform(_glide.value);
    _camera.moveLook(
      lookAt: Offset.lerp(_fromLook, _toLook, t)!,
      halfHeight: _fromHalf + (_toHalf - _fromHalf) * t,
    );
  }

  void _onFailDone(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _session.phase != LinePhase.failed) return;
      _load(_index);
    });
  }

  void _glideTo(Offset look, double half) {
    if (half <= 0) return;
    _fromLook = _camera.lookAt;
    _fromHalf = _camera.framedHalfHeightMm;
    _toLook = look;
    _toHalf = half;
    _glide.forward(from: 0);
  }

  void _centerOnHead() {
    final head = _session.head;
    if (head == null || _baseHalf <= 0) return;
    _glideTo(head.offset, _camera.framedHalfHeightMm);
  }

  void _onSpring() {
    if (!_springing || _peg == null) return;
    final travel = Curves.easeOutCubic.transform(_spring.value);
    final t = _springFromT * (1 - travel);
    final anchors = _session.phase == LinePhase.drawing
        ? _session.strokes.last.points
        : _peg!.anchors;
    _peg = LinePeg(
      anchors: anchors,
      toward: t <= 0.001 ? null : _springToward,
      t: t,
    );
    if (t <= 0.001) _springing = false;
    setState(() {});
  }

  void _beginSpring() {
    final peg = _peg;
    if (peg == null || peg.atAnchor) return;
    _springFromT = peg.t;
    _springToward = peg.toward;
    _springing = true;
    _spring.forward(from: 0);
  }

  void _frameBase() {
    if (_viewport.width < 2 || _viewport.height < 2) return;
    final paper = _session.puzzle.bounds.rect;
    final sheet = math.max(paper.width, paper.height);
    _camera.frameSheet(_viewport, sheetMm: sheet, center: paper.center);
    _baseHalf = _camera.framedHalfHeightMm;
    _browseLook = paper.center;
    _browseHalf = _baseHalf;
  }

  void _load(int index) {
    _failFlash.stop();
    _failFlash.value = 0;
    _glide.stop();
    _springing = false;
    _spring.stop();
    _slack = Offset.zero;
    _peg = null;
    _contacts.clear();
    setState(() {
      _index = index;
      _session = LineSession.start(kLinePuzzles[index]);
      _baseHalf = 0;
    });
  }

  void _applySession(LineSession next) {
    if (identical(next, _session)) return;
    final prev = _session;
    final entered =
        next.phase == LinePhase.drawing && prev.phase != LinePhase.drawing;
    if (entered) {
      if (_glide.isAnimating) {
        _browseLook = _toLook;
        _browseHalf = _toHalf;
        _glide.stop();
      } else {
        _browseLook = _camera.lookAt;
        _browseHalf = _camera.framedHalfHeightMm;
      }
    }
    setState(() {
      _session = next;
      if (next.phase != LinePhase.drawing) {
        _peg = null;
        _springing = false;
      }
    });
    if (next.phase != LinePhase.drawing) _spring.stop();
    if (next.phase == LinePhase.failed && prev.phase != LinePhase.failed) {
      _failFlash.forward(from: 0);
      fmHaptic(FmHapticStyle.heavyImpact);
    } else if (next.phase == LinePhase.solved &&
        prev.phase != LinePhase.solved) {
      fmHaptic(FmHapticStyle.heavyImpact);
      if (_baseHalf > 0) {
        _glideTo(_session.puzzle.bounds.rect.center, _baseHalf);
      }
    } else if (next.phase == LinePhase.paused &&
        prev.phase == LinePhase.drawing) {
      fmHaptic(FmHapticStyle.lightImpact);
      _glideTo(_browseLook, _browseHalf);
    } else if (next.phase == LinePhase.drawing || next.tool != prev.tool) {
      fmHaptic(FmHapticStyle.selectionClick);
    }
  }

  Offset? get _tip {
    final peg = _peg;
    if (peg == null || peg.atAnchor) return null;
    return peg.tip;
  }

  void _down(PointerDownEvent event) {
    _springing = false;
    _spring.stop();
    _contacts[event.pointer] = _Contact(event.localPosition);
  }

  void _move(PointerMoveEvent event) {
    final contact = _contacts[event.pointer];
    if (contact == null || _session.phase == LinePhase.failed) return;
    contact.previous = contact.current;
    contact.current = event.localPosition;
    if ((contact.current - contact.origin).distance > _slop) {
      contact.dragged = true;
    }
    if (_contacts.length >= 2) {
      _pinch();
      return;
    }
    if (!contact.dragged) return;
    if (_session.phase == LinePhase.drawing) {
      _dragLine(contact.previous, contact.current);
      return;
    }
    if (_session.phase == LinePhase.browse ||
        _session.phase == LinePhase.paused) {
      final dot = _edgeStartNear(contact.origin);
      if (dot != null) {
        final began = beginStroke(_session, dot);
        if (!identical(began, _session)) {
          _slack = Offset.zero;
          _peg = LinePeg(anchors: began.strokes.last.points);
          _applySession(began);
          _dragLine(contact.origin, contact.current);
          return;
        }
      }
    }
    _pan(contact.current - contact.previous);
  }

  void _up(PointerUpEvent event) {
    final contact = _contacts.remove(event.pointer);
    if (contact == null) return;
    final alone = _contacts.isEmpty;
    if (alone && !contact.dragged && _session.phase != LinePhase.failed) {
      _onTap(contact.current);
    }
    if (alone && _session.phase == LinePhase.drawing) {
      _slack = Offset.zero;
      _centerOnHead();
      _beginSpring();
    }
  }

  void _cancel(PointerCancelEvent event) {
    _contacts.remove(event.pointer);
    if (_contacts.isNotEmpty || _session.phase != LinePhase.drawing) return;
    _slack = Offset.zero;
    _centerOnHead();
    _beginSpring();
  }

  void _signal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_session.phase == LinePhase.drawing ||
        _session.phase == LinePhase.failed) {
      return;
    }
    if (event.scrollDelta.dy.abs() < 0.1) return;
    _zoom(event.scrollDelta.dy > 0 ? 0.92 : 1.08);
  }

  void _pinch() {
    if (_session.phase == LinePhase.drawing ||
        _session.phase == LinePhase.failed) {
      return;
    }
    final pts = _contacts.values.toList();
    if (pts.length < 2) return;
    final prevSpan = (pts[0].previous - pts[1].previous).distance;
    final nowSpan = (pts[0].current - pts[1].current).distance;
    if (prevSpan > 12 && nowSpan > 12) _zoom(nowSpan / prevSpan);
    final prevMid = (pts[0].previous + pts[1].previous) / 2;
    final nowMid = (pts[0].current + pts[1].current) / 2;
    _pan(nowMid - prevMid);
  }

  void _pan(Offset delta) {
    if (delta == Offset.zero || _viewport.width < 2) return;
    _glide.stop();
    _camera.panByScreen(delta, _viewport);
    if (_session.phase != LinePhase.drawing) {
      _browseLook = _camera.lookAt;
      _browseHalf = _camera.framedHalfHeightMm;
    }
  }

  void _zoom(double scale) {
    if (_baseHalf <= 0 || _session.phase == LinePhase.drawing) return;
    _glide.stop();
    final next = (_camera.framedHalfHeightMm / scale).clamp(
      _baseHalf / 3,
      _baseHalf,
    );
    _browseHalf = next;
    _camera.moveLook(lookAt: _camera.lookAt, halfHeight: next);
  }

  void _dragLine(Offset from, Offset to) {
    if (_viewport.width < 2 || _session.phase != LinePhase.drawing) return;
    final peg = _peg;
    if (peg == null) return;
    final start = _camera.planePoint(from, _viewport);
    final end = _camera.planePoint(to, _viewport);
    if (start == null || end == null) return;
    _slack += end - start;
    final result = movePeg(_session, peg, _slack);
    _slack = result.slack;
    final drawing = result.session.phase == LinePhase.drawing;
    _peg = drawing ? result.peg : null;
    if (!identical(result.session, _session)) {
      _applySession(result.session);
    } else {
      setState(() {});
    }
  }

  void _onTap(Offset local) {
    if (_viewport.width < 2 || _session.phase == LinePhase.solved) return;
    final dot = _dotNear(local);
    if (dot == null) return;
    if (_session.phase == LinePhase.drawing) {
      final peg = _peg;
      if (peg == null || !peg.atAnchor) return;
      final head = _session.head;
      if (head == null) return;
      if ((dot.x - head.x).abs() + (dot.y - head.y).abs() != 1) return;
      final next = step(_session, dot);
      if (identical(next, _session)) return;
      if (next.phase == LinePhase.drawing) {
        _peg = LinePeg(anchors: next.strokes.last.points);
      }
      _applySession(next);
      _centerOnHead();
      return;
    }
    final began = beginStroke(_session, dot);
    if (identical(began, _session)) return;
    _peg = LinePeg(anchors: began.strokes.last.points);
    _applySession(began);
  }

  LinePoint? _edgeStartNear(Offset local) {
    final world = _camera.planePoint(local, _viewport);
    final puzzle = _session.puzzle;
    final bounds = puzzle.bounds;
    LinePoint? best;
    var bestPx = _startReach;
    for (var x = bounds.left; x <= bounds.right; x++) {
      for (var y = bounds.top; y <= bounds.bottom; y++) {
        final point = LinePoint(x, y);
        if (!puzzle.isEdgeDot(point)) continue;
        if (lineVisits(_session, point) >= puzzle.budget(point)) continue;
        final screen = _camera.camera.projectToScreen(
          Vector3(x.toDouble(), y.toDouble(), 0),
          _viewport,
        );
        if (screen == null) continue;
        final pixels = (screen - local).distance;
        if (pixels >= bestPx) continue;
        if (world != null && (world - point.offset).distance > 0.75) continue;
        bestPx = pixels;
        best = point;
      }
    }
    return best;
  }

  LinePoint? _dotNear(Offset local) {
    final puzzle = _session.puzzle;
    final bounds = puzzle.bounds;
    LinePoint? best;
    var bestPx = 28.0;
    for (var x = bounds.left; x <= bounds.right; x++) {
      for (var y = bounds.top; y <= bounds.bottom; y++) {
        final point = LinePoint(x, y);
        if (!puzzle.hasDot(point)) continue;
        final screen = _camera.camera.projectToScreen(
          Vector3(x.toDouble(), y.toDouble(), 0),
          _viewport,
        );
        if (screen == null) continue;
        final dist = (screen - local).distance;
        if (dist < bestPx) {
          bestPx = dist;
          best = point;
        }
      }
    }
    return best;
  }

  void _pickTool(LineTool tool) {
    _applySession(setTool(_session, tool));
  }

  @override
  Widget build(BuildContext context) {
    return FmScreen(
      backgroundColor: const Color(0xFF12141C),
      overlays: const [FmDevBackButton()],
      content: Column(
        children: [
          _topBar(),
          Expanded(child: _board()),
          _toolBar(),
        ],
      ),
    );
  }

  Widget _topBar() {
    final puzzle = _session.puzzle;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 72),
            child: Row(
              children: [
                for (var i = 0; i < kLinePuzzles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  _pill(kLinePuzzles[i].title, i),
                ],
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _status(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
          ),
          Text(
            puzzle.blurb,
            style: const TextStyle(color: Colors.white60, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _status() {
    final tool = _session.tool == LineTool.fold ? 'Fold' : 'Cut';
    return switch (_session.phase) {
      LinePhase.failed => 'That breaks the puzzle',
      LinePhase.solved => 'Solved',
      LinePhase.paused => 'Paused — pick a tool, then drag from an edge',
      LinePhase.drawing => 'Drag to draw. Release snaps back to the last dot',
      LinePhase.browse => 'Drag from an edge dot to start a $tool',
    };
  }

  Widget _pill(String label, int index) {
    final selected = index == _index;
    return GestureDetector(
      onTap: () => _load(index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFC107) : const Color(0xFF1E2333),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFFFC107) : Colors.white24,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.black : Colors.white70,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }

  Widget _board() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        _viewport = size;
        if (_baseHalf == 0 &&
            size.width > 2 &&
            size.height > 2 &&
            !_frameQueued) {
          _frameQueued = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _frameQueued = false;
            if (!mounted) return;
            _frameBase();
            setState(() {});
          });
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: _down,
              onPointerMove: _move,
              onPointerUp: _up,
              onPointerCancel: _cancel,
              onPointerSignal: _signal,
              child: CustomPaint(
                painter: LinePuzzlePainter(
                  session: _session,
                  camera: _camera,
                  failureFlash: _failFlash.value,
                  tip: _tip,
                ),
                child: const SizedBox.expand(),
              ),
            ),
            if (_session.phase == LinePhase.paused)
              const IgnorePointer(child: ColoredBox(color: Color(0x66101422))),
            if (_session.phase == LinePhase.paused ||
                _session.phase == LinePhase.solved)
              Align(
                alignment: const Alignment(0, -0.72),
                child: IgnorePointer(child: _banner()),
              ),
          ],
        );
      },
    );
  }

  Widget _banner() {
    final solved = _session.phase == LinePhase.solved;
    final color = solved ? kLineCut : kLineFold;
    final label = solved ? 'Solved' : 'Paused';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xF01B202D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color, width: 1.4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _toolBar() {
    final enabled = _session.canSwitchTool;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF131722),
        border: Border(top: BorderSide(color: Colors.white12)),
      ),
      child: Row(
        children: [
          _toolButton(LineTool.cut, 'Cut', kLineCut, enabled),
          const SizedBox(width: 8),
          _toolButton(LineTool.fold, 'Fold', kLineFold, enabled),
          const Spacer(),
          TextButton(
            onPressed: () => _load(_index),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
  }

  Widget _toolButton(LineTool tool, String label, Color color, bool enabled) {
    final selected = _session.tool == tool;
    final background = selected ? color : const Color(0xFF1E2333);
    final foreground = selected && tool == LineTool.fold
        ? Colors.black
        : Colors.white;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? () => _pickTool(tool) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: selected ? color : Colors.white24),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: foreground,
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }
}
