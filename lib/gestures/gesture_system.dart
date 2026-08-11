import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

const double kDragSlopThreshold = 10.0;
const Duration kClickTimeout = Duration(milliseconds: 500);

enum GestureType {
  idle,
  oneFingerClick,
  oneFingerHold,
  oneFingerDrag,
  twoFingerHold,
  twoFingerDrag,
  threeFingerHold,
  threeFingerDrag,
}

extension GestureTypeLabel on GestureType {
  String get label => switch (this) {
        GestureType.idle => 'Idle',
        GestureType.oneFingerClick => '1-Finger Click',
        GestureType.oneFingerHold => '1-Finger Hold',
        GestureType.oneFingerDrag => '1-Finger Drag',
        GestureType.twoFingerHold => '2-Finger Hold',
        GestureType.twoFingerDrag => '2-Finger Drag',
        GestureType.threeFingerHold => '3+ Finger Hold',
        GestureType.threeFingerDrag => '3+ Finger Drag',
      };

  bool get isClick => this == GestureType.oneFingerClick;

  bool get isDrag =>
      this == GestureType.oneFingerDrag ||
      this == GestureType.twoFingerDrag ||
      this == GestureType.threeFingerDrag;

  bool get isHold =>
      this == GestureType.oneFingerHold ||
      this == GestureType.twoFingerHold ||
      this == GestureType.threeFingerHold;
}

class PointerSnapshot {
  const PointerSnapshot({
    required this.pointerId,
    required this.position,
    required this.initialPosition,
    required this.displacement,
    required this.totalDistance,
    required this.hasMoved,
  });

  final int pointerId;
  final Offset position;
  final Offset initialPosition;

  /// Straight-line distance from anchor (resets on finger-count change).
  final double displacement;
  final double totalDistance;
  final bool hasMoved;
}

class GestureState {
  const GestureState({
    required this.type,
    required this.pointers,
    required this.focalPoint,
    this.focalDelta = Offset.zero,
    this.span = 0,
    this.spanScale = 1,
  });

  static const idle = GestureState(
    type: GestureType.idle,
    pointers: [],
    focalPoint: Offset.zero,
  );

  final GestureType type;
  final List<PointerSnapshot> pointers;
  final Offset focalPoint;
  final Offset focalDelta;

  /// Distance between the first two pointers (0 if fewer than two).
  final double span;

  /// [span] / span at the start of the current multi-touch episode (1 if N/A).
  /// Prefer this over frame-to-frame scale ratios to avoid jitter accumulation.
  final double spanScale;

  int get pointerCount => pointers.length;
  List<Offset> get positions => pointers.map((p) => p.position).toList();
}

/// Tracks raw pointer events on [child] and classifies them into high-level
/// [GestureType] values (click, hold, and drag for 1/2/3+ fingers).
///
/// A single-finger touch starts as [GestureType.oneFingerClick]. If it stays
/// within [dragSlopThreshold] for longer than [clickTimeout] it becomes a
/// hold. If it moves beyond the threshold at any point it becomes a drag.
/// Multi-finger touches skip the click phase entirely and start as holds.
///
/// Drag detection uses *displacement* (straight-line distance from the anchor
/// point) rather than cumulative distance, so natural finger jitter during a
/// hold won't trigger a drag.
class GestureClassifier extends StatefulWidget {
  const GestureClassifier({
    required this.child,
    this.onGestureUpdate,
    this.dragSlopThreshold = kDragSlopThreshold,
    this.clickTimeout = kClickTimeout,
    super.key,
  });

  final Widget child;
  final ValueChanged<GestureState>? onGestureUpdate;
  final double dragSlopThreshold;
  final Duration clickTimeout;

  @override
  State<GestureClassifier> createState() => _GestureClassifierState();
}

class _GestureClassifierState extends State<GestureClassifier> {
  final Map<int, _PointerTracker> _pointers = {};
  Offset _lastFocalPoint = Offset.zero;
  Timer? _holdTimer;
  int _lastPointerCount = 0;
  double _gestureStartSpan = 0;

  // Trackpad / Magic Mouse pan-zoom (synthetic two-finger gesture).
  bool _panZoomActive = false;
  Offset _panZoomFocal = Offset.zero;
  double _panZoomScale = 1;

  @override
  void dispose() {
    _holdTimer?.cancel();
    super.dispose();
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_panZoomActive) return;
    _pointers[event.pointer] = _PointerTracker(
      pointerId: event.pointer,
      position: event.localPosition,
    );
    _resetAllMovement();
    _restartHoldTimer();
    _classify();
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_panZoomActive) return;
    final tracker = _pointers[event.pointer];
    if (tracker == null) return;
    tracker.update(event.localPosition);
    _classify();
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_panZoomActive) return;
    _pointers.remove(event.pointer);
    _resetAllMovement();
    _restartHoldTimer();
    _classify();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_panZoomActive) return;
    _pointers.remove(event.pointer);
    _resetAllMovement();
    _restartHoldTimer();
    _classify();
  }

  void _onPanZoomStart(PointerPanZoomStartEvent event) {
    _pointers.clear();
    _holdTimer?.cancel();
    _holdTimer = null;
    _panZoomActive = true;
    _panZoomFocal = event.localPosition;
    _panZoomScale = 1;
    _lastFocalPoint = _panZoomFocal;
    _lastPointerCount = 2;
    _gestureStartSpan = 1;
    _emitPanZoom();
  }

  void _onPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!_panZoomActive) return;
    _panZoomFocal = event.localPosition;
    // `scale` is cumulative from pan-zoom start; treat it as spanScale directly.
    _panZoomScale = event.scale <= 0 ? 1.0 : event.scale;
    _emitPanZoom();
  }

  void _onPanZoomEnd(PointerPanZoomEndEvent event) {
    if (!_panZoomActive) return;
    _panZoomActive = false;
    _panZoomScale = 1;
    _lastPointerCount = 0;
    _gestureStartSpan = 0;
    _lastFocalPoint = Offset.zero;
    widget.onGestureUpdate?.call(GestureState.idle);
  }

  void _emitPanZoom() {
    final focalDelta = _panZoomFocal - _lastFocalPoint;
    _lastFocalPoint = _panZoomFocal;
    widget.onGestureUpdate?.call(
      GestureState(
        type: GestureType.twoFingerDrag,
        pointers: const [],
        focalPoint: _panZoomFocal,
        focalDelta: focalDelta,
        span: _panZoomScale,
        spanScale: _panZoomScale,
      ),
    );
  }

  void _resetAllMovement() {
    for (final p in _pointers.values) {
      p.resetMovement();
    }
  }

  void _restartHoldTimer() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (_pointers.length == 1) {
      _holdTimer = Timer(widget.clickTimeout, _classify);
    }
  }

  double _computeSpan() {
    if (_pointers.length < 2) return 0;
    final pts = _pointers.values.map((p) => p.position).toList(growable: false);
    // Primary pinch metric: distance between the first two contacts.
    return (pts[0] - pts[1]).distance;
  }

  void _classify() {
    final count = _pointers.length;
    final slopThreshold = widget.dragSlopThreshold;
    final anyMoved =
        _pointers.values.any((p) => p.displacement > slopThreshold);

    final Offset focalPoint;
    if (count == 0) {
      focalPoint = Offset.zero;
    } else {
      focalPoint = _pointers.values
              .map((p) => p.position)
              .reduce((a, b) => a + b) /
          count.toDouble();
    }

    final span = _computeSpan();
    if (count != _lastPointerCount) {
      _lastPointerCount = count;
      _gestureStartSpan = span;
      // Re-baseline focal so the first frame after a count change has 0 delta.
      _lastFocalPoint = focalPoint;
    }

    final focalDelta = focalPoint - _lastFocalPoint;
    _lastFocalPoint = focalPoint;

    final spanScale = (count >= 2 && _gestureStartSpan > 1e-3)
        ? span / _gestureStartSpan
        : 1.0;

    final GestureType type;
    switch (count) {
      case 0:
        type = GestureType.idle;
      case 1:
        if (anyMoved) {
          type = GestureType.oneFingerDrag;
        } else {
          final tracker = _pointers.values.first;
          final elapsed = DateTime.now().difference(tracker.downTime);
          type = elapsed < widget.clickTimeout
              ? GestureType.oneFingerClick
              : GestureType.oneFingerHold;
        }
      case 2:
        type = anyMoved ? GestureType.twoFingerDrag : GestureType.twoFingerHold;
      default:
        type = anyMoved
            ? GestureType.threeFingerDrag
            : GestureType.threeFingerHold;
    }

    final snapshots = _pointers.values
        .map((p) => PointerSnapshot(
              pointerId: p.pointerId,
              position: p.position,
              initialPosition: p.initialPosition,
              displacement: p.displacement,
              totalDistance: p.totalDistance,
              hasMoved: p.displacement > slopThreshold,
            ))
        .toList(growable: false);

    widget.onGestureUpdate?.call(GestureState(
      type: type,
      pointers: snapshots,
      focalPoint: focalPoint,
      focalDelta: focalDelta,
      span: span,
      spanScale: spanScale,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      onPointerPanZoomStart: _onPanZoomStart,
      onPointerPanZoomUpdate: _onPanZoomUpdate,
      onPointerPanZoomEnd: _onPanZoomEnd,
      behavior: HitTestBehavior.opaque,
      child: widget.child,
    );
  }
}

class _PointerTracker {
  _PointerTracker({required this.pointerId, required this.position})
      : initialPosition = position,
        anchorPosition = position,
        downTime = DateTime.now(),
        totalDistance = 0;

  final int pointerId;
  Offset position;
  final Offset initialPosition;
  final DateTime downTime;

  /// Resets on finger-count changes; used for displacement-based slop check.
  Offset anchorPosition;
  double totalDistance;

  /// Straight-line distance from anchor — immune to jitter accumulation.
  double get displacement => (position - anchorPosition).distance;

  void update(Offset newPosition) {
    totalDistance += (newPosition - position).distance;
    position = newPosition;
  }

  void resetMovement() {
    anchorPosition = position;
    totalDistance = 0;
  }
}
